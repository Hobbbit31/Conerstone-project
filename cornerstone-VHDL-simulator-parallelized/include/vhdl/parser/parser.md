# Parser — Stage 2 of the VHDL Transpiler

## What the Parser Does

Takes the flat token stream from the lexer and builds a **structured tree** (AST).

```
Tokens:   [KW_ENTITY] [IDENT "and_gate_tb"] [KW_IS] [KW_END] [;] ...

AST:      VHDLDesign {
            entity_name: "and_gate_tb"
            signals: [ {names: ["A","B","OUT1"], init: '0'} ]
            concurrent_assigns: [ {target: "OUT1", expr: Binary(and, A, B)} ]
            stimulus: { steps: [{time:0, ...}, {time:10, ...}] }
          }
```

---

## How `vhdl_parser.y` is Structured

Same as any Bison file — **3 sections** separated by `%%`:

```
%{ ... %}        <--  C prologue (includes, globals)
%union / %token  <--  Types and token declarations
%%               <--  Grammar rules with semantic actions
%%               <--  yyerror() function
```

---

## Section 1: Prologue

```c
%{
#include "vhdl_ast.h"

extern int yylex(void);
extern int yylineno;
void yyerror(const char *s);

VHDLDesign *vhdl_root = NULL;   // parse result
static int stim_time = 0;       // cumulative time for stimulus
%}
```

- `vhdl_root` — output of the parser. After `yyparse()` succeeds, this points to the complete AST.
- `stim_time` — running counter. VHDL uses relative delays (`wait for 10 ns`), but our AST stores absolute times. So we accumulate: `0 → 10 → 20 → ...`

---

## Section 2: Union and Declarations

```c
%union {
    int   ival;
    char  cval;
    char *sval;
    VExpr             *expr;
    VIdentList        *ident_list;
    VSignalDecl       *signal_decl;
    VSignalDeclList   *signal_decl_list;
    VAssignList       *assign_list;
    VIfBranchList     *if_branch_list;
    VGateProcess      *gate_proc;
    VStimStepList     *stim_step_list;
    VArchBody         *arch_body;
    VHDLDesign        *design;
}
```

Every grammar symbol carries a **value** on Bison's stack. The `%union` defines all possible types. `$$`, `$1`, `$2` etc. in rules refer to these.

```c
%token <cval> LIT_CHAR       // LIT_CHAR carries a char
%token <sval> IDENT          // IDENT carries a char*
%type <expr>  expr expr_or   // expr carries a VExpr*
%type <design> design        // design carries a VHDLDesign*
```

---

## Section 3: Grammar Rules

### Top-Level

```yacc
design
    : entity_decl KW_ARCHITECTURE IDENT KW_OF IDENT KW_IS
      signal_decl_list KW_BEGIN_KW arch_body end_tag
        { $$ = vhdl_design_new($5, $3, $7, $9); vhdl_root = $$; }
    | REJECTED_KEYWORD
        { fprintf(stderr, "Line %d: '%s' not supported\n", yylineno, $1); YYERROR; }
    ;
```

Entity + architecture parsed in one rule. `$5` = entity name, `$3` = arch name, `$7` = signals, `$9` = body.

### end_tag — Shared Closing Rule

```yacc
end_tag
    : KW_END ';'
    | KW_END IDENT ';'                     { free($2); }
    | KW_END KW_ENTITY ';'
    | KW_END KW_ENTITY IDENT ';'           { free($3); }
    | KW_END KW_ARCHITECTURE ';'
    | KW_END KW_ARCHITECTURE IDENT ';'     { free($3); }
    | KW_END KW_PROCESS ';'
    ;
```

VHDL allows `end;`, `end entity;`, `end entity foo;`, etc. One shared rule handles all closing variants instead of duplicating them.

### Signal Declarations

```yacc
signal_decl_list
    : /* empty */                    { $$ = NULL; }
    | signal_decl_list signal_decl   { $$ = vsignal_decl_list_append($1, $2); }
    | signal_decl_list REJECTED_KEYWORD
        { fprintf(stderr, "Line %d: '%s' not supported — use signals\n", ...); YYERROR; }
    ;

signal_decl
    : KW_SIGNAL ident_list ':' KW_STD_LOGIC opt_init ';'
        { $$ = vsignal_decl_new($2, $5, yylineno); }
    ;
```

Left-recursion builds the list: `NULL → [A] → [A, B] → [A, B, C]`.

### Architecture Body

```yacc
arch_body
    : /* empty */                        { $$ = varch_body_new(); }
    | arch_body IDENT OP_SIGNAL_ASSIGN expr ';'
        { $$ = varch_body_add_conc($1, vconc_assign_new($2, $4, yylineno)); }
    | arch_body gate_process             { $$ = varch_body_add_gate($1, $2); }
    | arch_body KW_PROCESS KW_BEGIN_KW { stim_time = 0; }
      stim_steps KW_WAIT ';' end_tag
        { $$ = varch_body_add_stim($1, vstim_process_new($5, yylineno)); }
    ;
```

