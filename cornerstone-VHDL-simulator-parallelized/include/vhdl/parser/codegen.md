# Code Generator — Stage 3 of the VHDL Transpiler

## What the Code Generator Does

Takes the AST (from bison parser) and produces two plain text files:
- `.net` file — signal declarations + gate lines
- `.stim` file — stimulus events with timestamps

These files are in the exact format that `NetlistParser` and `StimParser` already read.
Nothing in the simulator backend changes.

```
.vhd file → [Lexer] → [Parser] → [AST] → [CodeGen] → .net + .stim → [Existing Simulator] → .vcd
```

---

## Where Generated Files Go

When you run `./simulator something.vhd`, it creates:
```
generated/something.net
generated/something.stim
```

These files are **kept** after simulation so you can inspect them.
The `generated/` folder is inside the project root.

---

## File: `include/vhdl/VHDLCodeGen.hpp`

Single header file. No .cpp file needed. Uses plain standalone functions — no classes, no templates, no complex OOP. Written to be as simple as possible.

### Global Variables Used During Generation

```cpp
g_signals    — string where signal lines are appended
g_gates      — string where gate lines are appended
g_stim       — string where stimulus lines are appended
g_temp       — counter for temp signal names: _t0, _t1, _t2 ...
g_has_const0 — whether we already created a _const0 signal
g_has_const1 — whether we already created a _const1 signal
```

All get reset at the start of each `generate()` call.

### 4 Parts

#### Part 1: `codegen_signals()`
Walks the `VSignalDeclList` linked list. For each signal declaration, writes one line per signal name.

```
Input AST:  signal A, B, OUT1 : std_logic := '0';
Output:     signal A 0
            signal B 0
            signal OUT1 0
```

#### Part 2: `codegen_concurrent()`
Walks `VConcAssignList`. For each concurrent assignment, calls `flatten_expr()` to break the expression tree into gate lines.

Simple case:
```
Input AST:  t0 <= A xor B;
Output:     xor t0 A B
```

Compound case (creates temp signals):
```
Input AST:  Cout <= (A and B) or (Cin and t0);
Output:     signal _t0 0
            signal _t1 0
            and _t0 A B
            and _t1 Cin t0
            or Cout _t0 _t1
```

#### Part 3: `codegen_processes()`
Walks `VGateProcList`. Pattern-matches each process to identify what hardware it represents:

| Pattern | How it's detected | .net output |
|---|---|---|
| DFF | 1 branch, condition is `rising_edge(X)` or `falling_edge(X)` | `dff Q Q_NOT CLK D` |
| MUX | 2 branches (if + else), condition is `X='1'` or `X='0'` | `mux Y A B SEL` |
| SR Latch | 2 branches (if + elsif), both conditions are `X='1'` | `sr Q Q_NOT S R` |
| Combinational | no branches, just direct assigns | uses flatten_expr |

If Q_NOT is not written in the VHDL, a dummy signal `_q_not_N` is auto-created.

If a process doesn't match any pattern, it throws an error with the line number.

#### Part 4: `codegen_stimulus()`
Walks `VStimStepList`. For each step, writes `@time signal=value` lines.

```
Input AST:  A <= '0'; B <= '0'; wait for 10 ns; A <= '1'; wait for 10 ns;
Output:     @0 A=0
            @0 B=0
            @10 A=1
```

---

## Key Functions: `flatten_expr()` and `flatten_child()`

This is the only "tricky" part of the whole file.

`flatten_expr(expr, target)` — takes an expression tree node and a target signal name. Writes gate lines into `g_gates`. Returns the signal name holding the result.

`flatten_child(child)` — handles one child of an expression:
- **IDENT** (signal name like `A`) → just returns `"A"`, nothing emitted
- **LITERAL** (`'0'` or `'1'`) → creates `_const0` or `_const1` signal if first time, returns the name
- **Anything else** (compound like `A and B`) → creates temp signal `_t0`, calls `flatten_expr` on it, returns `"_t0"`

### Walkthrough Example

```vhdl
Cout <= (A and B) or (Cin and t0);
```

Expression tree:
```
      OR           target = Cout
     /  \
   AND   AND
  / \   / \
 A   B Cin t0
```

Step by step:
1. `flatten_expr(OR, "Cout")` → needs to flatten left and right children
2. `flatten_child(AND(A,B))` → compound, creates `_t0`, emits `and _t0 A B`, returns `"_t0"`
3. `flatten_child(AND(Cin,t0))` → compound, creates `_t1`, emits `and _t1 Cin t0`, returns `"_t1"`
4. Emits `or Cout _t0 _t1`

Final output:
```
signal _t0 0
signal _t1 0
and _t0 A B
and _t1 Cin t0
or Cout _t0 _t1
```

---

## Integration in `main.cpp`

```cpp
if (argv[1] ends with ".vhd") {
    // 1. open file, set yyin, call yyparse() → vhdl_root (AST)
    // 2. VHDLCodeGen::generate(vhdl_root) → net_content + stim_content
    // 3. write to generated/<name>.net and generated/<name>.stim
    // 4. feed those files to existing NetlistParser::load() + StimParser::load()
    // 5. simulate as usual
    // 6. files are kept in generated/ for inspection
} else {
    // existing .net + .stim flow — completely unchanged
}
```

Usage:
```bash
./simulator circuit.vhd [output.vcd]               # new VHDL flow
./simulator circuit.net circuit.stim [output.vcd]   # old flow (unchanged)
```

Example:
```bash
./simulator test_vhdl/full_adder.vhd output.vcd
# creates: generated/full_adder.net
#          generated/full_adder.stim
#          output.vcd
```

---

## Makefile Changes

- Added `-Iinclude/vhdl -Ibuild/vhdl` to `CXXFLAGS` so main.cpp can find the parser headers
- Main `$(TARGET)` now depends on and links `$(VHDL_OBJ)` (parser.tab.o, lexer.o, vhdl_ast.o)
- `VHDLCodeGen.hpp` is header-only, no extra .o file needed

---

## Files Changed

| File | Change |
|---|---|
| `include/vhdl/VHDLCodeGen.hpp` | **NEW** — code generator (header-only, ~200 lines) |
| `main.cpp` | **EDITED** — added `.vhd` detection, VHDL parse+codegen flow, writes to `generated/` |
| `Makefile` | **EDITED** — added include paths, linked VHDL parser objects into simulator binary |
| `generated/` | **NEW** — folder where generated .net and .stim files are saved |

## Files NOT Changed

- `Simulator.cpp`, `Signal.hpp`, `Signal.cpp` — untouched
- `NetlistParser.hpp`, `StimParser.hpp`, `VCDWriter.hpp` — untouched
- All process files (`AndProcess.hpp`, `OrProcess.hpp`, etc.) — untouched
- `vhdl_parser.y`, `vhdl_lexer.l`, `vhdl_ast.c`, `vhdl_ast.h` — untouched
- `VHDLAST.hpp` — untouched (C++ AST, not used by codegen — codegen uses the C AST)

---

## Tested With

| Test | Result |
|---|---|
| `test_vhdl/and_gate.vhd` | Parses, generates correct .net/.stim, simulates correctly |
| `test_vhdl/full_adder.vhd` | Parses, generates correct .net/.stim, delta cycles propagate correctly |
| `test_vhdl/bad_variable.vhd` | Correctly rejected: `'variable' not supported — use signals` |
| `test_vhdl/bad_library.vhd` | Correctly rejected: `'library' not supported — no imports needed` |
| Old flow (`.net` + `.stim`) | Still works exactly as before, no regressions |
