# Lexer — Stage 1 of the VHDL Transpiler

## What the Lexer Does

The lexer is the **first stage** of a compiler. It takes raw `.vhd` text and breaks it into **tokens** — the smallest meaningful units.

```
Raw text:    "OUT1 <= A and B;"

Tokens:      [IDENT "OUT1"] [<= ] [IDENT "A"] [KW_AND] [IDENT "B"] [;]
```

The parser (Stage 2) will consume these tokens. Without a lexer, the parser would have to deal with whitespace, comments, case-insensitivity, and multi-character operators all at once.

---

## How `vhdl_lexer.l` is Structured

A flex file has **3 sections** separated by `%%`:

```
%{ ... %}        <--  C code copied verbatim (includes, globals)
%%               <--  separator
RULES            <--  pattern -> action pairs
%%               <--  end
```

---

## Section 1: Declarations

```c
%{
#include "vhdl_tokens.h"
YYSTYPE yylval;          // semantic value passed to parser
static int yycolumn = 1; // column tracker
%}

%option noyywrap          // single file, no chaining
%option noinput nounput   // suppress unused function warnings
%option yylineno          // flex auto-tracks line numbers
%option case-insensitive  // VHDL is case-insensitive
```

### What is `YYSTYPE yylval`?

It is a **union** — it can hold an `int` (for integers), a `char` (for `'0'`/`'1'`), or a `char*` (for identifiers). The parser reads this to get the token's value.

Defined in `vhdl_tokens.h`:

```c
typedef union {
    int   ival;   // LIT_INTEGER value
    char  cval;   // LIT_CHAR value: '0' or '1'
    char *sval;   // IDENT / keyword text (strdup'd, caller frees)
} YYSTYPE;
```

### What do the `%option` lines do?

| Option | Purpose |
|--------|---------|
| `noyywrap` | We only lex one file, no chaining to another file when EOF is reached |
| `noinput nounput` | Suppresses compiler warnings for two unused functions flex generates |
| `yylineno` | Flex automatically tracks the current line number in the variable `yylineno` |
| `case-insensitive` | VHDL is case-insensitive, so `"entity"` matches `ENTITY`, `Entity`, `eNtItY`, etc. |

---

## Section 2: Rules

Each rule is: **regex pattern** on the left, **C action** on the right.

Flex tries patterns **top to bottom**, and the **longest match wins**. If two patterns match the same length, the **first one listed** wins.

### Whitespace and Comments — discard silently

```
[ \t\r]+    ;                      // spaces/tabs -> do nothing
\n          { yycolumn = 1; }      // newline -> reset column
"--".*      ;                      // VHDL comment -> skip to end of line
```

- `[ \t\r]+` matches one or more spaces, tabs, or carriage returns. The action `;` means "do nothing" — just consume and move on.
- `\n` resets the column counter. Line number is tracked automatically by `yylineno`.
- `"--".*` matches `--` followed by anything until end of line. This is how VHDL comments work.

### Keywords — return specific token types

```
"entity"    { yylval.sval = strdup(yytext); return KW_ENTITY; }
"signal"    { yylval.sval = strdup(yytext); return KW_SIGNAL; }
"and"       { yylval.sval = strdup(yytext); return KW_AND; }
...
```

**How this works:**
- `yytext` is a flex built-in — it points to the matched string.
- `strdup(yytext)` copies the string because flex reuses its internal buffer on the next call.
- `return KW_ENTITY` sends token type `256` (defined in `vhdl_tokens.h`) back to whoever called `yylex()`.
- Because of `%option case-insensitive`, the pattern `"entity"` matches `ENTITY`, `Entity`, etc.

### Rejected Keywords — catch unsupported VHDL

```
"variable"  { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"library"   { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"port"      { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
...
```

These are valid VHDL keywords but not in our subset. We tag them as `REJECTED_KEYWORD` so the parser can give a helpful error like:
```
Line 5: 'variable' not supported -- use signals
```

We don't error in the lexer itself — we just tag and let the parser decide what message to show.

### Multi-character Operators — must come before single-char rules

```
"<="        { return OP_SIGNAL_ASSIGN; }   // signal assignment
":="        { return OP_VAR_ASSIGN; }      // initialization
```

Flex's **longest match** rule handles this correctly: when the input is `<=`, flex matches `<=` (2 chars) instead of `<` (1 char), because the longer match always wins.

We don't even have a rule for lone `<` since our VHDL subset doesn't use it.

### Character Literals — only `'0'` and `'1'`

```
"'0'"       { yylval.cval = '0'; return LIT_CHAR; }
"'1'"       { yylval.cval = '1'; return LIT_CHAR; }
"'"[^'']"'" { fprintf(stderr, "error: only '0' and '1' supported..."); exit(1); }
```

