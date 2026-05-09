/*
 * vhdl_lexer.l — Flex lexer for the supported VHDL subset
 *
 * Tokenizes a .vhd file into keywords, operators, identifiers, and
 * literals that the Bison parser (vhdl_parser.y) can consume.
 *
 * Key design decisions:
 *   - Case-insensitive to match VHDL semantics
 *   - Only '0' and '1' character literals (single-bit signals)
 *   - Unsupported VHDL keywords are explicitly rejected with clear
 *     error messages rather than silently misinterpreted
 *
 * Build:
 *   bison -d -o vhdl_parser.tab.c include/vhdl/vhdl_parser.y
 *   flex -o vhdl_lexer.c include/vhdl/vhdl_lexer.l
 */

%{
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "vhdl_parser.tab.h"
%}

%option noyywrap
%option noinput nounput
%option yylineno
%option case-insensitive

%%

    /* ── Whitespace and comments ───────────────────── */
[ \t\r]+                ;
\n                      ;
"--".*                  ;

    /* ── Supported VHDL keywords ───────────────────── */
"entity"                { return KW_ENTITY; }
"is"                    { return KW_IS; }
"end"                   { return KW_END; }
"architecture"          { return KW_ARCHITECTURE; }
"of"                    { return KW_OF; }
"begin"                 { return KW_BEGIN_KW; }
"signal"                { return KW_SIGNAL; }
"std_logic"             { return KW_STD_LOGIC; }
"process"               { return KW_PROCESS; }
"if"                    { return KW_IF; }
"then"                  { return KW_THEN; }
"elsif"                 { return KW_ELSIF; }
"else"                  { return KW_ELSE; }
"and"                   { return KW_AND; }
"or"                    { return KW_OR; }
"not"                   { return KW_NOT; }
"xor"                   { return KW_XOR; }
"nand"                  { return KW_NAND; }
"nor"                   { return KW_NOR; }
"xnor"                  { return KW_XNOR; }
"rising_edge"           { return KW_RISING_EDGE; }
"falling_edge"          { return KW_FALLING_EDGE; }
"wait"                  { return KW_WAIT; }
"for"                   { return KW_FOR; }
"ns"                    { return KW_NS; }

    /* ── Rejected keywords ─────────────────────────── */
    /* These are valid VHDL but not supported by our subset.       */
    /* We reject them explicitly so the user gets a helpful error  */
    /* instead of a confusing "unexpected token" from the parser.  */
"library"               { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"use"                   { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"port"                  { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"in"                    { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"out"                   { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"inout"                 { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"variable"              { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"while"                 { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"loop"                  { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"generate"              { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"component"             { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"map"                   { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"function"              { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"procedure"             { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"package"               { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"type"                  { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"subtype"               { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"record"                { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"array"                 { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"after"                 { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"with"                  { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"select"                { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"when"                  { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"assert"                { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"report"                { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"generic"               { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }
"buffer"                { yylval.sval = strdup(yytext); return REJECTED_KEYWORD; }

    /* ── Multi-character operators ──────────────────── */
"<="                    { return OP_SIGNAL_ASSIGN; }
":="                    { return OP_VAR_ASSIGN; }

    /* ── Character literals: only '0' and '1' ──────── */
"'0'"                   { yylval.cval = '0'; return LIT_CHAR; }
"'1'"                   { yylval.cval = '1'; return LIT_CHAR; }
"'"[^'']"'"             { fprintf(stderr, "Line %d: only '0' and '1' supported, got %s\n",
                            yylineno, yytext); exit(1); }

    /* ── Integer literals (for "wait for 10 ns") ───── */
[0-9]+                  { yylval.ival = atoi(yytext); return LIT_INTEGER; }

    /* ── Identifiers ───────────────────────────────── */
[a-zA-Z_][a-zA-Z0-9_]* { yylval.sval = strdup(yytext); return IDENT; }

    /* ── Single-character punctuation ──────────────── */
":"                     { return ':'; }
";"                     { return ';'; }
"("                     { return '('; }
")"                     { return ')'; }
","                     { return ','; }
"="                     { return '='; }

    /* ── Catch-all for unexpected characters ────────── */
.                       { fprintf(stderr, "Line %d: unexpected character '%s'\n",
                            yylineno, yytext); exit(1); }
%%