Concurrent assigns, gate processes, and stimulus are inlined directly. Bison distinguishes them by lookahead:
- `IDENT <=` → concurrent assign
- `process(` → gate process
- `process begin` → stimulus process
- `end` → done

### Gate Process

```yacc
gate_process
    : KW_PROCESS '(' sensitivity_list ')' KW_BEGIN_KW
      if_statement end_tag
        { $$ = vgate_process_new($3, $6, NULL, yylineno); }
    | KW_PROCESS '(' sensitivity_list ')' KW_BEGIN_KW
      assign_list_nonempty end_tag
        { $$ = vgate_process_new($3, NULL, $6, yylineno); }
    ;
```

Two body variants: `if/elsif/else` (DFF, MUX, latch) or direct assigns (combinational). First token after `begin` decides: `KW_IF` or `IDENT`.

### If / Elsif / Else

```yacc
if_statement
    : KW_IF condition KW_THEN assign_list elsif_list else_opt KW_END KW_IF ';'
        { /* builds VIfBranchList: if-branch + elsif-branches + optional else-branch */ }
    ;

elsif_list
    : /* empty */                                          { $$ = NULL; }
    | elsif_list KW_ELSIF condition KW_THEN assign_list    { append branch }
    ;

else_opt
    : /* empty */          { $$ = NULL; }
    | KW_ELSE assign_list { $$ = $2; }
    ;
```

For `if rising_edge(CLK) then Q<=D; end if;`:
```
Branch 1: condition=FuncCall("rising_edge",CLK), assigns=[Q<=D]
```

For `if SEL='1' then Y<=A; else Y<=B; end if;`:
```
Branch 1: condition=Binary("=",SEL,'1'), assigns=[Y<=A]
Branch 2: condition=NULL,                 assigns=[Y<=B]   (NULL = else)
```

### Condition

```yacc
condition
    : KW_RISING_EDGE '(' IDENT ')'    → FuncCall node
    | KW_FALLING_EDGE '(' IDENT ')'   → FuncCall node
    | IDENT '=' LIT_CHAR              → Binary("=") node
    ;
```

Only three forms. Anything else is a parse error — intentional, since the code generator only recognizes DFF, MUX, and latch patterns.

### Stimulus Process

```yacc
stim_steps
    : assign_list_nonempty KW_WAIT KW_FOR LIT_INTEGER KW_NS ';'
        { $$ = new step at stim_time; stim_time += $4; }
    | stim_steps assign_list_nonempty KW_WAIT KW_FOR LIT_INTEGER KW_NS ';'
        { $$ = append step at stim_time; stim_time += $5; }
    ;
```

Each step = assigns + `wait for N ns`. Uses `assign_list_nonempty` (not `assign_list`) to avoid shift-reduce conflict with the final `wait;`.

### Expressions

```yacc
expr      → expr_or
expr_or   → expr_and | expr_or (or|nor|xnor) expr_and      // lowest
expr_and  → expr_unary | expr_and (and|nand|xor) expr_unary // higher
expr_unary → expr_primary | not expr_unary                   // highest
expr_primary → IDENT | LIT_CHAR | '(' expr ')' | func_call  // atoms
```

Precedence encoded in grammar structure: `or` contains `and` as operands, so `and` binds tighter. Example:

```
A and B or C and D  →  (A and B) or (C and D)

      Binary(or)
       /      \
  Binary(and)  Binary(and)
   /    \       /    \
  A      B     C      D
```

---

## Error Handling

```c
void yyerror(const char *s) {
    if (yytext == NULL || yytext[0] == '\0')
        fprintf(stderr, "Syntax error at line %d: unexpected end of input\n", yylineno);
    else if (s && strcmp(s, "syntax error") != 0)
        fprintf(stderr, "Syntax error at line %d: %s\n", yylineno, s);
    else
        fprintf(stderr, "Syntax error at line %d: unexpected token '%s'\n", yylineno, yytext);
}
```

`%define parse.error verbose` makes Bison generate detailed messages. REJECTED_KEYWORD rules intercept unsupported keywords before the generic handler, giving specific messages:

```
Line 5: 'variable' not supported — use signals
Line 1: 'library' not supported — no imports needed
```

---

## Build and Test

```bash
make vhdl-parser    # generates + compiles into build/vhdl/
make clean          # removes build/vhdl/ entirely
```

### Test output for `and_gate.vhd`

```
Entity: and_gate_tb  Arch: test
signal A, B, OUT1 := '0'
OUT1 <= Binary(and) Ident(A) Ident(B)
@0: A<='0' B<='0'
@10: A<='1'
@20: B<='1'
@30: A<='0'
OK!
```

### Error tests

```
$ ./test bad_variable.vhd
Line 5: 'variable' not supported — use signals

$ ./test bad_library.vhd
Line 1: 'library' not supported — no imports needed
```
