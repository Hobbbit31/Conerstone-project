/*
 * vhdl_ast.h — C AST node definitions for the VHDL subset parser
 *
 * These structs hold the parsed representation of a .vhd file.
 * They are built by Bison semantic actions (in vhdl_parser.y)
 * and consumed by the code generator (VHDLCodeGen.hpp).
 *
 * We use C (not C++) for the AST because Bison's %union can't hold
 * C++ objects with constructors.  The tradeoff is manual memory
 * management, but it keeps the parser simple and portable.
 *
 * AST structure overview:
 *
 *   VHDLDesign (top level)
 *     ├── entity_name, architecture_name
 *     ├── VSignalDeclList → signal declarations
 *     ├── VConcAssignList → concurrent assignments (outside processes)
 *     ├── VGateProcList   → process blocks (DFF, MUX, SR, combinational)
 *     └── VStimulusProcess → test stimulus (optional)
 *
 *   VExpr (expression tree, used in assignments and conditions)
 *     - IDENT:     leaf node, signal name
 *     - LITERAL:   leaf node, '0' or '1'
 *     - UNARY:     "not X" — one child
 *     - BINARY:    "A and B" — two children
 *     - FUNC_CALL: "rising_edge(clk)" — one child
 */

#ifndef VHDL_AST_H
#define VHDL_AST_H

