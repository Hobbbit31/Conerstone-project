/*
 * vhdl_parser.y — Bison grammar for the supported VHDL subset
 *
 * Parses a .vhd file and builds a C AST (VHDLDesign) that the code
 * generator can walk to produce .net and .stim files.
 *
 * Supported VHDL constructs:
 *   - Entity declarations (empty — no ports, signals are internal)
 *   - Architecture with signal declarations
 *   - Concurrent signal assignments: Y <= A and B;
 *   - Process blocks with sensitivity lists:
 *       * DFF:  if rising_edge(CLK) then Q <= D; end if;
 *       * MUX:  if SEL='1' then Y<=A; else Y<=B; end if;
 *       * SR:   if S='1' then Q<='1'; elsif R='1' then Q<='0'; end if;
 *       * Comb: Y <= A and B;  (direct assignments inside process)
 *   - Stimulus process: assignments + "wait for N ns;" blocks
 *
 * Expression precedence (low to high):
 *   or, nor, xnor  →  and, nand, xor  →  not  →  primary (ident, literal, parens)
 */

%{
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "vhdl_ast.h"

extern int yylex(void);
extern int yylineno;
void yyerror(const char *s);

/* root of the parsed AST — set by the top-level 'design' rule */
VHDLDesign *vhdl_root = NULL;

/* running time accumulator for stimulus steps */
static int stim_time = 0;
%}

%code requires {
#include "vhdl_ast.h"
}

%start design
%define parse.error verbose

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

/* ── Token declarations ──────────────────────────────────── */

%token KW_ENTITY KW_IS KW_END KW_ARCHITECTURE KW_OF KW_BEGIN_KW
%token KW_SIGNAL KW_STD_LOGIC KW_PROCESS
%token KW_IF KW_THEN KW_ELSIF KW_ELSE
%token KW_AND KW_OR KW_NOT KW_XOR KW_NAND KW_NOR KW_XNOR
%token KW_RISING_EDGE KW_FALLING_EDGE
%token KW_WAIT KW_FOR KW_NS
%token OP_SIGNAL_ASSIGN OP_VAR_ASSIGN

%token <cval> LIT_CHAR
%token <ival> LIT_INTEGER
%token <sval> IDENT
%token <sval> REJECTED_KEYWORD

/* ── Non-terminal type declarations ──────────────────────── */

%type <design>          design
%type <signal_decl_list> signal_decl_list
%type <signal_decl>     signal_decl
%type <ident_list>      ident_list sensitivity_list
%type <cval>            opt_init
%type <arch_body>       arch_body
%type <gate_proc>       gate_process
%type <stim_step_list>  stim_steps
%type <assign_list>     assign_list assign_list_nonempty else_opt
%type <if_branch_list>  if_statement elsif_list
%type <expr>            expr expr_or expr_and expr_unary expr_primary condition

%%

/* ── Top-level design ────────────────────────────────────── */

design
    : entity_decl KW_ARCHITECTURE IDENT KW_OF IDENT KW_IS
      signal_decl_list KW_BEGIN_KW arch_body end_tag
        { $$ = vhdl_design_new($5, $3, $7, $9); vhdl_root = $$; }
    | REJECTED_KEYWORD
        {
            fprintf(stderr, "Line %d: '%s' not supported — no imports needed\n",
                    yylineno, $1);
            free($1); YYERROR;
        }
    ;

/* ── Entity declaration (empty — our subset has no ports) ── */

entity_decl
    : KW_ENTITY IDENT KW_IS end_tag { free($2); }
    ;

/* ── Various "end" forms that VHDL allows ────────────────── */

end_tag
    : KW_END ';'
    | KW_END IDENT ';'                 { free($2); }
    | KW_END KW_ENTITY ';'
    | KW_END KW_ENTITY IDENT ';'      { free($3); }
    | KW_END KW_ARCHITECTURE ';'
    | KW_END KW_ARCHITECTURE IDENT ';' { free($3); }
    | KW_END KW_PROCESS ';'
    ;

