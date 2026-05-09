# Makefile for the VHDL Discrete Event Simulator
#
# Builds the simulator from C++ source files and Flex/Bison-generated
# parser code.  The VHDL parser is built in three steps:
#   1. Bison generates the parser (.tab.c/.tab.h) from the grammar
#   2. Flex generates the lexer (.c) using the token definitions from Bison
#   3. Both are compiled as C and linked with the C++ code

export OMP_WAIT_POLICY = active
export OMP_NUM_THREADS = $(shell nproc)
export OMP_PROC_BIND = true

CXX      = g++
CC       = gcc
CXXFLAGS = -std=c++17 -Wall -Wextra -O1 -fopenmp -Iinclude -Iinclude/vhdl -Ibuild/vhdl
CFLAGS   = -Wall -Wextra -O1

# ── C++ sources ──────────────────────────────────────────────────────
SRC = main.cpp \
      src/Signal.cpp \
      src/Simulator.cpp

OBJ    = $(SRC:.cpp=.o)
TARGET = simulator

# ── VHDL parser sources (Flex + Bison) ───────────────────────────────
VHDL_PARSER_Y = include/vhdl/vhdl_parser.y
VHDL_LEXER_L  = include/vhdl/vhdl_lexer.l
VHDL_AST_C    = src/vhdl_ast.c

# Generated files go into build/vhdl/ for easy cleanup
VHDL_BUILD_DIR    = build/vhdl
VHDL_PARSER_TAB_C = $(VHDL_BUILD_DIR)/vhdl_parser.tab.c
VHDL_PARSER_TAB_H = $(VHDL_BUILD_DIR)/vhdl_parser.tab.h
VHDL_LEXER_C      = $(VHDL_BUILD_DIR)/vhdl_lexer.c

# Object files
VHDL_PARSER_TAB_O = $(VHDL_BUILD_DIR)/vhdl_parser.tab.o
VHDL_LEXER_O      = $(VHDL_BUILD_DIR)/vhdl_lexer.o
VHDL_AST_O        = $(VHDL_BUILD_DIR)/vhdl_ast.o

VHDL_OBJ = $(VHDL_PARSER_TAB_O) $(VHDL_LEXER_O) $(VHDL_AST_O)

# ── Default test file paths (override on command line) ───────────────
STIM   = and_gate.stim
VCD    = output.vcd

# ── Build rules ──────────────────────────────────────────────────────
all: $(TARGET)

$(TARGET): $(OBJ) $(VHDL_OBJ)
	$(CXX) $(CXXFLAGS) -fopenmp -o $(TARGET) $(OBJ) $(VHDL_OBJ)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -MMD -MP -c $< -o $@

# ── VHDL parser build steps ─────────────────────────────────────────

$(VHDL_BUILD_DIR):
	mkdir -p $(VHDL_BUILD_DIR)

# Step 1: Bison generates parser .tab.c and .tab.h from the grammar
$(VHDL_PARSER_TAB_C) $(VHDL_PARSER_TAB_H): $(VHDL_PARSER_Y) | $(VHDL_BUILD_DIR)
	bison -d -o $(VHDL_PARSER_TAB_C) $(VHDL_PARSER_Y)

# Step 2: Flex generates lexer .c (needs .tab.h for token definitions)
$(VHDL_LEXER_C): $(VHDL_LEXER_L) $(VHDL_PARSER_TAB_H) | $(VHDL_BUILD_DIR)
	flex -o $(VHDL_LEXER_C) $(VHDL_LEXER_L)

# Step 3: Compile the generated C files and hand-written vhdl_ast.c
$(VHDL_PARSER_TAB_O): $(VHDL_PARSER_TAB_C)
	$(CC) $(CFLAGS) -Iinclude/vhdl -I$(VHDL_BUILD_DIR) -c $< -o $@

$(VHDL_LEXER_O): $(VHDL_LEXER_C)
	$(CC) $(CFLAGS) -Iinclude/vhdl -I$(VHDL_BUILD_DIR) -c $< -o $@

$(VHDL_AST_O): $(VHDL_AST_C) include/vhdl/vhdl_ast.h | $(VHDL_BUILD_DIR)
	$(CC) $(CFLAGS) -Iinclude/vhdl -c $< -o $@

# Build just the VHDL parser objects (useful for development)
vhdl-parser: $(VHDL_OBJ)

# ── Run targets ──────────────────────────────────────────────────────
run: all
	./$(TARGET) $(STIM) $(VCD)

# Usage: make sim STIM=my_circuit.stim VCD=my_waves.vcd
sim: all
	./$(TARGET) $(STIM) $(VCD)

# ── Clean ────────────────────────────────────────────────────────────
clean:
	rm -f $(OBJ) $(TARGET) main.d src/Signal.d src/Simulator.d generated/*.net generated/*.stim
	rm -rf $(VHDL_BUILD_DIR)

cleanall: clean
	rm -f *.vcd output/*.vcd  
	rm -rf ui_uploads ui_output

# ── Auto-generated dependency tracking ───────────────────────────────
-include $(OBJ:.o=.d)

.PHONY: all run sim clean cleanall vhdl-parser
