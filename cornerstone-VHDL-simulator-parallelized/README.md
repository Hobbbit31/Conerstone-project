# Parallel VHDL Event-Driven Simulator

**Course:** Advanced Systems Programming
**Goal:** Redesign a cycle-accurate VHDL event-driven simulator to exploit multicore parallelism using OpenMP, while strictly preserving bit-for-bit identical output to the sequential baseline regardless of thread count.

---

## What It Does

This simulator takes a digital logic circuit (written in VHDL or as a pre-built netlist) and simulates how signals propagate through gates over time. It models real hardware behavior including delta cycles — the zero-time propagation steps that occur when a signal change triggers further changes within the same simulation timestep.

Key capabilities:
- **Two input modes:** accepts raw `.vhd` VHDL files (compiled on-the-fly) or pre-built `.net` netlist + `.stim` stimulus files
- **IEEE 1076-2008 compliant** delta-cycle semantics with double-buffering to ensure deterministic results
- **Parallel execution** using a dependency graph (Kahn's algorithm) to identify which gates can safely run in parallel at each delta step, then scheduling them with OpenMP
- **VCD output** in IEEE 1364 format — open in GTKWave to see waveforms for every signal

---

## Build

```bash
make
```

Requires: `g++` (C++17), `flex`, `bison`, and a compiler with OpenMP support (GCC recommended).

---

## Run

**Mode 1 — From a VHDL source file:**

The simulator compiles the VHDL on-the-fly into a netlist and runs it.
```bash
./simulator <file.vhd> [output.vcd] [flags]

# Examples:
./simulator test_vhdl/and_gate.vhd output.vcd
./simulator test_vhdl/full_adder.vhd output.vcd
./simulator test_vhdl/ripple_carry_adder_4bit.vhd output.vcd
```

**Mode 2 — From a pre-built netlist + stimulus:**

Directly load a `.net` netlist and `.stim` stimulus file without going through the VHDL compiler.
```bash
./simulator <file.net> <file.stim> [output.vcd] [flags]

# Examples:
./simulator test/net_files/and_gate.net test/tim_file/and_gate.stim output.vcd
./simulator test/net_files/dff_test.net test/tim_file/dff_test.stim output.vcd
./simulator test/net_files/ripple_carry_adder_4bit.net test/tim_file/ripple_carry_adder_4bit.stim output.vcd
```

**Debug flags:**

These can be combined to control what gets printed to stdout during simulation.

| Flag | Effect |
|------|--------|
| `-net` | Print the parsed netlist (signals + gates) |
| `-stim` | Print the scheduled stimulus events |
| `-dep` | Print dependency layers (which gates are in which parallel group) |
| `-sim` | Print simulation trace (time, delta, signal changes) |
| `-seq` | Force sequential execution — disables OpenMP for correctness comparison |
| `-all` | Enable all of the above |

**Run all tests:**
```bash
bash scripts/test.sh
```

**View waveform output:**
```bash
gtkwave output.vcd
```

---

## How It Works

### Simulation Engine — Delta-Cycle Model

The simulator uses an event-driven approach where each event is tagged with both a simulation time and a delta index. Within a single timestep, multiple delta rounds can occur as signal changes ripple through combinational logic.

The loop each step:
1. **Init** — all processes execute once at t=0 to propagate initial values
2. **Pop** — dequeue all events at the current `(time, delta)` from the priority queue
3. **Execute** — run all triggered gate processes; they read from `current_value` (double-buffering prevents race conditions)
4. **Commit** — atomically apply all pending writes (`next_value → current_value`)
5. **Propagate** — for each changed signal, schedule its sensitive processes at `(time, delta+1)`
6. **Repeat** until the queue is empty, or until the delta limit (10,000) is hit — which catches infinite combinational feedback loops

**Double-buffering** is what makes parallelism safe: since all processes in a batch read the old value and write to a separate buffer, the order of execution within a batch doesn't matter. Results are identical regardless of how many threads are used.

### Parallelism Strategy

Rather than parallelizing randomly (which would violate data dependencies), we first build a dependency graph of all gate processes:

- **Layer 0** — gates with no input dependencies (primary inputs, source signals)
- **Layer 1** — gates that only depend on Layer 0 outputs
- **Layer N** — gates that depend only on Layer N-1 outputs

Gates within the same layer are guaranteed to be independent of each other and can safely execute in parallel. OpenMP's `#pragma omp for` is used within each layer, with an implicit barrier between layers to maintain ordering.

```
Layer 0: [AND_1, NOT_2, BUF_3]   ← run in parallel
              ↓ barrier
Layer 1: [OR_4, XOR_5]           ← run in parallel
              ↓ barrier
Layer 2: [AND_6]                 ← single gate
```

Stimulus and clock processes are handled separately and always run sequentially.

### VHDL Frontend

When given a `.vhd` file, the simulator runs it through a Flex/Bison-based compiler:

```
.vhd → Flex lexer → Bison LALR(1) parser → C AST → pattern-matching codegen → .net + .stim
```

The codegen uses pattern matching on the AST to identify hardware constructs (DFF, MUX, SR latch, combinational logic) and emit the corresponding gate definitions. Complex expressions are automatically flattened into temporary signals.

---

## Project Structure

```
include/
  ├── Event.hpp              — Event struct: (time, delta, process*) + priority comparator
  ├── Process.hpp            — Abstract base class with virtual execute()
  ├── Signal.hpp             — Double-buffered signal with sensitivity list
  ├── Simulator.hpp          — Simulation loop, initialization, VCD attachment
  ├── Stimulusprocess.hpp    — Drives a signal to a value at a scheduled time
  ├── DependencyGraph.hpp    — Kahn's algorithm: partitions gates into parallel layers
  ├── DebugFlags.hpp         — Global debug flag toggles
  └── io_handlers/
      ├── NetlistParser.hpp  — Parses .net files, builds circuit (signals + gates)
      ├── StimParser.hpp     — Parses .stim files, schedules stimulus events
      └── VCDWriter.hpp      — Writes IEEE 1364 VCD waveform files

include/vhdl/
  ├── vhdl_lexer.l           — Flex lexer (case-insensitive VHDL)
  ├── vhdl_parser.y          — Bison LALR(1) parser
  ├── vhdl_ast.h             — C AST node structs
  ├── VHDLAST.hpp            — C++ wrapper for AST access
  └── VHDLCodeGen.hpp        — Pattern-matching codegen: VHDL → gate netlist

processes/                   — 12 gate types: AND, OR, NOT, XOR, NAND, NOR, XNOR,
                               BUF, MUX (2:1), DFF (rising-edge), SR Latch, Clock

src/
  ├── Simulator.cpp          — Event loop with init phase + delta cycle limit
  ├── Signal.cpp             — Double-buffer, commit, sensitivity list
  └── vhdl_ast.c             — AST constructor/destructor functions (C)

test/
  ├── net_files/             — Pre-built netlists: and_gate, full_adder, delta_chain,
  │                            dff_test, ripple_carry_adder_4bit, semantic_violation
  └── tim_file/              — Corresponding stimulus files

test_vhdl/                   — VHDL test circuits: and_gate, full_adder, multiplier_2bit,
                               comparator_4bit, encoder, ripple_carry_adder_4bit,
                               bad_library (error test), bad_variable (error test)

scripts/test.sh              — Automated test suite (36 assertions across 4 circuits)
generated/                   — Auto-generated .net/.stim from VHDL compilation
main.cpp                     — Entry point: dispatches VHDL or netlist mode
Makefile                     — g++ -std=c++17 -O2 -fopenmp, flex, bison
```

---

## Supported VHDL Subset

The VHDL compiler supports a testbench-style subset sufficient for describing combinational and sequential logic:

| Feature | Details |
|---------|---------|
| Entity/architecture | Testbench style (no external ports) |
| Signal declarations | `std_logic` with optional `:= '0'` / `:= '1'` init |
| Concurrent assignments | `Y <= A and B;`, `Z <= not X;`, expressions |
| Process blocks | Combinational, DFF (`rising_edge`), MUX (`if/else`), SR Latch |
| Stimulus | `process begin ... wait for N ns; end process;` |
| Operators | `and`, `or`, `not`, `xor`, `nand`, `nor`, `xnor` |

**Not supported:** `library`, `use`, `port`, `variable`, `component`, `std_logic_vector`, arithmetic operators, `generate`, loops.

Complex expressions are automatically flattened. For example:
```vhdl
Cout <= (A and B) or (Cin and (A xor B));
```
Gets compiled to:
```
signal _t0 0
signal _t1 0
xor _t0 A B
and _t1 Cin _t0
and _t2 A B
or Cout _t2 _t1
```

---

## Tests

The test suite in `scripts/test.sh` runs 36 assertions across 4 circuits, verifying correct signal values at specific simulation times.

| Circuit | Focus |
|---------|-------|
| AND gate | Basic gate behavior, input sensitivity |
| Delta chain | 3-level delta propagation within a single timestep |
| D Flip-Flop | Rising-edge capture, latch stability |
| Ripple carry adder | Carry propagation across 6 delta levels, overflow |

The 8 VHDL test circuits in `test_vhdl/` verify the compiler — including two intentional error cases (`bad_library.vhd`, `bad_variable.vhd`) that confirm unsupported constructs are rejected cleanly.

Correctness is validated by comparing sequential (`-seq`) vs parallel output — they must be identical.

---

## Status

| Component | Status |
|-----------|--------|
| Sequential baseline | Done |
| VHDL frontend (Flex/Bison) | Done |
| Dependency graph (Kahn's) | Done |
| OpenMP parallelism | Done |
| Test suite (36/36 passing) | Done |
| Performance benchmarks | Done |
| Final design document | Done |


## observations
- OMP_WAIT_POLICY=active — threads spin instead of sleeping, so they're ready instantly when the next process starts a parallel region
- OMP_NUM_THREADS=8 — fixes the thread count so no respawning happens when count changes between run


- i noticeed that there was one issue each time thread spanwn then and then deleted when that particular block of code is over.
- above 2 varable helped in export by setting this threads are not going to back to sleep instead staying back to take next work in next interation.

- these are the commands
export OMP_WAIT_POLICY=active
export OMP_NUM_THREADS=8

unset OMP_WAIT_POLICY                       
unset OMP_NUM_THREADS

echo $OMP_WAIT_POLICY                       
echo $OMP_NUM_THREADS 


