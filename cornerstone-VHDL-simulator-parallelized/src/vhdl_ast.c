/*
 * vhdl_ast.c — AST constructor and destructor implementations
 *
 * Each constructor allocates a node, fills in its fields, and returns it.
 * The Bison parser calls these from its semantic actions.
 *
 * Memory ownership rules:
 *   - String fields (char*) are owned by the node — the parser passes
 *     strdup'd copies, and the destructor frees them.
 *   - Child pointers are owned by the parent — freeing the parent
 *     recursively frees all children.
 */

#include <stdlib.h>
#include <string.h>
#include "vhdl_ast.h"

/* Safe strdup that handles NULL */
static char *safe_strdup(const char *s) {
    return s ? strdup(s) : NULL;
}

/* ── Expression constructors ──────────────────────────── */

VExpr *vexpr_ident(char *name, int line) {
    VExpr *e = calloc(1, sizeof(VExpr));
    e->kind = VEXPR_IDENT;
    e->value = name;   /* takes ownership from the lexer's strdup */
    e->line = line;
    return e;
}

VExpr *vexpr_literal(char val, int line) {
    VExpr *e = calloc(1, sizeof(VExpr));
    e->kind = VEXPR_LITERAL;
    char buf[2] = { val, '\0' };
    e->value = strdup(buf);
    e->line = line;
    return e;
}

VExpr *vexpr_unary(const char *op, VExpr *child, int line) {
    VExpr *e = calloc(1, sizeof(VExpr));
    e->kind = VEXPR_UNARY;
    e->value = safe_strdup(op);
    e->left = child;
    e->line = line;
    return e;
}

VExpr *vexpr_binary(const char *op, VExpr *left, VExpr *right, int line) {
    VExpr *e = calloc(1, sizeof(VExpr));
    e->kind = VEXPR_BINARY;
    e->value = safe_strdup(op);
    e->left = left;
    e->right = right;
    e->line = line;
    return e;
}

VExpr *vexpr_func_call(const char *func, VExpr *arg, int line) {
    VExpr *e = calloc(1, sizeof(VExpr));
    e->kind = VEXPR_FUNC_CALL;
    e->value = safe_strdup(func);
    e->left = arg;
    e->line = line;
    return e;
}

/* ── Identifier list (linked list of names) ───────────── */

VIdentList *vident_list_new(char *name) {
    VIdentList *n = calloc(1, sizeof(VIdentList));
    n->name = name;
    return n;
}

VIdentList *vident_list_append(VIdentList *list, char *name) {
    VIdentList *n = vident_list_new(name);
    if (!list) return n;
    /* walk to the end and append */
    VIdentList *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = n;
    return list;
}

/* ── Signal declarations ──────────────────────────────── */

VSignalDecl *vsignal_decl_new(VIdentList *names, char init, int line) {
    VSignalDecl *d = calloc(1, sizeof(VSignalDecl));
    d->names = names;
    d->init = init;
    d->line = line;
    return d;
}

VSignalDeclList *vsignal_decl_list_append(VSignalDeclList *list, VSignalDecl *decl) {
    VSignalDeclList *n = calloc(1, sizeof(VSignalDeclList));
    n->decl = decl;
    if (!list) return n;
    VSignalDeclList *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = n;
    return list;
}

/* ── Signal assignments ───────────────────────────────── */

VSignalAssign *vsignal_assign_new(char *target, VExpr *expr, int line) {
    VSignalAssign *a = calloc(1, sizeof(VSignalAssign));
    a->target = target;
    a->expr = expr;
    a->line = line;
    return a;
}

VAssignList *vassign_list_append(VAssignList *list, VSignalAssign *assign) {
    VAssignList *n = calloc(1, sizeof(VAssignList));
    n->assign = assign;
    if (!list) return n;
    VAssignList *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = n;
    return list;
}

/* ── If branches ──────────────────────────────────────── */

VIfBranch *vif_branch_new(VExpr *cond, VAssignList *assigns, int line) {
    VIfBranch *b = calloc(1, sizeof(VIfBranch));
    b->condition = cond;
    b->assigns = assigns;
    b->line = line;
    return b;
}

VIfBranchList *vif_branch_list_append(VIfBranchList *list, VIfBranch *branch) {
    VIfBranchList *n = calloc(1, sizeof(VIfBranchList));
    n->branch = branch;
    if (!list) return n;
    VIfBranchList *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = n;
    return list;
}

/* ── Concurrent assignments ───────────────────────────── */

VConcurrentAssign *vconc_assign_new(char *target, VExpr *expr, int line) {
    VConcurrentAssign *a = calloc(1, sizeof(VConcurrentAssign));
    a->target = target;
    a->expr = expr;
    a->line = line;
    return a;
}

VConcAssignList *vconc_assign_list_append(VConcAssignList *list, VConcurrentAssign *assign) {
    VConcAssignList *n = calloc(1, sizeof(VConcAssignList));
    n->assign = assign;
    if (!list) return n;
    VConcAssignList *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = n;
    return list;
}

/* ── Gate processes ───────────────────────────────────── */

