/* vhdl_stub.c — Stub for VHDL parser when bison/flex are not available.
 * Only the .net/.stim flow works with this stub.
 */

#include <stdio.h>
#include "vhdl_ast.h"

FILE *yyin = NULL;
VHDLDesign *vhdl_root = NULL;

int yyparse(void) {
    fprintf(stderr, "Error: VHDL parser not built (bison/flex required).\n");
    fprintf(stderr, "Use .net + .stim files instead.\n");
    return 1;
}

void vhdl_design_free(VHDLDesign *d) {
    (void)d;
}
