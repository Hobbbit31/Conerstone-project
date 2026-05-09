/*
 * VHDLCodeGen.hpp — Translates the VHDL AST into .net and .stim strings
 *
 * After the Flex/Bison parser produces a C AST (VHDLDesign), this code
 * generator walks it and emits:
 *   - .net content: signal declarations + gate instantiations
 *   - .stim content: timed stimulus assignments
 *
 * The output format matches what NetlistParser and StimParser already
 * read, so nothing else in the simulator needs to change.
 *
 * The trickiest part is "flattening" VHDL expressions into individual
 * gate lines.  For example:
 *
 *   VHDL:   Cout <= (A and B) or (Cin and (A xor B));
 *
 *   Becomes:
 *     signal _t0 0
 *     signal _t1 0
 *     signal _t2 0
 *     xor  _t0  A    B
 *     and  _t1  Cin  _t0
 *     and  _t2  A    B
 *     or   Cout _t2  _t1
 *
 * Each sub-expression gets a temporary signal (_t0, _t1, ...) and its
 * own gate line.  Simple identifiers and literals are used directly.
 */

#ifndef VHDL_CODEGEN_HPP
#define VHDL_CODEGEN_HPP

#include <string>
#include <stdexcept>

using namespace std;

extern "C" {
#include "vhdl_ast.h"
}

// Result of code generation — two strings ready to write to files
struct CodeGenResult {
    string net_content;   // signal + gate lines → .net file
    string stim_content;  // @time sig=val lines → .stim file
};

// ── Globals used during a single generate() call ────────────────────
//
// These are 'inline' (not 'static') so that if this header is included
// from multiple translation units, there's only one shared copy.
// With 'static', each .cpp would get its own copy and the strings
// written in one TU would be invisible to another.

static string g_signals;       // accumulated "signal X 0\n" lines
static string g_gates;         // accumulated "and OUT A B\n" lines
static string g_stim;          // accumulated "@10 A=1\n" lines
static int g_temp = 0;              // counter for temp signal names: _t0, _t1, ...
static bool g_has_const0 = false;   // have we already emitted _const0?
static bool g_has_const1 = false;   // have we already emitted _const1?

// forward declarations (mutually recursive)
inline string flatten_child(VExpr *child);
inline string flatten_expr(VExpr *expr, const string &target);

/*
 * flatten_child — resolve one operand of an expression
 *
 * Returns the signal name that holds this operand's value:
 *   - Simple identifier ("A")      → return "A" directly
 *   - Literal ('0' or '1')         → create a _const0/_const1 signal
 *   - Complex sub-expression       → create a temp signal, emit its gate, return temp name
 */
inline string flatten_child(VExpr *child) {
    // simple signal name — use it directly
    if (child->kind == VEXPR_IDENT) {
        return string(child->value);
    }

    // literal '0' or '1' — need a constant signal to feed into gates
    if (child->kind == VEXPR_LITERAL) {
        if (child->value[0] == '0') {
            if (!g_has_const0) {
                g_signals += "signal _const0 0\n";
                g_has_const0 = true;
            }
            return "_const0";
        } else {
            if (!g_has_const1) {
                g_signals += "signal _const1 1\n";
                g_has_const1 = true;
            }
            return "_const1";
        }
    }

    // complex sub-expression — allocate a temp signal and flatten recursively
    string temp = "_t" + to_string(g_temp++);
    g_signals += "signal " + temp + " 0\n";
    flatten_expr(child, temp);
    return temp;
}

/*
 * flatten_expr — emit gate lines for an expression, writing result to 'target'
 *
 * Walks the expression tree recursively.  Each node becomes one gate line.
 */