VGateProcess *vgate_process_new(VIdentList *sens, VIfBranchList *branches,
                                VAssignList *direct, int line) {
    VGateProcess *p = calloc(1, sizeof(VGateProcess));
    p->sensitivity_list = sens;
    p->branches = branches;
    p->direct_assigns = direct;
    p->line = line;
    return p;
}

VGateProcList *vgate_proc_list_append(VGateProcList *list, VGateProcess *proc) {
    VGateProcList *n = calloc(1, sizeof(VGateProcList));
    n->proc = proc;
    if (!list) return n;
    VGateProcList *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = n;
    return list;
}

/* ── Stimulus ─────────────────────────────────────────── */

VStimulusStep *vstim_step_new(int time, VAssignList *assigns) {
    VStimulusStep *s = calloc(1, sizeof(VStimulusStep));
    s->time = time;
    s->assigns = assigns;
    return s;
}

VStimStepList *vstim_step_list_append(VStimStepList *list, VStimulusStep *step) {
    VStimStepList *n = calloc(1, sizeof(VStimStepList));
    n->step = step;
    if (!list) return n;
    VStimStepList *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = n;
    return list;
}

int vstim_step_list_last_time(VStimStepList *list) {
    if (!list) return 0;
    VStimStepList *cur = list;
    while (cur->next) cur = cur->next;
    return cur->step->time;
}

VStimulusProcess *vstim_process_new(VStimStepList *steps, int line) {
    VStimulusProcess *p = calloc(1, sizeof(VStimulusProcess));
    p->steps = steps;
    p->line = line;
    return p;
}

/* ── Architecture body helpers ────────────────────────── */

VArchBody *varch_body_new(void) {
    return calloc(1, sizeof(VArchBody));
}

VArchBody *varch_body_add_conc(VArchBody *body, VConcurrentAssign *assign) {
    body->conc = vconc_assign_list_append(body->conc, assign);
    return body;
}

VArchBody *varch_body_add_gate(VArchBody *body, VGateProcess *proc) {
    body->gates = vgate_proc_list_append(body->gates, proc);
    return body;
}

VArchBody *varch_body_add_stim(VArchBody *body, VStimulusProcess *stim) {
    body->stim = stim;
    return body;
}

/* ── Top-level design constructor ─────────────────────── */

VHDLDesign *vhdl_design_new(char *entity, char *arch,
                             VSignalDeclList *signals,
                             VArchBody *body) {
    VHDLDesign *d = calloc(1, sizeof(VHDLDesign));
    d->entity_name = entity;
    d->architecture_name = arch;
    d->signals = signals;
    if (body) {
        d->concurrent_assigns = body->conc;
        d->gate_processes = body->gates;
        d->stimulus = body->stim;
        free(body);  /* free the VArchBody wrapper, not its contents */
    }
    return d;
}

/* ── AST destructor (recursive) ───────────────────────── */

static void free_expr(VExpr *e) {
    if (!e) return;
    free(e->value);
    free_expr(e->left);
    free_expr(e->right);
    free(e);
}

static void free_ident_list(VIdentList *l) {
    while (l) {
        VIdentList *next = l->next;
        free(l->name);
        free(l);
        l = next;
    }
}

static void free_assign_list(VAssignList *l) {
    while (l) {
        VAssignList *next = l->next;
        free(l->assign->target);
        free_expr(l->assign->expr);
        free(l->assign);
        free(l);
        l = next;
    }
}

void vhdl_design_free(VHDLDesign *d) {
    if (!d) return;

    free(d->entity_name);
    free(d->architecture_name);

    /* free signal declarations */
    VSignalDeclList *sd = d->signals;
    while (sd) {
        VSignalDeclList *next = sd->next;
        free_ident_list(sd->decl->names);
        free(sd->decl);
        free(sd);
        sd = next;
    }

    /* free concurrent assignments */
    VConcAssignList *ca = d->concurrent_assigns;
    while (ca) {
        VConcAssignList *next = ca->next;
        free(ca->assign->target);
        free_expr(ca->assign->expr);
        free(ca->assign);
        free(ca);
        ca = next;
    }

    /* free gate processes */
    VGateProcList *gp = d->gate_processes;
    while (gp) {
        VGateProcList *next = gp->next;
        free_ident_list(gp->proc->sensitivity_list);
        VIfBranchList *bl = gp->proc->branches;
        while (bl) {
            VIfBranchList *bnext = bl->next;
            free_expr(bl->branch->condition);
            free_assign_list(bl->branch->assigns);
            free(bl->branch);
            free(bl);
            bl = bnext;
        }
        free_assign_list(gp->proc->direct_assigns);
        free(gp->proc);
        free(gp);
        gp = next;
    }

    /* free stimulus process */
    if (d->stimulus) {
        VStimStepList *sl = d->stimulus->steps;
        while (sl) {
            VStimStepList *next = sl->next;
            free_assign_list(sl->step->assigns);
            free(sl->step);
            free(sl);
            sl = next;
        }
        free(d->stimulus);
    }

    free(d);
}