/* ── Signal declarations ─────────────────────────────────── */

signal_decl_list
    : /* empty */ { $$ = NULL; }
    | signal_decl_list signal_decl { $$ = vsignal_decl_list_append($1, $2); }
    | signal_decl_list REJECTED_KEYWORD
        {
            fprintf(stderr, "Line %d: '%s' not supported — use signals\n",
                    yylineno, $2);
            free($2); YYERROR;
        }
    ;

signal_decl
    : KW_SIGNAL ident_list ':' KW_STD_LOGIC opt_init ';'
        { $$ = vsignal_decl_new($2, $5, yylineno); }
    ;

opt_init
    : /* empty */             { $$ = '\0'; }
    | OP_VAR_ASSIGN LIT_CHAR { $$ = $2; }
    ;

ident_list
    : IDENT                  { $$ = vident_list_new($1); }
    | ident_list ',' IDENT   { $$ = vident_list_append($1, $3); }
    ;

/* ── Architecture body ───────────────────────────────────── */

arch_body
    : /* empty */                        { $$ = varch_body_new(); }
    | arch_body IDENT OP_SIGNAL_ASSIGN expr ';'
        { $$ = varch_body_add_conc($1, vconc_assign_new($2, $4, yylineno)); }
    | arch_body gate_process             { $$ = varch_body_add_gate($1, $2); }
    | arch_body KW_PROCESS KW_BEGIN_KW { stim_time = 0; }
      stim_steps KW_WAIT ';' end_tag
        { $$ = varch_body_add_stim($1, vstim_process_new($5, yylineno)); }
    ;

/* ── Gate processes (with sensitivity list) ──────────────── */

gate_process
    : KW_PROCESS '(' sensitivity_list ')' KW_BEGIN_KW
      if_statement end_tag
        { $$ = vgate_process_new($3, $6, NULL, yylineno); }
    | KW_PROCESS '(' sensitivity_list ')' KW_BEGIN_KW
      assign_list_nonempty end_tag
        { $$ = vgate_process_new($3, NULL, $6, yylineno); }
    ;

sensitivity_list
    : IDENT                        { $$ = vident_list_new($1); }
    | sensitivity_list ',' IDENT   { $$ = vident_list_append($1, $3); }
    ;

/* ── If/elsif/else statement ─────────────────────────────── */

if_statement
    : KW_IF condition KW_THEN assign_list elsif_list else_opt KW_END KW_IF ';'
        {
            /* build the branch list: first branch, then elsifs, then else */
            VIfBranch *first = vif_branch_new($2, $4, yylineno);
            $$ = vif_branch_list_append(NULL, first);
            if ($5) {
                /* attach elsif chain to the end */
                VIfBranchList *t = $$;
                while (t->next) t = t->next;
                t->next = $5;
            }
            if ($6) $$ = vif_branch_list_append($$, vif_branch_new(NULL, $6, yylineno));
        }
    ;

elsif_list
    : /* empty */ { $$ = NULL; }
    | elsif_list KW_ELSIF condition KW_THEN assign_list
        { $$ = vif_branch_list_append($1, vif_branch_new($3, $5, yylineno)); }
    ;

else_opt
    : /* empty */          { $$ = NULL; }
    | KW_ELSE assign_list { $$ = $2; }
    ;

/* ── Conditions (if-guards) ──────────────────────────────── */

condition
    : KW_RISING_EDGE '(' IDENT ')'
        { $$ = vexpr_func_call("rising_edge", vexpr_ident($3, yylineno), yylineno); }
    | KW_FALLING_EDGE '(' IDENT ')'
        { $$ = vexpr_func_call("falling_edge", vexpr_ident($3, yylineno), yylineno); }
    | IDENT '=' LIT_CHAR
        { $$ = vexpr_binary("=", vexpr_ident($1, yylineno), vexpr_literal($3, yylineno), yylineno); }
    ;