inline string flatten_expr(VExpr *expr, const string &target) {
    // bare identifier: "X <= Y" needs a buf gate to drive target from source
    if (expr->kind == VEXPR_IDENT) {
        string src(expr->value);
        if (src != target) {
            g_gates += "buf " + target + " " + src + "\n";
        }
        return target;
    }

    // bare literal: delegate to flatten_child (creates _const signal)
    if (expr->kind == VEXPR_LITERAL) {
        return flatten_child(expr);
    }

    // unary: "not X"
    if (expr->kind == VEXPR_UNARY) {
        string child_sig = flatten_child(expr->left);
        g_gates += string(expr->value) + " " + target + " " + child_sig + "\n";
        return target;
    }

    // binary: "A and B", "A or B", etc.
    if (expr->kind == VEXPR_BINARY) {
        string left_sig  = flatten_child(expr->left);
        string right_sig = flatten_child(expr->right);
        g_gates += string(expr->value) + " " + target
                   + " " + left_sig + " " + right_sig + "\n";
        return target;
    }

    throw runtime_error("CodeGen: unexpected expression type in concurrent assignment");
}

// ── Part 1: emit signal declarations ────────────────────────────────

inline void codegen_signals(VSignalDeclList *list) {
    VSignalDeclList *cur = list;
    while (cur != NULL) {
        VSignalDecl *decl = cur->decl;

        int init = (decl->init == '1') ? 1 : 0;

        // a single declaration can have multiple names:
        // "signal A, B, C : std_logic := '0';"
        VIdentList *name = decl->names;
        while (name != NULL) {
            g_signals += "signal " + string(name->name)
                         + " " + to_string(init) + "\n";
            name = name->next;
        }

        cur = cur->next;
    }
}

// ── Part 2: emit concurrent signal assignments ─────────────────────

inline void codegen_concurrent(VConcAssignList *list) {
    VConcAssignList *cur = list;
    while (cur != NULL) {
        string target(cur->assign->target);
        flatten_expr(cur->assign->expr, target);
        cur = cur->next;
    }
}

// ── Part 3: emit gate processes ─────────────────────────────────────
//
// Each VHDL process block is pattern-matched to a specific gate type:
//   - DFF:   process(CLK) begin if rising_edge(CLK) then Q<=D; end if; end process;
//   - MUX:   process(...) begin if SEL='1' then Y<=A; else Y<=B; end if; end process;
//   - SR:    process(S,R) begin if S='1' then Q<='1'; elsif R='1' then Q<='0'; end if; end process;
//   - Comb:  process(A,B) begin Y <= A and B; end process;

