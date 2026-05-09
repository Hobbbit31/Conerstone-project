"""Tkinter dashboard for the parallel VHDL simulator.

Pure-stdlib UI (no pip installs): upload a .vhd file, pick how many
OpenMP threads to run on, and visualize the scaling behaviour of the
simulator. All paths are resolved relative to this file's location so
the dashboard is portable — clone the repo anywhere and it just works.
"""

from __future__ import annotations

import os
import queue
import re
import shutil
import subprocess
import threading
import time
import tkinter as tk
from dataclasses import dataclass
from pathlib import Path
from tkinter import filedialog, messagebox, ttk


# ──────────────────────────────────────────────────────────────────────
# Paths — derived from this file's location, nothing hard-coded.
# ──────────────────────────────────────────────────────────────────────

UI_DIR       = Path(__file__).resolve().parent
PROJECT_DIR  = UI_DIR.parent                 # ../ relative to ui/
UPLOADS_REL  = Path("ui_uploads")            # relative to PROJECT_DIR
VCDS_REL     = Path("ui_output")             # relative to PROJECT_DIR
EXAMPLES_REL = Path("test_vhdl")             # bundled examples


def _detect_binary_rel() -> Path:
    env_rel = os.environ.get("VHDL_SIM_BIN_REL")
    if env_rel:
        p = Path(env_rel)
        if p.parts and p.parts[0] == "..":
            p = Path(*p.parts[1:])
        return p

    is_windows = os.name == "nt"
    exe_path  = PROJECT_DIR / "simulator.exe"
    unix_path = PROJECT_DIR / "simulator"
    if is_windows and exe_path.exists():
        return Path("simulator.exe")
    if unix_path.exists():
        return Path("simulator")
    if exe_path.exists():
        return Path("simulator.exe")
    return Path("simulator")


SIM_BIN_REL = _detect_binary_rel()
ELAPSED_RE  = re.compile(r"Elapsed:\s*([0-9.eE+\-]+)\s*ms", re.IGNORECASE)
SIM_TIME_RE = re.compile(
    r"Simulation time:\s*([0-9.eE+\-]+)\s*(ms|s)\b", re.IGNORECASE)

def _get_cpu_count() -> int:
    try:
        # sched_getaffinity is more accurate on Linux for active cores
        return len(os.sched_getaffinity(0))
    except (AttributeError, NotImplementedError):
        return os.cpu_count() or 8

CPU_COUNT = _get_cpu_count()
# If the user has 8 physical cores, we might want to prioritize showing 8 
# if the system reports 16 due to hyper-threading.
if CPU_COUNT > 8:
    CPU_COUNT = 8 

(PROJECT_DIR / UPLOADS_REL).mkdir(exist_ok=True)
(PROJECT_DIR / VCDS_REL).mkdir(exist_ok=True)


# ──────────────────────────────────────────────────────────────────────
# Canvas-based Dependency Graph (DAG) visualizer
# ──────────────────────────────────────────────────────────────────────

class GraphCanvas(tk.Canvas):
    def __init__(self, master, **kw):
        super().__init__(master, bg=PALETTE["card"], highlightthickness=0, **kw)
        self.processes = []
        self.layers_count = 0
        self.msg = ""
        self.node_radius = 28
        self.col_spacing = 240
        self.row_spacing = 100
        self.margin_x = 100
        self.margin_y = 80
        self.bind("<Configure>", lambda _e: self._redraw())

    def set_data(self, processes, layers_count, msg=""):
        self.processes = processes
        self.layers_count = layers_count
        self.msg = msg
        self._redraw()

    def _redraw(self):
        self.delete("all")
        if not self.processes:
            display_msg = self.msg or "No graph data available."
            self.create_text(self.winfo_width()//2, self.winfo_height()//2,
                             text=display_msg, fill=PALETTE["muted"],
                             font=(FONT_FAMILY, 11, "italic"))
            return

        # 1. Group processes and identify ALL unique signals
        layers = [[] for _ in range(self.layers_count)]
        signal_to_writer = {}
        all_signals = set()
        
        for p in self.processes:
            if 0 <= p['layer'] < self.layers_count:
                layers[p['layer']].append(p)
            for s in p['outputs']:
                signal_to_writer[s] = p['name']
                all_signals.add(s)
            for s in p['inputs']:
                all_signals.add(s)

        # Identify 'External' signals (no writer process)
        external_signals = [s for s in all_signals if s not in signal_to_writer]
        
        # 2. Calculate coordinates
        max_rows = max(len(l) for l in layers) if layers else 0
        # If we have external inputs, we'll imagine a virtual 'Layer -1'
        eff_layers = self.layers_count + (1 if external_signals else 0)
        
        needed_w = (eff_layers - 1) * self.col_spacing + 2 * self.margin_x
        needed_h = (max_rows - 1) * self.row_spacing + 2 * self.margin_y
        canvas_mid_y = max(needed_h, self.winfo_height()) / 2

        self.configure(scrollregion=(0, 0, max(needed_w, self.winfo_width()), 
                                     max(needed_h, self.winfo_height())))

        node_coords = {}
        layer_offset = 1 if external_signals else 0
        
        # Virtual nodes for external inputs
        if external_signals:
            ex_x = self.margin_x
            ex_h = (len(external_signals) - 1) * (self.row_spacing * 0.6)
            ex_start_y = canvas_mid_y - (ex_h / 2)
            for i, s in enumerate(external_signals):
                sy = ex_start_y + i * (self.row_spacing * 0.6)
                node_coords[f"__ext_{s}"] = (ex_x, sy)
                # Draw small marker for external input
                self.create_text(ex_x - 10, sy, text=s, anchor="e", 
                                 fill=PALETTE["muted"], font=(FONT_FAMILY, 8))
                self.create_oval(ex_x-4, sy-4, ex_x+4, sy+4, fill=PALETTE["border"])

        for l_idx, layer_procs in enumerate(layers):
            x = self.margin_x + (l_idx + layer_offset) * self.col_spacing
            layer_h = (len(layer_procs) - 1) * self.row_spacing
            start_y = canvas_mid_y - (layer_h / 2)
            for p_idx, p in enumerate(layer_procs):
                y = start_y + p_idx * self.row_spacing
                node_coords[p['name']] = (x, y)

        # 3. Draw EVERY Edge
        import math
        for p in self.processes:
            if p['name'] not in node_coords: continue
            dx, dy = node_coords[p['name']]
            
            for s in p['inputs']:
                src_x, src_y = (None, None)
                if s in signal_to_writer:
                    src_name = signal_to_writer[s]
                    if src_name in node_coords:
                        src_x, src_y = node_coords[src_name]
                elif f"__ext_{s}" in node_coords:
                    src_x, src_y = node_coords[f"__ext_{s}"]
                
                if src_x is not None:
                    # Calculate angle for clean landing
                    angle = math.atan2(dy - src_y, dx - src_x)
                    # Start from edge of source node (or marker)
                    is_ext = s not in signal_to_writer
                    r_src = 4 if is_ext else self.node_radius
                    sx = src_x + (r_src + 2) * math.cos(angle)
                    sy = src_y + (r_src + 2) * math.sin(angle)
                    # End at edge of destination node
                    ex = dx - (self.node_radius + 6) * math.cos(angle)
                    ey = dy - (self.node_radius + 6) * math.sin(angle)
                    
                    self.create_line(sx, sy, ex, ey,
                                     fill=PALETTE["border_hi"], width=1.2,
                                     arrow=tk.LAST, arrowshape=(9, 11, 4),
                                     smooth=True)

        # 4. Draw Nodes
        for p in self.processes:
            if p['name'] not in node_coords: continue
            x, y = node_coords[p['name']]
            color = LineChart.COLORS[p['layer'] % len(LineChart.COLORS)]
            self.create_oval(x - self.node_radius, y - self.node_radius,
                             x + self.node_radius, y + self.node_radius,
                             fill=PALETTE["card_soft"], outline=color, width=2)
            self.create_text(x, y, text=p['name'], fill=PALETTE["text"],
                             font=(FONT_FAMILY, 9, "bold"), width=self.node_radius*2-8,
                             justify="center")


