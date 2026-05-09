// VHDLAST.hpp — All the "boxes" that hold parsed VHDL info
//
// Think of it like this:
//   Raw text  ->  Lexer makes tokens  ->  Parser puts tokens into these boxes
//
// Each struct is one kind of box.

#ifndef VHDLAST_HPP
#define VHDLAST_HPP

#include <string>
#include <vector>
#include <memory>

using namespace std;

// ──────────────────────────────────────────────────────────
// Expr — an expression tree node
//
// Example:  "A and B"  becomes:
//
//       BinaryOp(AND)
//        /        \
//   Ident("a")   Ident("b")
//
// Example:  "not A"  becomes:
//
//       UnaryOp(NOT)
//            |
//       Ident("a")
// ──────────────────────────────────────────────────────────

struct Expr {
    // what kind of expression is this?
    enum Kind {
        IDENT,       // just a signal name, like "a" or "out1"
        LITERAL,     // '0' or '1'
        UNARY_OP,    // "not X"
        BINARY_OP,   // "A and B"
        FUNC_CALL    // "rising_edge(clk)" or "falling_edge(clk)"
    };

    Kind kind;

    // the text value:
    //   IDENT    -> signal name ("a", "out1")
    //   LITERAL  -> "0" or "1"
    //   UNARY_OP -> "not"
    //   BINARY_OP -> "and", "or", "xor", "nand", "nor", "xnor"
    //   FUNC_CALL -> "rising_edge" or "falling_edge"
    string value;

    // children:
    //   IDENT / LITERAL -> no children (leaf node)
    //   UNARY_OP        -> one child (left)
    //   BINARY_OP       -> two children (left and right)
    //   FUNC_CALL       -> one child (the signal inside parentheses)
    shared_ptr<Expr> left;
    shared_ptr<Expr> right;

    int line;  // line number in the .vhd file (for error messages)
};

// helper functions to make Expr nodes easily
// (so we don't have to write out the struct every time)

inline shared_ptr<Expr> make_ident(const string& name, int line) {
    auto e = make_shared<Expr>();
    e->kind = Expr::IDENT;
    e->value = name;
    e->line = line;
    return e;
}

inline shared_ptr<Expr> make_literal(const string& val, int line) {
    auto e = make_shared<Expr>();
    e->kind = Expr::LITERAL;
    e->value = val;
    e->line = line;
    return e;
}

inline shared_ptr<Expr> make_unary(const string& op,
                                         shared_ptr<Expr> child, int line) {
    auto e = make_shared<Expr>();
    e->kind = Expr::UNARY_OP;
    e->value = op;
    e->left = child;
    e->line = line;
    return e;
}

inline shared_ptr<Expr> make_binary(const string& op,
                                          shared_ptr<Expr> left,
                                          shared_ptr<Expr> right, int line) {
    auto e = make_shared<Expr>();
    e->kind = Expr::BINARY_OP;
    e->value = op;
    e->left = left;
    e->right = right;
    e->line = line;
    return e;
}

inline shared_ptr<Expr> make_func_call(const string& func_name,
                                              shared_ptr<Expr> arg, int line) {
    auto e = make_shared<Expr>();
    e->kind = Expr::FUNC_CALL;
    e->value = func_name;
    e->left = arg;
    e->line = line;
    return e;
}

// ──────────────────────────────────────────────────────────
// SignalDecl — one signal declaration line
//
// Example: "signal A, B, OUT1 : std_logic := '0';"
//   names = ["a", "b", "out1"]
//   init  = "0"
// ──────────────────────────────────────────────────────────

struct SignalDecl {
    vector<string> names;  // one or more signal names
    string init;                // initial value: "0" or "1" or "" if none
    int line;
};

// ──────────────────────────────────────────────────────────
// ConcurrentAssign — one signal assignment outside a process
//
// Example: "OUT1 <= A and B;"
//   target = "out1"
//   expr   = BinaryOp(AND, Ident("a"), Ident("b"))
// ──────────────────────────────────────────────────────────

struct ConcurrentAssign {
    string target;              // signal being assigned to
    shared_ptr<Expr> expr;      // the expression tree
    int line;
};

// ──────────────────────────────────────────────────────────
// SignalAssign — a simple assignment inside a process
//
// Example: "Q <= D;"  or  "Q <= '1';"
//   target = "q"
//   expr   = the right-hand side expression
// ──────────────────────────────────────────────────────────

struct SignalAssign {
    string target;
    shared_ptr<Expr> expr;
    int line;
};

// ──────────────────────────────────────────────────────────
// IfBranch — one branch of if / elsif / else
//
// Example:
//   if rising_edge(CLK) then    <-- condition = FuncCall("rising_edge", "clk")
//     Q <= D;                   <-- assigns = [SignalAssign("q", Ident("d"))]
//   end if;
//
// For "else" branch, condition is nullptr (no condition needed)
// ──────────────────────────────────────────────────────────

struct IfBranch {
    shared_ptr<Expr> condition;      // nullptr for "else"
    vector<SignalAssign> assigns;
    int line;
};

// ──────────────────────────────────────────────────────────
// GateProcess — a process with a sensitivity list
//
// Example:
//   process(CLK)
//   begin
//     if rising_edge(CLK) then
//       Q <= D;
//     end if;
//   end process;
//
//   sensitivity_list = ["clk"]
//   branches = [IfBranch with rising_edge condition]
// ──────────────────────────────────────────────────────────

struct GateProcess {
    vector<string> sensitivity_list;
    vector<IfBranch> branches;

    // if the process body is just assignments (no if/else),
    // they go here instead of in branches
    vector<SignalAssign> direct_assigns;
    int line;
};

// ──────────────────────────────────────────────────────────
// StimulusStep — one moment in time during simulation
//
// Example:
//   A <= '1';           <-- at time 10
//   wait for 10 ns;     <-- next step starts at time 20
//
//   time = 10
//   assigns = [SignalAssign("a", Literal("1"))]
// ──────────────────────────────────────────────────────────

struct StimulusStep {
    int time;                             // absolute time in ns
    vector<SignalAssign> assigns;
};

// ──────────────────────────────────────────────────────────
// StimulusProcess — the whole test stimulus
//
// Example:
//   process
//   begin
//     A <= '0'; B <= '0';    -- time 0
//     wait for 10 ns;
//     A <= '1';              -- time 10
//     wait for 10 ns;
//     wait;
//   end process;
//
//   steps = [
//     StimulusStep(0, [A='0', B='0']),
//     StimulusStep(10, [A='1'])
//   ]
// ──────────────────────────────────────────────────────────

struct StimulusProcess {
    vector<StimulusStep> steps;
    int line;
};

// ──────────────────────────────────────────────────────────
// VHDLDesign — the ENTIRE parsed .vhd file
//
// This is the "big box" that holds everything.
// After parsing, you get one of these back.
// ──────────────────────────────────────────────────────────

struct VHDLDesign {
    string entity_name;                         // e.g. "and_gate_tb"
    string architecture_name;                   // e.g. "test"
    vector<SignalDecl> signals;                  // all signal declarations
    vector<ConcurrentAssign> concurrent_assigns; // assignments outside processes
    vector<GateProcess> gate_processes;          // process blocks with sensitivity list
    StimulusProcess stimulus;                         // the stimulus process (at most one)
    bool has_stimulus;                                // did we find a stimulus process?

    VHDLDesign() : has_stimulus(false) {}
};

#endif