#ifdef __cplusplus
extern "C" {
#endif

/* ── Forward declarations ──────────────────────────────── */

typedef struct VExpr VExpr;
typedef struct VIdentList VIdentList;
typedef struct VSignalDecl VSignalDecl;
typedef struct VSignalDeclList VSignalDeclList;
typedef struct VSignalAssign VSignalAssign;
typedef struct VAssignList VAssignList;
typedef struct VIfBranch VIfBranch;
typedef struct VIfBranchList VIfBranchList;
typedef struct VConcurrentAssign VConcurrentAssign;
typedef struct VConcAssignList VConcAssignList;
typedef struct VGateProcess VGateProcess;
typedef struct VGateProcList VGateProcList;
typedef struct VStimulusStep VStimulusStep;
typedef struct VStimStepList VStimStepList;
typedef struct VStimulusProcess VStimulusProcess;
typedef struct VArchBody VArchBody;
typedef struct VHDLDesign VHDLDesign;

/* ── Expression tree ───────────────────────────────────── */

typedef enum {
    VEXPR_IDENT,       /* signal name: "A", "out1"                     */
    VEXPR_LITERAL,     /* character literal: '0' or '1'                */
    VEXPR_UNARY,       /* unary operator: not X                        */
    VEXPR_BINARY,      /* binary operator: A and B, A or B, etc.       */
    VEXPR_FUNC_CALL    /* function call: rising_edge(clk)              */
} VExprKind;

struct VExpr {
    VExprKind kind;
    char *value;       /* ident name, "0"/"1", operator, or func name  */
    VExpr *left;       /* first child (or only child for unary/func)   */
    VExpr *right;      /* second child (binary only)                   */
    int line;          /* source line number for error messages         */
};

/* ── Identifier list (signal names, sensitivity lists) ── */

struct VIdentList {
    char *name;
    VIdentList *next;
};

/* ── Signal declaration ────────────────────────────────── */
/*
 * Example: signal A, B : std_logic := '0';
 *   names = [A, B]
 *   init  = '0'
 */

struct VSignalDecl {
    VIdentList *names;  /* one or more signal names                    */
    char init;          /* '0', '1', or '\0' if no initializer         */
    int line;
};

struct VSignalDeclList {
    VSignalDecl *decl;
    VSignalDeclList *next;
};

/* ── Signal assignment (used inside process bodies) ───── */

struct VSignalAssign {
    char *target;       /* left-hand side signal name                  */
    VExpr *expr;        /* right-hand side expression                  */
    int line;
};

struct VAssignList {
    VSignalAssign *assign;
    VAssignList *next;
};

/* ── If branch (one arm of if/elsif/else) ─────────────── */

struct VIfBranch {
    VExpr *condition;       /* NULL for the else branch                */
    VAssignList *assigns;   /* assignments in this branch              */
    int line;
};

struct VIfBranchList {
    VIfBranch *branch;
    VIfBranchList *next;
};

/* ── Concurrent assignment (outside any process) ──────── */

struct VConcurrentAssign {
    char *target;
    VExpr *expr;
    int line;
};

struct VConcAssignList {
    VConcurrentAssign *assign;
    VConcAssignList *next;
};

/* ── Gate process (process with sensitivity list) ─────── */

struct VGateProcess {
    VIdentList *sensitivity_list;
    VIfBranchList *branches;        /* if/elsif/else branches          */
    VAssignList *direct_assigns;    /* combinational: no if, just assigns */
    int line;
};

struct VGateProcList {
    VGateProcess *proc;
    VGateProcList *next;
};

/* ── Stimulus step (one time point in the test bench) ─── */

struct VStimulusStep {
    int time;                   /* absolute time in nanoseconds        */
    VAssignList *assigns;       /* signal assignments at this time     */
};

struct VStimStepList {
    VStimulusStep *step;
    VStimStepList *next;
};

/* ── Stimulus process (the complete test stimulus) ────── */

struct VStimulusProcess {
    VStimStepList *steps;
    int line;
};

/* ── Architecture body (intermediate node during parsing) */

struct VArchBody {
    VConcAssignList *conc;      /* concurrent assignments              */
    VGateProcList *gates;       /* gate processes                      */
    VStimulusProcess *stim;     /* stimulus process (NULL if none)     */
};

/* ── Top-level design (the root of the AST) ───────────── */

struct VHDLDesign {
    char *entity_name;
    char *architecture_name;
    VSignalDeclList *signals;
    VConcAssignList *concurrent_assigns;
    VGateProcList *gate_processes;
    VStimulusProcess *stimulus;     /* NULL if no stimulus              */
};

/* ── Constructor functions ─────────────────────────────── */

/* Expressions */
VExpr *vexpr_ident(char *name, int line);
VExpr *vexpr_literal(char val, int line);
VExpr *vexpr_unary(const char *op, VExpr *child, int line);
VExpr *vexpr_binary(const char *op, VExpr *left, VExpr *right, int line);
VExpr *vexpr_func_call(const char *func, VExpr *arg, int line);

/* Identifier lists */
VIdentList *vident_list_new(char *name);
VIdentList *vident_list_append(VIdentList *list, char *name);

/* Signal declarations */
VSignalDecl *vsignal_decl_new(VIdentList *names, char init, int line);
VSignalDeclList *vsignal_decl_list_append(VSignalDeclList *list, VSignalDecl *decl);

/* Signal assignments */
VSignalAssign *vsignal_assign_new(char *target, VExpr *expr, int line);
VAssignList *vassign_list_append(VAssignList *list, VSignalAssign *assign);

/* If branches */
VIfBranch *vif_branch_new(VExpr *cond, VAssignList *assigns, int line);
VIfBranchList *vif_branch_list_append(VIfBranchList *list, VIfBranch *branch);

/* Concurrent assignments */
VConcurrentAssign *vconc_assign_new(char *target, VExpr *expr, int line);
VConcAssignList *vconc_assign_list_append(VConcAssignList *list, VConcurrentAssign *assign);

/* Gate processes */
VGateProcess *vgate_process_new(VIdentList *sens, VIfBranchList *branches,
                                VAssignList *direct, int line);
VGateProcList *vgate_proc_list_append(VGateProcList *list, VGateProcess *proc);

/* Stimulus */
VStimulusStep *vstim_step_new(int time, VAssignList *assigns);
VStimStepList *vstim_step_list_append(VStimStepList *list, VStimulusStep *step);
VStimulusProcess *vstim_process_new(VStimStepList *steps, int line);

/* Architecture body helpers */
VArchBody *varch_body_new(void);
VArchBody *varch_body_add_conc(VArchBody *body, VConcurrentAssign *assign);
VArchBody *varch_body_add_gate(VArchBody *body, VGateProcess *proc);
VArchBody *varch_body_add_stim(VArchBody *body, VStimulusProcess *stim);

/* Top-level design */
VHDLDesign *vhdl_design_new(char *entity, char *arch,
                             VSignalDeclList *signals,
                             VArchBody *body);

/* Get the time of the last stimulus step (for cumulative time tracking) */
int vstim_step_list_last_time(VStimStepList *list);

/* Free the entire AST recursively */
void vhdl_design_free(VHDLDesign *design);

#ifdef __cplusplus
}
#endif

#endif /* VHDL_AST_H */
