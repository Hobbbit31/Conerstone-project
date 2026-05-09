# VHDL Simulator — Dashboard UI

A small Tkinter desktop dashboard that drives the parallel VHDL
simulator built by the Makefile in the parent directory. Upload a
`.vhd` file, pick how many OpenMP threads to use, and inspect scaling
metrics (simulation time, speedup, parallel efficiency) in one place.

**Zero Python dependencies.** The app uses only the standard library
(`tkinter`, `subprocess`, `threading`), so there is no `pip`, no
virtualenv, and no `requirements.txt` to manage.

## Layout

```
cornerstone-VHDL-simulator-parallelized/
├── Makefile
├── main.cpp, src/, include/, …
└── ui/
    ├── run_dashboard.sh   # builds the simulator, then launches the dashboard
    ├── dashboard.py       # Tkinter app
    └── README.md
```

At runtime the dashboard creates, by default, two helper directories
next to the Makefile:

- `../ui_uploads/` — uploaded/selected `.vhd` inputs
- `../ui_output/`  — generated `.vcd` waveforms (user-overridable via
  the *Browse…* button in the sidebar)

Both are removed by `make cleanall`.

## Quick start

From the project root, in bash (Linux / WSL / macOS / Git Bash):

```bash
cd cornerstone-VHDL-simulator-parallelized/ui
./run_dashboard.sh
```

If you cloned the repo on Windows and are running in WSL, line endings
may have been converted to CRLF, which bash can't parse. Strip them
once and you're set:

```bash
sed -i 's/\r$//' ui/run_dashboard.sh
```

(You can do the same to `ui/dashboard.py` if Python complains, though
Python is generally tolerant.)

### Flags

| Flag         | Effect                             |
| ------------ | ---------------------------------- |
| `--clean`    | `make clean` before building       |
| `--no-build` | skip compile, launch the UI only   |

## What the dashboard does

1. **Build step.** The script runs `make` in the parent directory to
   produce `simulator` (Linux/WSL/macOS) or `simulator.exe` (MSYS/MinGW).
   It auto-detects the right binary for the platform so a stale
   cross-compiled `.exe` sitting next to a fresh Linux build won't fool
   it.
2. **Python check.** Verifies `python3` and `tkinter` are importable.
   Tkinter is bundled with upstream Python; on Debian/Ubuntu/WSL
   install it with `sudo apt install python3-tk`.
3. **Launch.** Exports `OMP_WAIT_POLICY=active` (keeps OpenMP threads
   spinning between parallel regions) and `VHDL_SIM_BIN_REL` (the
   relative binary path, so `dashboard.py` stays location-independent),
   then execs the Tkinter app.

## Using the UI

| Control | What it does |
| ------- | ------------ |
| **Upload .vhd…** | Pick any VHDL file; it is copied into `ui_uploads/` so every run uses the same input path. |
| **Example…** | Pick one of the bundled designs in `test_vhdl/`. |
| **OpenMP threads (single run)** | `OMP_NUM_THREADS` for the single-run button. |
| **VCD output directory** | Where generated `.vcd` files land. Defaults to `../ui_output/`; use *Browse…* to pick anywhere else, or *Reset* to restore the default. |
| **Thread counts (comma-sep)** | The sweep for the benchmark button. Defaults to powers of two up to the host CPU count. |
| **Repeats per thread count** | Runs each thread count *N* times and keeps the fastest — tames noise on tiny designs. |
| **Run single** | One run at the chosen thread count. Fills the top metrics row. |
| **Run benchmark sweep** | Runs the full sweep, populates the benchmark table and the three charts. |
| **Open in GTKWave** | Opens the latest generated `.vcd` in GTKWave (must be on your `PATH`). After a sweep, the best-speedup run's VCD is used. |

## How a run works under the hood

For every thread count *N* the dashboard spawns the simulator with

```
OMP_NUM_THREADS=<N>  OMP_WAIT_POLICY=active  ./simulator  <vhd>  <vcd>  [-seq]
```

from the project directory. The `-seq` flag is added automatically when
*N* == 1 so the sequential baseline is a true single-threaded run (no
OpenMP overhead), which makes `speedup = T₁ / Tₙ` meaningful.

The subprocess runs on a worker thread so the UI stays responsive; the
simulator's self-reported `Simulation time: … s` line is parsed from
stdout and wall time is captured as a sanity check. Speedup and
efficiency (`speedup / N`) are derived from the collected table and
plotted on the Charts tab.

## Requirements

- `make`, `g++`, `flex`, `bison` — to build the simulator
- Python 3.9+ with the `tkinter` module
  - Debian/Ubuntu/WSL: `sudo apt install python3-tk`
  - Fedora/RHEL     : `sudo dnf install python3-tkinter`
  - macOS (Homebrew): `brew install python-tk`
  - Windows         : bundled with the python.org installer
- `gtkwave` on `PATH`, if you want the *Open in GTKWave* button
- On WSL: WSLg (built into WSL2 on Windows 11) for the Tk window