# ──────────────────────────────────────────────────────────────────────
# Modern palette — used by the ttk style setup below.
# ──────────────────────────────────────────────────────────────────────

PALETTE = {
    "bg":          "#0f1419",   # app background
    "card":        "#1a1f2a",   # panels / cards
    "card_soft":   "#242935",   # inputs / subtle surfaces
    "text":        "#e5e7ec",   # primary text
    "muted":       "#8b92a0",   # secondary text
    "border":      "#2d3544",
    "border_hi":   "#3a4458",
    "accent":      "#60a5fa",   # soft blue
    "accent_hov":  "#93c5fd",
    "accent_pr":   "#3b82f6",
    "accent_glow": "#bfdbfe",
    "success":     "#86efac",
    "danger":      "#fca5a5",
    "warn":        "#fcd34d",
    "magenta":     "#c4b5fd",
    "chart_a":     "#60a5fa",
    "chart_b":     "#c4b5fd",
    "chart_c":     "#86efac",
    "chart_d":     "#fcd34d",
}

FONT_FAMILY = "Segoe UI"   # Tk falls back gracefully if unavailable


# ──────────────────────────────────────────────────────────────────────
# Simulator invocation
# ──────────────────────────────────────────────────────────────────────

@dataclass
class RunResult:
    threads:    int
    sim_ms:     float | None
    wall_ms:    float
    returncode: int
    stdout:     str
    stderr:     str
    vcd_path:   Path
    is_seq:     bool = False

    @property
    def ok(self) -> bool:
        return self.returncode == 0 and self.sim_ms is not None


def run_simulator(vhd_rel: Path, threads: int, tag: str,
                  vcd_dir: Path, seq: bool = False) -> RunResult:
    """Invoke the simulator.

    `seq=True` adds the simulator's `-seq` flag for a true single-threaded
    baseline with no OpenMP overhead. Otherwise the run uses OpenMP with
    `threads` worker threads (even when threads == 1).
    """
    vcd_dir = Path(vcd_dir).expanduser().resolve()
    vcd_dir.mkdir(parents=True, exist_ok=True)
    vcd_path = vcd_dir / f"{Path(vhd_rel).stem}_{tag}_t{threads}.vcd"

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    env["OMP_WAIT_POLICY"] = "active"

    bin_arg = str(SIM_BIN_REL)
    if not bin_arg.startswith((".", "/")) and os.sep != "\\":
        bin_arg = f"./{bin_arg}"

    cmd = [bin_arg, str(vhd_rel), str(vcd_path), "-dep"]
    if seq:
        cmd.append("-seq")

    t0 = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(PROJECT_DIR),
        env=env,
        capture_output=True,
        text=True,
    )
    wall_ms = (time.perf_counter() - t0) * 1000.0

    sim_ms: float | None = None
    # Prioritize 'Elapsed: ... ms' from Simulator.cpp
    m_elap = ELAPSED_RE.search(proc.stdout)
    if m_elap:
        sim_ms = float(m_elap.group(1))
    else:
        # Fallback to 'Simulation time: ...' from main.cpp
        m_sim = SIM_TIME_RE.search(proc.stdout)
        if m_sim:
            val = float(m_sim.group(1))
            sim_ms = val if m_sim.group(2).lower() == "ms" else val * 1000.0

    return RunResult(
        threads=threads, sim_ms=sim_ms, wall_ms=wall_ms,
        returncode=proc.returncode, stdout=proc.stdout, stderr=proc.stderr,
        vcd_path=vcd_path, is_seq=seq,
    )


def default_thread_sweep(max_threads: int) -> list[int]:
    # Linear sweep from 1 to 8 as requested
    return list(range(1, 9))


# ──────────────────────────────────────────────────────────────────────
# Canvas-based line chart (keeps the app stdlib-only)
# ──────────────────────────────────────────────────────────────────────