- First two rules match the exact strings `'0'` and `'1'`, storing the character in `yylval.cval`.
- Third rule catches anything else between single quotes (like `'X'`, `'Z'`) and exits with an error.
- We only support `std_logic` values `0` and `1` — no `X`, `Z`, `U`, `-`, etc.

### Integer Literals

```
[0-9]+      { yylval.ival = atoi(yytext); return LIT_INTEGER; }
```

- `[0-9]+` matches one or more digits.
- `atoi(yytext)` converts the matched string `"10"` to the integer `10`.
- Stored in `yylval.ival`.
- Used for `wait for 10 ns` — the `10` becomes a `LIT_INTEGER` token.

### Identifiers — anything that isn't a keyword

```
[a-zA-Z_][a-zA-Z0-9_]*  { yylval.sval = strdup(yytext); return IDENT; }
```

- Matches signal names like `OUT1`, `t0`, `Cin`, `and_gate_tb`.
- Must start with a letter or underscore, followed by letters, digits, or underscores.
- This rule comes **after** all keyword rules — so when the input is `and`, flex matches `KW_AND` first (same length, first rule wins), not `IDENT`.

**Rule priority example:**
```
Input: "and"
  - "and" rule matches 3 chars -> KW_AND
  - [a-zA-Z_][a-zA-Z0-9_]* also matches 3 chars -> IDENT
  - Same length, so first rule wins -> KW_AND returned
```

### Single-character Punctuation

```
":"   { return ':'; }
";"   { return ';'; }
"("   { return '('; }
")"   { return ')'; }
","   { return ','; }
"="   { return '='; }
```

These return their **ASCII value** directly (`:` = 58, `;` = 59, etc.). This is a standard flex/bison convention — single-char tokens don't need named constants.

### Catch-all Error

```
.     { fprintf(stderr, "error: unexpected character '%s'\n", yytext); exit(1); }
```

- `.` in regex matches **any single character** except newline.
- This is the **last rule**, so it only triggers if nothing above matched.
- Catches illegal characters like `@`, `#`, `$`, `!` in the VHDL source.
- Exits immediately with an error message including line and column.

---

## How It All Connects

```
.vhd file -> flex calls yylex() repeatedly -> each call returns one token
                                               |-- token type (int): KW_AND, IDENT, ';', etc.
                                               |-- token value (yylval): string/int/char
```

The parser (Stage 2) will call `yylex()` in a loop, consuming tokens one by one to build the AST (Abstract Syntax Tree).

---

## Token Types Summary

All defined in `vhdl_tokens.h` (starting from 256 to avoid clashing with ASCII values):

| Token | Value | Example Input |
|-------|-------|---------------|
| `KW_ENTITY` | 256 | `entity` |
| `KW_IS` | 257 | `is` |
| `KW_END` | 258 | `end` |
| `KW_ARCHITECTURE` | 259 | `architecture` |
| `KW_SIGNAL` | 262 | `signal` |
| `KW_AND` | 269 | `and` |
| `KW_OR` | 270 | `or` |
| `KW_NOT` | 271 | `not` |
| `OP_SIGNAL_ASSIGN` | 281 | `<=` |
| `OP_VAR_ASSIGN` | 282 | `:=` |
| `LIT_CHAR` | 283 | `'0'`, `'1'` |
| `LIT_INTEGER` | 284 | `10`, `100` |
| `IDENT` | 285 | `OUT1`, `clk` |
| `REJECTED_KEYWORD` | 286 | `variable`, `library` |
| `':'` | 58 | `:` |
| `';'` | 59 | `;` |
| `'('` | 40 | `(` |
| `')'` | 41 | `)` |
| `','` | 44 | `,` |
| `'='` | 61 | `=` |

---

## Build and Test

```bash
# Generate C code from flex file
flex -o vhdl_lexer.c include/vhdl/vhdl_lexer.l

# Compile with a test driver
gcc -o test_flex_lexer test_flex_lexer.c vhdl_lexer.c -Iinclude/vhdl

# Run on a VHDL file
./test_flex_lexer test_vhdl/and_gate.vhd
```

### Example Output

For input `test_vhdl/and_gate.vhd`:
```
  line   1  KW_ENTITY             "entity"
  line   1  IDENT                 "and_gate_tb"
  line   1  KW_IS                 "is"
  line   5  KW_SIGNAL             "signal"
  line   5  IDENT                 "A"
  line   5  ','
  line   5  IDENT                 "B"
  line   7  IDENT                 "OUT1"
  line   7  OP_SIGNAL_ASSIGN
  line   7  IDENT                 "A"
  line   7  KW_AND                "and"
  line   7  IDENT                 "B"
  line   7  ';'
  ...
```