/* ── Assignment lists (inside process bodies) ────────────── */

assign_list
    : /* empty */                { $$ = NULL; }
    | assign_list IDENT OP_SIGNAL_ASSIGN expr ';'
        { $$ = vassign_list_append($1, vsignal_assign_new($2, $4, yylineno)); }
    ;

assign_list_nonempty
    : IDENT OP_SIGNAL_ASSIGN expr ';'
        { $$ = vassign_list_append(NULL, vsignal_assign_new($1, $3, yylineno)); }
    | assign_list_nonempty IDENT OP_SIGNAL_ASSIGN expr ';'
        { $$ = vassign_list_append($1, vsignal_assign_new($2, $4, yylineno)); }
    ;

/* ── Stimulus steps ──────────────────────────────────────── */
/* Each step is: assignments + "wait for N ns;"              */
/* Time is accumulated: first wait sets absolute time,       */
/* subsequent waits add to the running total.                */

stim_steps
    : assign_list_nonempty KW_WAIT KW_FOR LIT_INTEGER KW_NS ';'
        {
            $$ = vstim_step_list_append(NULL, vstim_step_new(stim_time, $1));
            stim_time += $4;
        }
    | stim_steps assign_list_nonempty KW_WAIT KW_FOR LIT_INTEGER KW_NS ';'
        {
            $$ = vstim_step_list_append($1, vstim_step_new(stim_time, $2));
            stim_time += $5;
        }
    ;

/* ── Expression grammar (precedence climbing) ────────────── */

expr
    : expr_or { $$ = $1; }
    ;

/* lowest precedence: or, nor, xnor */
expr_or
    : expr_and                     { $$ = $1; }
    | expr_or KW_OR expr_and      { $$ = vexpr_binary("or", $1, $3, yylineno); }
    | expr_or KW_NOR expr_and     { $$ = vexpr_binary("nor", $1, $3, yylineno); }
    | expr_or KW_XNOR expr_and   { $$ = vexpr_binary("xnor", $1, $3, yylineno); }
    ;

/* medium precedence: and, nand, xor */
expr_and
    : expr_unary                    { $$ = $1; }
    | expr_and KW_AND expr_unary   { $$ = vexpr_binary("and", $1, $3, yylineno); }
    | expr_and KW_NAND expr_unary  { $$ = vexpr_binary("nand", $1, $3, yylineno); }
    | expr_and KW_XOR expr_unary   { $$ = vexpr_binary("xor", $1, $3, yylineno); }
    ;

/* high precedence: not (unary) */
expr_unary
    : expr_primary       { $$ = $1; }
    | KW_NOT expr_unary  { $$ = vexpr_unary("not", $2, yylineno); }
    ;

/* highest precedence: identifiers, literals, parenthesized, function calls */
expr_primary
    : IDENT                            { $$ = vexpr_ident($1, yylineno); }
    | LIT_CHAR                         { $$ = vexpr_literal($1, yylineno); }
    | '(' expr ')'                     { $$ = $2; }
    | KW_RISING_EDGE '(' IDENT ')'    { $$ = vexpr_func_call("rising_edge", vexpr_ident($3, yylineno), yylineno); }
    | KW_FALLING_EDGE '(' IDENT ')'   { $$ = vexpr_func_call("falling_edge", vexpr_ident($3, yylineno), yylineno); }
    ;

%%

/* ── Error reporting ─────────────────────────────────────── */

extern char *yytext;

void yyerror(const char *s) {
    if (yytext == NULL || yytext[0] == '\0') {
        fprintf(stderr, "Syntax error at line %d: unexpected end of input\n", yylineno);
        return;
    }
    if (s && strcmp(s, "syntax error") != 0) {
        fprintf(stderr, "Syntax error at line %d: %s\n", yylineno, s);
    } else {
        fprintf(stderr, "Syntax error at line %d: unexpected token '%s'\n", yylineno, yytext);
    }
}
