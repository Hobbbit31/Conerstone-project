#!/usr/bin/env python3
"""
gen_pyramid.py — Generate a pyramid AND-tree VHDL test circuit.

Structure:
  Layer 0 : 10000 AND gates, each fed by 2 primary inputs  (20000 inputs total)
  Layer 1 :  5000 AND gates, each fed by 2 layer-0 outputs
  Layer 2 :  2500 AND gates, each fed by 2 layer-1 outputs
  ...halving each layer until 1 gate remains (final output: OUT_FINAL)

Purpose: stress-test the parallel simulator.
  - Every gate in a layer is independent → ideal for omp parallelism.
  - Deep layer chain stresses inter-layer synchronisation (barriers).
  - Large signal count stresses the commit phase.
"""

import math, os, sys

# ── config ─────────────────────────────────────────────────────────────────
FIRST_LAYER_GATES = 30000       # 50000+25000+...+1 ≈ 100000 total gates
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "test_vhdl")
OUT_FILE = os.path.join(OUT_DIR, "pyramid_100k.vhd")

# ── build layer sizes ───────────────────────────────────────────────────────
layers = []
n = FIRST_LAYER_GATES
while n >= 1:
    layers.append(n)
    if n == 1:
        break
    n = max(1, n // 2)

total_gates   = sum(layers)
total_inputs  = layers[0] * 2          # each layer-0 gate needs 2 primary inputs
total_signals = total_inputs + total_gates  # inputs + one output per gate

print(f"Layers      : {len(layers)}")
print(f"Layer sizes : {layers}")
print(f"Total gates : {total_gates}")
print(f"Primary ins : {total_inputs}")
print(f"Signals     : {total_signals}")

# ── generate VHDL ───────────────────────────────────────────────────────────
lines = []

# ── entity ──────────────────────────────────────────────────────────────────
lines.append("-- Auto-generated pyramid AND-tree")
lines.append(f"-- {len(layers)} layers: {' -> '.join(str(x) for x in layers)}")
lines.append(f"-- {total_gates} gates, {total_inputs} primary inputs")
lines.append("")
lines.append("entity pyramid_and_tree is")
lines.append("end entity pyramid_and_tree;")
lines.append("")
lines.append("architecture rtl of pyramid_and_tree is")
lines.append("")

# ── signal declarations ──────────────────────────────────────────────────────
# primary inputs: IN_0_0, IN_0_1, IN_1_0, IN_1_1, ... IN_{G-1}_0, IN_{G-1}_1
lines.append("  -- primary inputs (2 per layer-0 gate)")
for g in range(layers[0]):
    lines.append(f"  signal IN_{g}_A : std_logic := '1';")
    lines.append(f"  signal IN_{g}_B : std_logic := '1';")

lines.append("")
lines.append("  -- gate outputs: G_L{layer}_{index}")
for li, count in enumerate(layers):
    lines.append(f"  -- layer {li} ({count} gates)")
    for g in range(count):
        lines.append(f"  signal G_L{li}_{g} : std_logic := '0';")

lines.append("")
lines.append("begin")
lines.append("")

# ── concurrent assignments ───────────────────────────────────────────────────
# layer 0: each gate reads two primary inputs
lines.append("  -- layer 0: primary inputs -> AND gates")
for g in range(layers[0]):
    lines.append(f"  G_L0_{g} <= IN_{g}_A and IN_{g}_B;")

lines.append("")

# layers 1..N: each gate reads two outputs from previous layer
for li in range(1, len(layers)):
    prev_count = layers[li - 1]
    cur_count  = layers[li]
    lines.append(f"  -- layer {li}: {cur_count} gates fed by layer {li-1} outputs")
    for g in range(cur_count):
        a = g * 2
        b = g * 2 + 1
        # if previous layer has odd count, last gate reuses the last output
        if b >= prev_count:
            b = prev_count - 1
        lines.append(f"  G_L{li}_{g} <= G_L{li-1}_{a} and G_L{li-1}_{b};")
    lines.append("")

last_layer = len(layers) - 1
lines.append(f"  -- G_L{last_layer}_0 is the single final output of the pyramid")
lines.append("")

# ── stimulus ─────────────────────────────────────────────────────────────────
# Signals initialise to '1'. The process immediately overrides all A-inputs to
# '0' at t=0, then flips them back to '1' at t=10ns, then to '0' at t=20ns.
# Grammar requires at least one assignment before the first wait for.
# Grammar rule: each step = assign_list + "wait for N ns;"
# Process ends with bare "wait;" (halt stimulus forever).
lines.append("  -- stimulus: set A-inputs to '0' at t=0, flip to '1' at t=10ns, then halt")
lines.append("  process begin")
for g in range(layers[0]):
    lines.append(f"    IN_{g}_A <= '0';")
lines.append("    wait for 10 ns;")
for g in range(layers[0]):
    lines.append(f"    IN_{g}_A <= '1';")
lines.append("    wait for 10 ns;")
lines.append("    wait;")          # bare wait = halt stimulus forever
lines.append("  end process;")
lines.append("")
lines.append("end architecture rtl;")

# ── write file ───────────────────────────────────────────────────────────────
os.makedirs(OUT_DIR, exist_ok=True)
with open(OUT_FILE, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"\nWritten to: {OUT_FILE}")
print(f"File size : {os.path.getsize(OUT_FILE):,} bytes")