inline void codegen_processes(VGateProcList *list) {
    VGateProcList *cur = list;
    while (cur != NULL) {
        VGateProcess *proc = cur->proc;

        // --- Combinational: no if/else, just direct assignments ---
        if (proc->branches == NULL && proc->direct_assigns != NULL) {
            VAssignList *a = proc->direct_assigns;
            while (a != NULL) {
                flatten_expr(a->assign->expr, string(a->assign->target));
                a = a->next;
            }
            cur = cur->next;
            continue;
        }

        // count branches to determine the pattern
        int branch_count = 0;
        VIfBranchList *b = proc->branches;
        while (b != NULL) { branch_count++; b = b->next; }

        VIfBranch *first = proc->branches->branch;

        // --- Try DFF pattern ---
        // exactly 1 branch with a rising_edge/falling_edge condition
        if (branch_count == 1
            && first->condition != NULL
            && first->condition->kind == VEXPR_FUNC_CALL)
        {
            string func(first->condition->value);
            if (func == "rising_edge" || func == "falling_edge") {
                string clk(first->condition->left->value);

                // safety check: the process body must have at least one assignment
                if (first->assigns == NULL || first->assigns->assign == NULL
                    || first->assigns->assign->expr == NULL) {
                    throw runtime_error("CodeGen line " + to_string(proc->line) +
                        ": DFF process has rising_edge/falling_edge but no assignments inside");
                }

                // first assignment tells us Q and D
                string q(first->assigns->assign->target);
                string d(first->assigns->assign->expr->value);

                // second assignment gives Q_NOT, or we create a dummy
                string q_not;
                if (first->assigns->next != NULL) {
                    q_not = string(first->assigns->next->assign->target);
                } else {
                    q_not = "_q_not_" + to_string(g_temp++);
                    g_signals += "signal " + q_not + " 1\n";
                }

                g_gates += "dff " + q + " " + q_not + " " + clk + " " + d + "\n";
                cur = cur->next;
                continue;
            }
        }

        // --- Try MUX pattern ---
        // exactly 2 branches: if (SEL='1') then ... else ...
        if (branch_count == 2) {
            VIfBranch *if_branch   = proc->branches->branch;
            VIfBranch *else_branch = proc->branches->next->branch;

            if (else_branch->condition == NULL
                && if_branch->condition != NULL
                && if_branch->condition->kind == VEXPR_BINARY
                && string(if_branch->condition->value) == "="
                && if_branch->condition->left->kind == VEXPR_IDENT
                && if_branch->condition->right->kind == VEXPR_LITERAL
                && if_branch->assigns != NULL
                && else_branch->assigns != NULL
                && if_branch->assigns->assign != NULL
                && if_branch->assigns->assign->expr != NULL
                && else_branch->assigns->assign != NULL
                && else_branch->assigns->assign->expr != NULL)
            {
                string sel(if_branch->condition->left->value);
                char sel_val = if_branch->condition->right->value[0];
                string target(if_branch->assigns->assign->target);
                string if_sig(if_branch->assigns->assign->expr->value);
                string else_sig(else_branch->assigns->assign->expr->value);

                // mux format: mux OUT A B SEL  (sel=0 picks A, sel=1 picks B)
                if (sel_val == '1') {
                    g_gates += "mux " + target + " " + else_sig + " " + if_sig + " " + sel + "\n";
                } else {
                    g_gates += "mux " + target + " " + if_sig + " " + else_sig + " " + sel + "\n";
                }
                cur = cur->next;
                continue;
            }

            // --- Try SR Latch pattern ---
            // 2 branches, both with conditions (if S='1' ... elsif R='1' ...)
            VIfBranch *second = proc->branches->next->branch;
            if (first->condition != NULL
                && second->condition != NULL
                && first->condition->kind == VEXPR_BINARY
                && second->condition->kind == VEXPR_BINARY
                && string(first->condition->value) == "="
                && string(second->condition->value) == "="
                && first->assigns != NULL)
            {
                string s_sig(first->condition->left->value);
                string r_sig(second->condition->left->value);
                string q(first->assigns->assign->target);

                // create a dummy Q_NOT signal
                string q_not = "_q_not_" + to_string(g_temp++);
                g_signals += "signal " + q_not + " 0\n";

                g_gates += "sr " + q + " " + q_not + " " + s_sig + " " + r_sig + "\n";
                cur = cur->next;
                continue;
            }
        }

        throw runtime_error("CodeGen line " + to_string(proc->line) +
            ": could not figure out what hardware this process is.\n"
            "Supported: DFF, MUX, SR Latch, Combinational.");

        cur = cur->next;
    }
}

// ── Part 4: emit stimulus ───────────────────────────────────────────

inline void codegen_stimulus(VStimulusProcess *proc) {
    if (proc == NULL) return;

    VStimStepList *step_node = proc->steps;
    while (step_node != NULL) {
        VStimulusStep *step = step_node->step;

        VAssignList *a = step->assigns;
        while (a != NULL) {
            string sig(a->assign->target);
            string val(a->assign->expr->value);  // always '0' or '1'
            g_stim += "@" + to_string(step->time) + " " + sig + "=" + val + "\n";
            a = a->next;
        }

        step_node = step_node->next;
    }
}

// ── Main entry point ────────────────────────────────────────────────

class VHDLCodeGen {
public:
    static CodeGenResult generate(VHDLDesign *design) {
        // reset all globals for a fresh run
        g_signals    = "";
        g_gates      = "";
        g_stim       = "";
        g_temp       = 0;
        g_has_const0 = false;
        g_has_const1 = false;

        // generate each section in order
        codegen_signals(design->signals);
        codegen_concurrent(design->concurrent_assigns);
        codegen_processes(design->gate_processes);
        codegen_stimulus(design->stimulus);

        // combine signals + gates into .net, stim goes to .stim
        CodeGenResult result;
        result.net_content  = g_signals + g_gates;
        result.stim_content = g_stim;
        return result;
    }
};

#endif