class LineChart(tk.Canvas):
    PAD_L, PAD_R, PAD_T, PAD_B = 58, 24, 32, 40
    COLORS = (PALETTE["chart_a"], PALETTE["chart_b"],
              PALETTE["chart_c"], PALETTE["chart_d"])

    def __init__(self, master, title: str, ylabel: str, **kw):
        super().__init__(master, bg=PALETTE["card"], highlightthickness=1,
                         highlightbackground=PALETTE["border"], **kw)
        self.title  = title
        self.ylabel = ylabel
        self.series: list[tuple[str, list[tuple[float, float]]]] = []
        self.bind("<Configure>", lambda _e: self._redraw())

    def set_series(self, series):
        self.series = series
        self._redraw()

    def _redraw(self):
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        if w <= 20 or h <= 20:
            return

        self.create_text(w // 2, 16, text=self.title,
                         fill=PALETTE["text"],
                         font=(FONT_FAMILY, 11, "bold"))

        all_pts = [p for _, pts in self.series for p in pts]
        if not all_pts:
            self.create_text(w // 2, h // 2, text="(no data)",
                             fill=PALETTE["muted"],
                             font=(FONT_FAMILY, 10, "italic"))
            return

        xs = [p[0] for p in all_pts]
        ys = [p[1] for p in all_pts]
        xmin, xmax = min(xs), max(xs)
        ymin, ymax = min(ys + [0]), max(ys)
        if xmax == xmin: xmax = xmin + 1
        if ymax == ymin: ymax = ymin + 1

        pl, pr = self.PAD_L, w - self.PAD_R
        pt, pb = self.PAD_T, h - self.PAD_B

        def sx(x): return pl + (x - xmin) / (xmax - xmin) * (pr - pl)
        def sy(y): return pb - (y - ymin) / (ymax - ymin) * (pb - pt)

        # Plot background
        self.create_rectangle(pl, pt, pr, pb,
                              fill=PALETTE["card_soft"], outline="")

        # Gridlines + Y labels
        for i in range(5):
            yv = ymin + (ymax - ymin) * i / 4
            yp = sy(yv)
            self.create_line(pl, yp, pr, yp, fill=PALETTE["border"])
            self.create_text(pl - 8, yp, text=f"{yv:.2f}",
                             anchor="e", fill=PALETTE["muted"],
                             font=(FONT_FAMILY, 8))

        # Axes
        self.create_line(pl, pb, pr, pb, fill=PALETTE["border"])
        self.create_line(pl, pb, pl, pt, fill=PALETTE["border"])

        unique_xs = sorted(set(xs))
        if len(unique_xs) > 10:
            step = max(1, len(unique_xs) // 10)
            unique_xs = unique_xs[::step]
        for xv in unique_xs:
            xp = sx(xv)
            self.create_line(xp, pb, xp, pb + 4, fill=PALETTE["border"])
            self.create_text(xp, pb + 14,
                             text=str(int(xv) if xv == int(xv) else f"{xv:.2f}"),
                             fill=PALETTE["muted"],
                             font=(FONT_FAMILY, 8))

        self.create_text((pl + pr) // 2, h - 8,
                         text="Threads", fill=PALETTE["muted"],
                         font=(FONT_FAMILY, 9, "italic"))
        self.create_text(14, (pt + pb) // 2, text=self.ylabel,
                         angle=90, fill=PALETTE["muted"],
                         font=(FONT_FAMILY, 9, "italic"))

        legend_x = pr - 150
        legend_y = pt + 6
        for idx, (name, pts) in enumerate(self.series):
            color = self.COLORS[idx % len(self.COLORS)]
            if len(pts) >= 2:
                flat = []
                for x, y in pts:
                    flat += [sx(x), sy(y)]
                self.create_line(*flat, fill=color, width=2, smooth=False)
            for x, y in pts:
                px, py = sx(x), sy(y)
                self.create_oval(px - 3, py - 3, px + 3, py + 3,
                                 fill=color, outline=color)
            self.create_line(legend_x, legend_y + idx * 16 + 7,
                             legend_x + 20, legend_y + idx * 16 + 7,
                             fill=color, width=2)
            self.create_text(legend_x + 24, legend_y + idx * 16 + 7,
                             text=name, anchor="w",
                             fill=PALETTE["text"],
                             font=(FONT_FAMILY, 9))


# ──────────────────────────────────────────────────────────────────────
# Rounded card container — draws a rounded-rectangle background on a
# Canvas and hosts a regular Frame (`.inner`) inside it. All children go
# into `.inner`. Tk/ttk don't natively do border-radius, so we fake it.
# ──────────────────────────────────────────────────────────────────────

class RoundedCard(tk.Canvas):
    def __init__(self, master, *, radius=14, card_bg=None,
                 parent_bg=None, border=None, pad=14, **kw):
        super().__init__(master,
                         bg=parent_bg or PALETTE["bg"],
                         highlightthickness=0, bd=0, **kw)
        self.radius    = radius
        self.card_bg   = card_bg or PALETTE["card"]
        self.border    = border
        self.pad       = pad
        self.inner     = tk.Frame(self, bg=self.card_bg)
        self._win      = self.create_window(pad, pad, anchor="nw",
                                             window=self.inner)
        self.bind("<Configure>", self._on_configure)

    def _on_configure(self, event):
        w, h = event.width, event.height
        self.delete("rr")
        self._draw_rounded(0, 0, w, h)
        self.tag_lower("rr")
        self.itemconfigure(self._win,
                            width=max(0, w - 2 * self.pad),
                            height=max(0, h - 2 * self.pad))

    def _draw_rounded(self, x1, y1, x2, y2):
        r = self.radius
        pts = [x1 + r, y1, x2 - r, y1, x2, y1,
               x2, y1 + r, x2, y2 - r, x2, y2,
               x2 - r, y2, x1 + r, y2, x1, y2,
               x1, y2 - r, x1, y1 + r, x1, y1]
        self.create_polygon(
            pts, smooth=True,
            fill=self.card_bg,
            outline=self.border or "",
            width=1 if self.border else 0,
            tags="rr",
        )


# ──────────────────────────────────────────────────────────────────────
# Main application
# ──────────────────────────────────────────────────────────────────────

class Dashboard(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Parallel VHDL Simulator — Dashboard")
        self.geometry("1500x960")
        self.minsize(1120, 740)
        self.configure(bg=PALETTE["bg"])

        self.vhd_rel: Path | None = None
        self.worker: threading.Thread | None = None
        self.msg_queue: queue.Queue = queue.Queue()
        self.bench_rows: dict[int, RunResult] = {}
        self.last_vcd: Path | None = None
        self.vcd_dir_var = tk.StringVar(
            value=str((PROJECT_DIR / VCDS_REL).resolve()))

        self._setup_style()
        self._build_layout()
        self._refresh_env_panel()
        self._poll_queue()

    # ── Styling ──────────────────────────────────────────────────────
    def _setup_style(self):
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        P = PALETTE

        style.configure(".", background=P["bg"], foreground=P["text"],
                        font=(FONT_FAMILY, 10))
        style.configure("TFrame", background=P["bg"])
        style.configure("Card.TFrame", background=P["card"], relief="flat")
        style.configure("Header.TFrame", background=P["card"])

        style.configure("TLabel", background=P["bg"], foreground=P["text"])
        style.configure("Card.TLabel", background=P["card"], foreground=P["text"])
        style.configure("Muted.TLabel", background=P["bg"],
                        foreground=P["muted"], font=(FONT_FAMILY, 9))
        style.configure("CardMuted.TLabel", background=P["card"],
                        foreground=P["muted"], font=(FONT_FAMILY, 9))
        style.configure("H1.TLabel", background=P["card"], foreground=P["text"],
                        font=(FONT_FAMILY, 16, "bold"))
        style.configure("H2.TLabel", background=P["bg"], foreground=P["text"],
                        font=(FONT_FAMILY, 12, "bold"))
        style.configure("H3.TLabel", background=P["bg"], foreground=P["text"],
                        font=(FONT_FAMILY, 10, "bold"))
        style.configure("Accent.TLabel", background=P["card"],
                        foreground=P["accent"], font=(FONT_FAMILY, 10, "bold"))
        style.configure("Metric.TLabel", background=P["card"],
                        foreground=P["accent"],
                        font=(FONT_FAMILY, 20, "bold"))
        style.configure("MetricLabel.TLabel", background=P["card"],
                        foreground=P["muted"],
                        font=(FONT_FAMILY, 9, "bold"))
        style.configure("Status.TLabel", background=P["bg"],
                        foreground=P["muted"], font=(FONT_FAMILY, 9))
        style.configure("Success.TLabel", background=P["bg"],
                        foreground=P["success"],
                        font=(FONT_FAMILY, 10, "bold"))

        style.configure("TButton", padding=(12, 7),
                        font=(FONT_FAMILY, 10), borderwidth=0,
                        background=P["card_soft"], foreground=P["text"])
        style.map("TButton",
                  background=[("active", P["border"]),
                              ("pressed", P["border_hi"])])

        style.configure("Accent.TButton", padding=(14, 9),
                        background=P["accent"], foreground="#061018",
                        font=(FONT_FAMILY, 10, "bold"), borderwidth=0)
        style.map("Accent.TButton",
                  background=[("active", P["accent_hov"]),
                              ("pressed", P["accent_pr"]),
                              ("disabled", "#2a3147")],
                  foreground=[("disabled", P["muted"])])

        style.configure("Ghost.TButton", padding=(10, 6),
                        background=P["card"], foreground=P["accent"],
                        font=(FONT_FAMILY, 10), borderwidth=1,
                        bordercolor=P["border_hi"],
                        lightcolor=P["border_hi"],
                        darkcolor=P["border_hi"])
        style.map("Ghost.TButton",
                  background=[("active", P["card_soft"])],
                  foreground=[("active", P["accent_hov"])])

        style.configure("TEntry", fieldbackground=P["card_soft"],
                        background=P["card_soft"], foreground=P["text"],
                        insertcolor=P["accent"],
                        bordercolor=P["border"], lightcolor=P["border"],
                        darkcolor=P["border"], padding=6)
        style.map("TEntry",
                  bordercolor=[("focus", P["accent"])],
                  lightcolor=[("focus", P["accent"])],
                  darkcolor=[("focus", P["accent"])])
        style.configure("TSpinbox", fieldbackground=P["card_soft"],
                        background=P["card_soft"], foreground=P["text"],
                        bordercolor=P["border"], arrowcolor=P["accent"],
                        insertcolor=P["accent"], padding=4)

        style.configure("TNotebook", background=P["bg"], borderwidth=0)
        style.configure("TNotebook.Tab", background=P["bg"],
                        foreground=P["muted"], padding=(14, 8),
                        font=(FONT_FAMILY, 10, "bold"), borderwidth=0)
        style.map("TNotebook.Tab",
                  background=[("selected", P["card"])],
                  foreground=[("selected", P["accent"])])

        style.configure("Treeview", background=P["card"], foreground=P["text"],
                        fieldbackground=P["card"], rowheight=28,
                        bordercolor=P["border"], borderwidth=0,
                        font=(FONT_FAMILY, 10))
        style.configure("Treeview.Heading", background=P["card_soft"],
                        foreground=P["accent"], borderwidth=0,
                        font=(FONT_FAMILY, 10, "bold"), padding=(8, 8),
                        relief="flat")
        style.map("Treeview.Heading",
                  background=[("active", P["border"])])
        style.map("Treeview",
                  background=[("selected", P["border_hi"])],
                  foreground=[("selected", P["accent_glow"])])

        style.configure("Card.TLabelframe", background=P["card"],
                        bordercolor=P["border"], borderwidth=1,
                        relief="solid", padding=12)
        style.configure("Card.TLabelframe.Label", background=P["card"],
                        foreground=P["muted"],
                        font=(FONT_FAMILY, 9, "bold"))

        style.configure("Accent.Horizontal.TProgressbar",
                        background=P["accent"], troughcolor=P["card_soft"],
                        bordercolor=P["card_soft"],
                        lightcolor=P["accent"], darkcolor=P["accent"],
                        borderwidth=0, thickness=6)

        style.configure("TSeparator", background=P["border"])

    # ── Layout ───────────────────────────────────────────────────────
    def _build_layout(self):
        P = PALETTE

        # Header: rounded card sitting in a bg-colored frame.
        header_wrap = tk.Frame(self, bg=P["bg"])
        header_wrap.pack(fill=tk.X, side=tk.TOP, padx=14, pady=(14, 0))
        header_card = RoundedCard(header_wrap, radius=14, pad=0,
                                   parent_bg=P["bg"],
                                   border=P["border"], height=64)
        header_card.pack(fill=tk.X)
        hinner = header_card.inner
        hinner.configure(bg=P["card"])
        tk.Label(hinner, text="  Parallel VHDL Simulator",
                 bg=P["card"], fg=P["text"],
                 font=(FONT_FAMILY, 16, "bold"))\
            .pack(side=tk.LEFT, padx=18, pady=14)
        tk.Label(hinner, text="Scaling dashboard",
                 bg=P["card"], fg=P["muted"],
                 font=(FONT_FAMILY, 10))\
            .pack(side=tk.LEFT, padx=(0, 20), pady=20)

        outer = ttk.Frame(self)
        outer.pack(fill=tk.BOTH, expand=True, padx=14, pady=14)

        main = ttk.PanedWindow(outer, orient=tk.HORIZONTAL)
        main.pack(fill=tk.BOTH, expand=True)

        # ── Left: controls (rounded card) ────────────────────────
        left_wrap = ttk.Frame(main)
        main.add(left_wrap, weight=0)

        left_card = RoundedCard(left_wrap, radius=16, pad=0,
                                 parent_bg=P["bg"],
                                 border=P["border"],
                                 width=340)
        left_card.pack(fill=tk.BOTH, expand=True)
        left = left_card.inner

        lpad = {"padx": 16}

        def cardlabel(text, font_style="H3.TLabel", pady=(0, 4), **kw):
            lbl = tk.Label(left, text=text, bg=P["card"], fg=P["text"],
                           anchor="w", **kw)
            # Apply style manually since it's on a tk.Frame not ttk
            if "H3" in font_style:
                lbl.configure(font=(FONT_FAMILY, 10, "bold"))
            elif "Muted" in font_style:
                lbl.configure(font=(FONT_FAMILY, 9), fg=P["muted"])
            lbl.pack(anchor="w", pady=pady, **lpad)
            return lbl

        tk.Label(left, text="Run configuration", bg=P["card"],
                 fg=P["text"], font=(FONT_FAMILY, 13, "bold"))\
            .pack(anchor="w", padx=16, pady=(16, 2))
        tk.Label(left, text="Configure inputs and launch simulations.",
                 bg=P["card"], fg=P["muted"],
                 font=(FONT_FAMILY, 9))\
            .pack(anchor="w", padx=16, pady=(0, 14))

        # Input file
        cardlabel("VHDL input file")
        self.file_var = tk.StringVar(value="(none selected)")
        tk.Label(left, textvariable=self.file_var, bg=P["card"],
                 fg=P["accent"], anchor="w",
                 font=(FONT_FAMILY, 9, "bold"))\
            .pack(anchor="w", padx=16, pady=(0, 4))
        row = tk.Frame(left, bg=P["card"]); row.pack(fill=tk.X, padx=16, pady=(0, 14))
        ttk.Button(row, text="Upload .vhd…", style="Accent.TButton",
                   command=self._pick_file).pack(side=tk.LEFT)
        ttk.Button(row, text="Example…", style="Ghost.TButton",
                   command=self._pick_example).pack(side=tk.LEFT, padx=6)

        # Threads for single run
        cardlabel("OpenMP threads (single run)")
        self.threads_var = tk.IntVar(value=min(4, CPU_COUNT))
        tk.Spinbox(left, from_=1, to=max(CPU_COUNT, 64),
                   textvariable=self.threads_var, width=10,
                   relief="flat", bg=PALETTE["card_soft"],
                   fg=PALETTE["text"],
                   buttonbackground=PALETTE["card_soft"],
                   insertbackground=PALETTE["accent"],
                   highlightthickness=1,
                   highlightbackground=PALETTE["border"],
                   font=(FONT_FAMILY, 10))\
            .pack(anchor="w", padx=16, pady=(0, 14))

        # VCD output directory
        cardlabel("VCD output directory")
        ttk.Entry(left, textvariable=self.vcd_dir_var)\
            .pack(fill=tk.X, padx=16, pady=(0, 4))
        out_row = tk.Frame(left, bg=P["card"])
        out_row.pack(fill=tk.X, padx=16, pady=(0, 14))
        ttk.Button(out_row, text="Browse…", style="Ghost.TButton",
                   command=self._pick_vcd_dir).pack(side=tk.LEFT)
        ttk.Button(out_row, text="Reset", style="Ghost.TButton",
                   command=self._reset_vcd_dir).pack(side=tk.LEFT, padx=6)

        ttk.Separator(left, orient="horizontal").pack(fill=tk.X, padx=16, pady=10)

        tk.Label(left, text="Benchmark sweep", bg=P["card"],
                 fg=P["text"], font=(FONT_FAMILY, 12, "bold"))\
            .pack(anchor="w", padx=16, pady=(0, 2))
        tk.Label(left,
                 text="Runs a -seq baseline, then each thread count (no -seq).",
                 bg=P["card"], fg=P["muted"],
                 font=(FONT_FAMILY, 9))\
            .pack(anchor="w", padx=16, pady=(0, 10))

        cardlabel("Thread counts (comma-sep)")
        self.sweep_var = tk.StringVar(
            value=",".join(str(t) for t in default_thread_sweep(CPU_COUNT)))
        ttk.Entry(left, textvariable=self.sweep_var)\
            .pack(fill=tk.X, padx=16, pady=(0, 10))

        cardlabel("Repeats per thread count")
        self.repeats_var = tk.IntVar(value=1)
        tk.Spinbox(left, from_=1, to=10, textvariable=self.repeats_var,
                   width=10, relief="flat", bg=PALETTE["card_soft"],
                   fg=PALETTE["text"],
                   buttonbackground=PALETTE["card_soft"],
                   insertbackground=PALETTE["accent"],
                   highlightthickness=1,
                   highlightbackground=PALETTE["border"],
                   font=(FONT_FAMILY, 10))\
            .pack(anchor="w", padx=16, pady=(0, 14))

        # Buttons
        self.btn_single = ttk.Button(left, text="▶   Run single",
                                      style="Accent.TButton",
                                      command=self._on_run_single)
        self.btn_single.pack(fill=tk.X, padx=16, pady=(4, 6))
        self.btn_bench = ttk.Button(left, text="⚡   Run benchmark sweep",
                                     style="Accent.TButton",
                                     command=self._on_run_bench)
        self.btn_bench.pack(fill=tk.X, padx=16, pady=(0, 14))

        ttk.Separator(left, orient="horizontal").pack(fill=tk.X, padx=16, pady=(4, 10))

        tk.Label(left, text="Environment", bg=P["card"],
                 fg=P["text"], font=(FONT_FAMILY, 10, "bold"))\
            .pack(anchor="w", padx=16)
        self.env_text = tk.Text(left, height=7, wrap="word",
                                 relief="flat", bg=P["card_soft"],
                                 fg=P["accent_glow"],
                                 font=("Consolas", 9),
                                 highlightthickness=1,
                                 highlightbackground=P["border"])
        self.env_text.pack(fill=tk.X, padx=16, pady=(6, 16))
        self.env_text.configure(state="disabled")

        # ── Right: results ───────────────────────────────────────
        right = ttk.Frame(main)
        main.add(right, weight=1)

        # Status bar row
        status = ttk.Frame(right)
        status.pack(fill=tk.X)
        self.status_var = tk.StringVar(value="Ready.")
        ttk.Label(status, textvariable=self.status_var,
                  style="Status.TLabel").pack(side=tk.LEFT, padx=4, pady=2)
        self.progress = ttk.Progressbar(
            status, mode="determinate", length=240,
            style="Accent.Horizontal.TProgressbar")
        self.progress.pack(side=tk.RIGHT, padx=4, pady=2)

        # Metric cards
        metrics_wrap = ttk.Frame(right)
        metrics_wrap.pack(fill=tk.X, pady=(10, 6))
        self.m_threads = self._metric_card(metrics_wrap, "THREADS", 0)
        self.m_sim     = self._metric_card(metrics_wrap, "SIM TIME (MS)", 1)
        self.m_wall    = self._metric_card(metrics_wrap, "WALL TIME (MS)", 2)
        self.m_vcd     = self._metric_card(metrics_wrap, "VCD SIZE (KB)", 3)
        for c in range(4):
            metrics_wrap.columnconfigure(c, weight=1, uniform="metric")

        # Actions on the latest VCD (rounded card)
        actions_card = RoundedCard(right, radius=12, pad=0,
                                    parent_bg=P["bg"],
                                    border=P["border"], height=60)
        actions_card.pack(fill=tk.X, pady=(0, 8))
        actions = actions_card.inner
        actions.configure(bg=P["card"])
        self.btn_gtkwave = ttk.Button(actions, text="🔍  Open in GTKWave",
                                        style="Ghost.TButton",
                                        command=self._open_in_gtkwave)
        self.btn_gtkwave.pack(side=tk.LEFT, padx=14, pady=12)
        self.btn_gtkwave.configure(state="disabled")
        self.vcd_caption_var = tk.StringVar(value="No VCD yet — run the simulator.")
        tk.Label(actions, textvariable=self.vcd_caption_var,
                 bg=P["card"], fg=P["muted"],
                 font=(FONT_FAMILY, 9)).pack(side=tk.LEFT, padx=8, pady=12)

        # Notebook
        nb = ttk.Notebook(right)
        nb.pack(fill=tk.BOTH, expand=True, pady=(4, 0))

        # Benchmark table
        tab_bench = tk.Frame(nb, bg=P["card"])
        nb.add(tab_bench, text="  Benchmark table  ")
        cols = ("Threads", "Sim (ms)", "Wall (ms)", "Speedup", "Efficiency", "Status")
        tree_wrap = tk.Frame(tab_bench, bg=P["card"])
        tree_wrap.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        self.tree = ttk.Treeview(tree_wrap, columns=cols, show="headings",
                                  height=11)
        for c, w in zip(cols, (100, 130, 130, 120, 120, 100)):
            self.tree.heading(c, text=c)
            self.tree.column(c, width=w, anchor="center")
        self.tree.tag_configure("seq", background="#2a1f0b",
                                 foreground=P["warn"])
        self.tree.tag_configure("best", background="#0e2a1a",
                                 foreground=P["success"])
        self.tree.pack(fill=tk.BOTH, expand=True)
        self.summary_var = tk.StringVar(value="")
        tk.Label(tab_bench, textvariable=self.summary_var,
                 bg=P["card"], fg=P["success"],
                 font=(FONT_FAMILY, 10, "bold"))\
            .pack(anchor="w", padx=10, pady=(0, 10))

        # Charts
        tab_charts = tk.Frame(nb, bg=P["bg"])
        nb.add(tab_charts, text="  Charts  ")
        self.chart_time    = LineChart(tab_charts,
                                        "Elapsed time vs threads",
                                        "Wall time (ms)", height=220)
        self.chart_speedup = LineChart(tab_charts,
                                        "Speedup vs threads (Elapsed-time based)",
                                        "Speedup (T_seq / Tn)", height=220)
        self.chart_eff     = LineChart(tab_charts,
                                        "Parallel efficiency (speedup / threads)",
                                        "Efficiency", height=220)
        self.chart_time.pack(fill=tk.BOTH, expand=True, padx=10, pady=(10, 4))
        self.chart_speedup.pack(fill=tk.BOTH, expand=True, padx=10, pady=4)
        self.chart_eff.pack(fill=tk.BOTH, expand=True, padx=10, pady=(4, 10))

        # Dependency Graph
        tab_dep = tk.Frame(nb, bg=P["card"])
        nb.add(tab_dep, text="  Dependency Graph  ")
        
        graph_wrap = tk.Frame(tab_dep, bg=P["card"])
        graph_wrap.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        self.graph_canvas = GraphCanvas(graph_wrap)
        self.graph_canvas.pack(fill=tk.BOTH, expand=True, side=tk.LEFT)
        
        # Add scrollbars for the canvas
        sb_y = ttk.Scrollbar(graph_wrap, orient="vertical", command=self.graph_canvas.yview)
        sb_y.pack(side=tk.RIGHT, fill=tk.Y)
        sb_x = ttk.Scrollbar(tab_dep, orient="horizontal", command=self.graph_canvas.xview)
        sb_x.pack(side=tk.BOTTOM, fill=tk.X)
        self.graph_canvas.configure(yscrollcommand=sb_y.set, xscrollcommand=sb_x.set)

        # Output
        tab_out = tk.Frame(nb, bg=P["card"])
        nb.add(tab_out, text="  Simulator output  ")
        self.out_text = tk.Text(tab_out, wrap="word", height=10,
                                 font=("Consolas", 10),
                                 bg="#05070d", fg=P["accent_glow"],
                                 insertbackground=P["accent"],
                                 relief="flat", padx=12, pady=10,
                                 highlightthickness=1,
                                 highlightbackground=P["border"])
        self.out_text.pack(fill=tk.BOTH, expand=True, side=tk.LEFT,
                            padx=(10, 0), pady=10)
        sb = ttk.Scrollbar(tab_out, orient="vertical",
                            command=self.out_text.yview)
        sb.pack(fill=tk.Y, side=tk.RIGHT, padx=(0, 10), pady=10)
        self.out_text.configure(yscrollcommand=sb.set)

    def _metric_card(self, parent, label, col):
        P = PALETTE
        card = RoundedCard(parent, radius=12, pad=0,
                           parent_bg=P["bg"], border=P["border"],
                           height=86)
        card.grid(row=0, column=col, sticky="nsew",
                  padx=(0 if col == 0 else 10, 0))
        inner = card.inner
        inner.configure(bg=P["card"])
        tk.Label(inner, text=label, bg=P["card"], fg=P["muted"],
                 font=(FONT_FAMILY, 9, "bold"), anchor="w")\
            .pack(anchor="w", padx=14, pady=(12, 0))
        var = tk.StringVar(value="—")
        tk.Label(inner, textvariable=var, bg=P["card"], fg=P["accent"],
                 font=(FONT_FAMILY, 22, "bold"), anchor="w")\
            .pack(anchor="w", padx=14, pady=(0, 12))
        return var

    def _refresh_env_panel(self):
        sim_abs = PROJECT_DIR / SIM_BIN_REL
        info = (
            f"Project dir : .. (parent of ui/)\n"
            f"Simulator   : {SIM_BIN_REL}\n"
            f"Binary OK   : {sim_abs.exists()}\n"
            f"CPU cores   : {CPU_COUNT}\n"
            f"Uploads dir : {UPLOADS_REL}/\n"
            f"VCD out dir : {VCDS_REL}/\n"
        )
        self.env_text.configure(state="normal")
        self.env_text.delete("1.0", tk.END)
        self.env_text.insert("1.0", info)
        self.env_text.configure(state="disabled")

        if not sim_abs.exists():
            messagebox.showerror(
                "Simulator missing",
                f"Simulator binary not found at '{SIM_BIN_REL}' "
                "(relative to the project directory).\n\n"
                "Run ./run_dashboard.sh (which builds the project) first, "
                "or invoke 'make' in the parent directory.",
            )

    # ── GTKWave launch ───────────────────────────────────────────────
    def _open_in_gtkwave(self):
        if self.last_vcd is None or not self.last_vcd.exists():
            messagebox.showinfo("No VCD",
                                 "Run the simulator first to produce a .vcd file.")
            return
        if shutil.which("gtkwave") is None:
            messagebox.showerror(
                "GTKWave not found",
                "The `gtkwave` command is not on your PATH.\n\n"
                "Install it first:\n"
                "  Debian/Ubuntu/WSL : sudo apt install gtkwave\n"
                "  Fedora/RHEL       : sudo dnf install gtkwave\n"
                "  macOS (Homebrew)  : brew install --cask gtkwave\n"
                "  Windows           : download from gtkwave.sourceforge.net",
            )
            return
        try:
            subprocess.Popen(
                ["gtkwave", str(self.last_vcd)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
            )
            self.status_var.set(f"Opened {self.last_vcd.name} in GTKWave.")
        except OSError as e:
            messagebox.showerror("GTKWave launch failed", str(e))

    def _set_last_vcd(self, path: Path):
        self.last_vcd = path
        self.btn_gtkwave.configure(state="normal")
        self.vcd_caption_var.set(str(path))

    # ── Output directory ─────────────────────────────────────────────
    def _pick_vcd_dir(self):
        chosen = filedialog.askdirectory(
            title="Select output directory for .vcd files",
            initialdir=self.vcd_dir_var.get() or str(PROJECT_DIR),
            mustexist=False,
        )
        if chosen:
            self.vcd_dir_var.set(chosen)

    def _reset_vcd_dir(self):
        self.vcd_dir_var.set(str((PROJECT_DIR / VCDS_REL).resolve()))

    def _current_vcd_dir(self) -> Path:
        p = Path(self.vcd_dir_var.get() or str(PROJECT_DIR / VCDS_REL)).expanduser()
        p.mkdir(parents=True, exist_ok=True)
        return p

    # ── File selection ───────────────────────────────────────────────
    def _pick_file(self):
        path = filedialog.askopenfilename(
            title="Select a VHDL file",
            filetypes=[("VHDL files", "*.vhd *.vhdl"), ("All files", "*.*")],
        )
        if not path:
            return
        src = Path(path)
        dest_abs = PROJECT_DIR / UPLOADS_REL / src.name
        if src.resolve() != dest_abs.resolve():
            shutil.copy2(src, dest_abs)
        self.vhd_rel = UPLOADS_REL / src.name
        self.file_var.set(str(self.vhd_rel))

    def _pick_example(self):
        ex_dir = PROJECT_DIR / EXAMPLES_REL
        if not ex_dir.exists():
            messagebox.showwarning("No examples",
                                    f"{EXAMPLES_REL}/ is missing.")
            return
        choices = sorted(p.name for p in ex_dir.glob("*.vhd"))
        if not choices:
            messagebox.showwarning("No examples",
                                    "No .vhd files in test_vhdl/.")
            return

        dlg = tk.Toplevel(self)
        dlg.title("Pick a bundled example")
        dlg.configure(bg=PALETTE["card"])
        dlg.transient(self); dlg.grab_set()
        tk.Label(dlg, text="Select a bundled VHDL example:",
                 bg=PALETTE["card"], fg=PALETTE["text"],
                 font=(FONT_FAMILY, 10, "bold"))\
            .pack(padx=14, pady=(14, 6), anchor="w")
        lst = tk.Listbox(dlg, width=42, height=min(len(choices), 14),
                         relief="flat", bg=PALETTE["card_soft"],
                         fg=PALETTE["text"],
                         selectbackground=PALETTE["accent"],
                         selectforeground="#061018",
                         highlightthickness=1,
                         highlightbackground=PALETTE["border"],
                         borderwidth=0,
                         font=(FONT_FAMILY, 10))
        for n in choices:
            lst.insert(tk.END, n)
        lst.pack(padx=14, pady=4)
        lst.selection_set(0)

        def ok():
            sel = lst.curselection()
            if not sel:
                return
            name = choices[sel[0]]
            src = ex_dir / name
            dest = PROJECT_DIR / UPLOADS_REL / name
            if not dest.exists() or dest.stat().st_mtime < src.stat().st_mtime:
                shutil.copy2(src, dest)
            self.vhd_rel = UPLOADS_REL / name
            self.file_var.set(str(self.vhd_rel))
            dlg.destroy()

        row = tk.Frame(dlg, bg=PALETTE["card"])
        row.pack(pady=(8, 14))
        ttk.Button(row, text="OK", style="Accent.TButton",
                   command=ok).pack(side=tk.LEFT, padx=4)
        ttk.Button(row, text="Cancel", style="Ghost.TButton",
                   command=dlg.destroy).pack(side=tk.LEFT, padx=4)

    # ── Run handlers ─────────────────────────────────────────────────
    def _busy(self, running: bool):
        state = "disabled" if running else "normal"
        self.btn_single.configure(state=state)
        self.btn_bench.configure(state=state)

    def _require_vhd(self) -> Path | None:
        if self.vhd_rel is None:
            messagebox.showinfo("No input",
                                 "Upload a .vhd file or pick a bundled example first.")
            return None
        if not (PROJECT_DIR / SIM_BIN_REL).exists():
            messagebox.showerror("Simulator missing",
                                  f"Binary '{SIM_BIN_REL}' not present; "
                                  "build the project first.")
            return None
        return self.vhd_rel

    def _on_run_single(self):
        vhd = self._require_vhd()
        if vhd is None: return
        threads = int(self.threads_var.get())
        vcd_dir = self._current_vcd_dir()
        self._busy(True)
        self.status_var.set(f"Running (threads={threads})…")
        self.progress.configure(mode="indeterminate"); self.progress.start(12)

        def task():
            # Single-run always uses OpenMP (never -seq), even at threads=1.
            # The dedicated -seq baseline lives on the benchmark sweep.
            res = run_simulator(vhd, threads, tag="single",
                                vcd_dir=vcd_dir, seq=False)
            self.msg_queue.put(("single_done", res))

        self.worker = threading.Thread(target=task, daemon=True)
        self.worker.start()

    def _on_run_bench(self):
        vhd = self._require_vhd()
        if vhd is None: return
        try:
            sweep = sorted({int(x.strip()) for x in self.sweep_var.get().split(",")
                             if x.strip()})
            sweep = [n for n in sweep if n >= 1]
        except ValueError:
            messagebox.showerror("Bad input",
                                  "Thread list must be comma-separated integers.")
            return
        if not sweep:
            messagebox.showerror("Bad input", "Thread list is empty.")
            return

        repeats = int(self.repeats_var.get())
        # +1 for the dedicated -seq baseline run.
        total = 1 + len(sweep) * repeats
        vcd_dir = self._current_vcd_dir()

        self.bench_rows.clear()
        for i in self.tree.get_children():
            self.tree.delete(i)
        self.summary_var.set("")
        self._busy(True)
        self.progress.stop()
        self.progress.configure(mode="determinate", maximum=total, value=0)

        def task():
            done = 0
            # 1) Dedicated sequential baseline (truly single-threaded, no OpenMP).
            self.msg_queue.put(("bench_status", "Sequential baseline (-seq)…"))
            seq_res = run_simulator(vhd, 1, tag="seq",
                                    vcd_dir=vcd_dir, seq=True)
            done += 1
            self.msg_queue.put(("bench_progress", done))

            # 2) Parallel sweep. threads=1 here is an OpenMP run with 1 worker
            #    (no -seq) so the parallel overhead is visible in the data.
            best: dict[int, RunResult] = {}
            for n in sweep:
                for r in range(repeats):
                    self.msg_queue.put(
                        ("bench_status",
                         f"Parallel run: threads={n}  (repeat {r+1}/{repeats})"))
                    res = run_simulator(vhd, n, tag=f"bench_r{r}",
                                        vcd_dir=vcd_dir, seq=False)
                    # Keep the fastest repeat by simulation (Elapsed) time.
                    if res.ok and (n not in best or
                                   res.sim_ms < best[n].sim_ms):
                        best[n] = res
                    done += 1
                    self.msg_queue.put(("bench_progress", done))
            self.msg_queue.put(("bench_done", (seq_res, best)))

        self.worker = threading.Thread(target=task, daemon=True)
        self.worker.start()

    # ── UI updates from worker thread (via queue) ────────────────────
    def _poll_queue(self):
        try:
            while True:
                kind, payload = self.msg_queue.get_nowait()
                if   kind == "single_done":    self._apply_single(payload)
                elif kind == "bench_status":   self.status_var.set(payload)
                elif kind == "bench_progress": self.progress["value"] = payload
                elif kind == "bench_done":     self._apply_bench(payload)
        except queue.Empty:
            pass
        self.after(100, self._poll_queue)

    def _update_graph(self, stdout: str):
        start_marker = "========== DEPENDENCY GRAPH =========="
        end_marker   = "======================================"
        
        if start_marker not in stdout:
            self.graph_canvas.set_data([], 0)
            return

        try:
            start_idx = stdout.find(start_marker)
            end_idx = stdout.find(end_marker, start_idx + len(start_marker))
            raw_text = stdout[start_idx : end_idx].strip() if end_idx != -1 else stdout[start_idx:].strip()

            lines = raw_text.splitlines()
            processes = []
            current_layer = -1
            proc_re = re.compile(r"^\s*(\S+)\s*:\s*(.*?)\s*-->\s*(.*)$")
            
            for line in lines:
                if "Layer " in line:
                    current_layer += 1
                    continue
                m = proc_re.match(line)
                if m:
                    processes.append({
                        "name": m.group(1),
                        "inputs": [s.strip() for s in m.group(2).split(",") if s.strip()],
                        "outputs": [s.strip() for s in m.group(3).split(",") if s.strip()],
                        "layer": current_layer
                    })
            
            if len(processes) > 100:
                self.graph_canvas.set_data([], 0, "Graph is too big to represent here")
            else:
                self.graph_canvas.set_data(processes, current_layer + 1)
        except Exception:
            self.graph_canvas.set_data([], 0)

    def _apply_single(self, res: RunResult):
        self.progress.stop()
        self.progress.configure(mode="determinate", value=0)
        self._busy(False)

        self.out_text.delete("1.0", tk.END)
        self.out_text.insert("1.0", res.stdout or "")
        if res.stderr:
            self.out_text.insert(tk.END, "\n── stderr ──\n" + res.stderr)

        self._update_graph(res.stdout or "")

        if not res.ok:
            self.status_var.set(f"Run failed (exit={res.returncode}).")
            messagebox.showerror("Simulator error",
                                  f"Exit code {res.returncode}.\n\n"
                                  f"{res.stderr.strip()[:800] or '(no stderr)'}")
            return

        label = "seq" if res.is_seq else str(res.threads)
        self.m_threads.set(label)
        self.m_sim.set(f"{res.sim_ms:.4f}")
        self.m_wall.set(f"{res.wall_ms:.4f}")
        self.m_vcd.set(f"{res.vcd_path.stat().st_size / 1024:.1f}"
                        if res.vcd_path.exists() else "—")
        if res.vcd_path.exists():
            self._set_last_vcd(res.vcd_path)
        tag = "-seq" if res.is_seq else f"{res.threads} thread(s)"
        self.status_var.set(
            f"Done. Wall {res.wall_ms:.4f} ms  (sim {res.sim_ms:.4f} ms) "
            f"at {tag}."
        )

    def _apply_bench(self, payload):
        seq_res, best = payload
        self._busy(False)

        self.out_text.delete("1.0", tk.END)
        self.out_text.insert("1.0", seq_res.stdout or "")

        self._update_graph(seq_res.stdout or "")

        if not seq_res.ok:
            self.status_var.set(
                f"Sequential baseline failed (exit={seq_res.returncode}).")
            self.summary_var.set("Baseline run failed — cannot compute speedups.")
            return

        # ─────────────────────────────────────────────────────────────
        # 1. Compare VCDs for correctness (seq vs all parallel)
        # ─────────────────────────────────────────────────────────────
        import hashlib
        def get_hash(p: Path) -> str:
            if not p.exists(): return ""
            with open(p, "rb") as f:
                return hashlib.sha256(f.read()).hexdigest()

        seq_hash = get_hash(seq_res.vcd_path)
        all_match = True
        vcd_statuses = {} # n -> status_str

        for n, r in best.items():
            if not r.ok:
                vcd_statuses[n] = "FAILED"
                all_match = False
                continue
            
            p_hash = get_hash(r.vcd_path)
            if p_hash == seq_hash:
                vcd_statuses[n] = "MATCH"
            else:
                vcd_statuses[n] = "MISMATCH"
                all_match = False

        # ─────────────────────────────────────────────────────────────
        # 2. Update Table and Charts
        # ─────────────────────────────────────────────────────────────
        self.status_var.set(
            f"Benchmark complete — baseline {seq_res.wall_ms:.4f} ms, "
            f"{len(best)} parallel points.")

        # Seq baseline row
        self.tree.insert("", tk.END, values=(
            "seq",
            f"{seq_res.sim_ms:.4f}",
            f"{seq_res.wall_ms:.4f}",
            "1.00×",
            "—",
            "BASE",
        ), tags=("seq",))

        if not best:
            self.summary_var.set("No successful parallel runs.")
            self._set_last_vcd(seq_res.vcd_path) if seq_res.vcd_path.exists() else None
            return

        baseline_sim = seq_res.sim_ms
        rows = []
        for n in sorted(best):
            r = best[n]
            speedup = baseline_sim / r.sim_ms if r.sim_ms else 0.0
            eff = speedup / n if n else 0.0
            rows.append((n, r.sim_ms, r.wall_ms, speedup, eff))

        best_row = max(rows, key=lambda x: x[3])
        for row in rows:
            n, sim_ms, wall_ms, sp, eff = row
            tag = ("best",) if row is best_row else ()
            status = vcd_statuses.get(n, "—")
            self.tree.insert("", tk.END, values=(
                n, f"{sim_ms:.4f}", f"{wall_ms:.4f}",
                f"{sp:.2f}×", f"{eff:.2f}", status
            ), tags=tag)

        # Charts
        self.chart_time.set_series([
            ("Sim time (Elapsed)", [(n, s)  for n, s, *_ in rows]),
        ])
        self.chart_speedup.set_series([
            ("Measured", [(n, sp) for n, _, _, sp, _ in rows]),
            ("Ideal",    [(n, n)  for n, *_ in rows]),
        ])
        self.chart_eff.set_series([
            ("Efficiency", [(n, e) for n, _, _, _, e in rows]),
        ])

        match_text = " ✅ ALL MATCHES" if all_match else " ❌ OUTPUT MISMATCH"
        self.summary_var.set(
            f"Best speedup: {best_row[3]:.2f}× at {best_row[0]} threads "
            f"(efficiency {best_row[4]:.2f})   "
            f"·   baseline (-seq) Elapsed time: {baseline_sim:.4f} ms"
            f"   ·   {match_text}"
        )

        best_vcd = best[best_row[0]].vcd_path
        if best_vcd.exists():
            self._set_last_vcd(best_vcd)


if __name__ == "__main__":
    Dashboard().mainloop()
