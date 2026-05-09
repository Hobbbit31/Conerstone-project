-- =============================================================
-- Circuit  : Wide Mixed Gate Test
-- File     : wide_mixed_gates.vhd
--
-- WHAT THIS CIRCUIT DOES:
--   Contains 128 combinational gates covering ALL 8 gate types
--   (16 of each), plus 16 D flip-flops that register selected outputs.
--   Total: 128 combinational gates + 16 DFFs = 144 gates.
--
-- GATE TYPES AND WHAT EACH GROUP COMPUTES:
--   AND  gates (16): Y_andi  = A_andi  and B_andi   (both inputs must be 1)
--   OR   gates (16): Y_ori   = A_ori   or  B_ori    (either input is 1)
--   XOR  gates (16): Y_xori  = A_xori  xor B_xori   (inputs differ)
--   NAND gates (16): Y_nandi = A_nandi nand B_nandi  (NOT of AND)
--   NOR  gates (16): Y_nori  = A_nori  nor  B_nori   (NOT of OR)
--   XNOR gates (16): Y_xnori = A_xnori xnor B_xnori  (inputs are equal)
--   NOT  gates (16): Y_noti  = not A_noti            (single input invert)
--   BUF  gates (16): Y_bufi  = A_bufi               (single input buffer)
--   DFF       (16):  REGi captures Y_andi on rising CLK edge
--                    REGi_n is the complement output of the DFF
--
-- WHY THIS MATTERS FOR PARALLELISM:
--   All 128 combinational gates are independent of each other.
--   They all sit in Layer 0 and run in parallel.
--   The 16 DFFs form Layer 1 (they depend on CLK and Y_and outputs).
--   This tests that ALL gate implementations are thread-safe
--   when executed in parallel — no gate should have hidden shared state.
--
-- DEPENDENCY GRAPH:
--   Layer 0: 128 gates (all AND/OR/XOR/NAND/NOR/XNOR/NOT/BUF)
--   Layer 1: 16 DFF gates (depend on CLK and Y_and outputs)
--   Total  : 144 gates in 2 layers
--
-- SIGNALS:
--   CLK           : shared clock for all DFFs
--   A_<type>0..15 : first input to each 2-input gate group
--   B_<type>0..15 : second input to each 2-input gate group (AND/OR/XOR/NAND/NOR/XNOR)
--   A_not0..15    : input to each NOT gate
--   A_buf0..15    : input to each BUF gate
--   Y_<type>0..15 : output of each gate group
--   REG0..15      : DFF Q outputs (registered Y_and)
--   REG0_n..15_n  : DFF Q_NOT outputs (complement of REG)
--
-- STIMULUS — 3 test vectors + clock edges:
--   t=0  : all A=0, B=0, CLK=0
--          AND=0, OR=0, XOR=0, NAND=1, NOR=1, XNOR=1, NOT=1, BUF=0
--   t=10 : CLK=1  -> DFFs register AND outputs (all 0)
--   t=20 : A=1, B=0, CLK=0
--          AND=0, OR=1, XOR=1, NAND=1, NOR=0, XNOR=0, NOT=0, BUF=1
--   t=30 : CLK=1  -> DFFs register AND outputs (still 0)
--   t=40 : A=1, B=1, CLK=0
--          AND=1, OR=1, XOR=0, NAND=0, NOR=0, XNOR=1, NOT=0, BUF=1
--   t=50 : CLK=1  -> DFFs register AND outputs (now 1, REG flips)
--
-- HOW TO BENCHMARK:
--   OMP_NUM_THREADS=1 ./simulator test_vhdl/large/wide_mixed_gates.vhd t1.vcd
--   OMP_NUM_THREADS=4 ./simulator test_vhdl/large/wide_mixed_gates.vhd t4.vcd
--   diff t1.vcd t4.vcd   <-- must be empty (bit-identical output)
-- =============================================================

entity wide_mixed_gates_tb is
end entity;

architecture rtl of wide_mixed_gates_tb is
    signal CLK : std_logic := '0';
    signal A_and0, A_and1, A_and2, A_and3, A_and4, A_and5, A_and6, A_and7, A_and8, A_and9, A_and10, A_and11, A_and12, A_and13, A_and14, A_and15 : std_logic := '0';
    signal B_and0, B_and1, B_and2, B_and3, B_and4, B_and5, B_and6, B_and7, B_and8, B_and9, B_and10, B_and11, B_and12, B_and13, B_and14, B_and15 : std_logic := '0';
    signal Y_and0, Y_and1, Y_and2, Y_and3, Y_and4, Y_and5, Y_and6, Y_and7, Y_and8, Y_and9, Y_and10, Y_and11, Y_and12, Y_and13, Y_and14, Y_and15 : std_logic := '0';
    signal A_or0, A_or1, A_or2, A_or3, A_or4, A_or5, A_or6, A_or7, A_or8, A_or9, A_or10, A_or11, A_or12, A_or13, A_or14, A_or15 : std_logic := '0';
    signal B_or0, B_or1, B_or2, B_or3, B_or4, B_or5, B_or6, B_or7, B_or8, B_or9, B_or10, B_or11, B_or12, B_or13, B_or14, B_or15 : std_logic := '0';
    signal Y_or0, Y_or1, Y_or2, Y_or3, Y_or4, Y_or5, Y_or6, Y_or7, Y_or8, Y_or9, Y_or10, Y_or11, Y_or12, Y_or13, Y_or14, Y_or15 : std_logic := '0';
    signal A_xor0, A_xor1, A_xor2, A_xor3, A_xor4, A_xor5, A_xor6, A_xor7, A_xor8, A_xor9, A_xor10, A_xor11, A_xor12, A_xor13, A_xor14, A_xor15 : std_logic := '0';
    signal B_xor0, B_xor1, B_xor2, B_xor3, B_xor4, B_xor5, B_xor6, B_xor7, B_xor8, B_xor9, B_xor10, B_xor11, B_xor12, B_xor13, B_xor14, B_xor15 : std_logic := '0';
    signal Y_xor0, Y_xor1, Y_xor2, Y_xor3, Y_xor4, Y_xor5, Y_xor6, Y_xor7, Y_xor8, Y_xor9, Y_xor10, Y_xor11, Y_xor12, Y_xor13, Y_xor14, Y_xor15 : std_logic := '0';
    signal A_nand0, A_nand1, A_nand2, A_nand3, A_nand4, A_nand5, A_nand6, A_nand7, A_nand8, A_nand9, A_nand10, A_nand11, A_nand12, A_nand13, A_nand14, A_nand15 : std_logic := '0';
    signal B_nand0, B_nand1, B_nand2, B_nand3, B_nand4, B_nand5, B_nand6, B_nand7, B_nand8, B_nand9, B_nand10, B_nand11, B_nand12, B_nand13, B_nand14, B_nand15 : std_logic := '0';
    signal Y_nand0, Y_nand1, Y_nand2, Y_nand3, Y_nand4, Y_nand5, Y_nand6, Y_nand7, Y_nand8, Y_nand9, Y_nand10, Y_nand11, Y_nand12, Y_nand13, Y_nand14, Y_nand15 : std_logic := '0';
    signal A_nor0, A_nor1, A_nor2, A_nor3, A_nor4, A_nor5, A_nor6, A_nor7, A_nor8, A_nor9, A_nor10, A_nor11, A_nor12, A_nor13, A_nor14, A_nor15 : std_logic := '0';
    signal B_nor0, B_nor1, B_nor2, B_nor3, B_nor4, B_nor5, B_nor6, B_nor7, B_nor8, B_nor9, B_nor10, B_nor11, B_nor12, B_nor13, B_nor14, B_nor15 : std_logic := '0';
    signal Y_nor0, Y_nor1, Y_nor2, Y_nor3, Y_nor4, Y_nor5, Y_nor6, Y_nor7, Y_nor8, Y_nor9, Y_nor10, Y_nor11, Y_nor12, Y_nor13, Y_nor14, Y_nor15 : std_logic := '0';
    signal A_xnor0, A_xnor1, A_xnor2, A_xnor3, A_xnor4, A_xnor5, A_xnor6, A_xnor7, A_xnor8, A_xnor9, A_xnor10, A_xnor11, A_xnor12, A_xnor13, A_xnor14, A_xnor15 : std_logic := '0';
    signal B_xnor0, B_xnor1, B_xnor2, B_xnor3, B_xnor4, B_xnor5, B_xnor6, B_xnor7, B_xnor8, B_xnor9, B_xnor10, B_xnor11, B_xnor12, B_xnor13, B_xnor14, B_xnor15 : std_logic := '0';
    signal Y_xnor0, Y_xnor1, Y_xnor2, Y_xnor3, Y_xnor4, Y_xnor5, Y_xnor6, Y_xnor7, Y_xnor8, Y_xnor9, Y_xnor10, Y_xnor11, Y_xnor12, Y_xnor13, Y_xnor14, Y_xnor15 : std_logic := '0';
    signal A_not0, A_not1, A_not2, A_not3, A_not4, A_not5, A_not6, A_not7, A_not8, A_not9, A_not10, A_not11, A_not12, A_not13, A_not14, A_not15 : std_logic := '0';
    signal Y_not0, Y_not1, Y_not2, Y_not3, Y_not4, Y_not5, Y_not6, Y_not7, Y_not8, Y_not9, Y_not10, Y_not11, Y_not12, Y_not13, Y_not14, Y_not15 : std_logic := '0';
    signal A_buf0, A_buf1, A_buf2, A_buf3, A_buf4, A_buf5, A_buf6, A_buf7, A_buf8, A_buf9, A_buf10, A_buf11, A_buf12, A_buf13, A_buf14, A_buf15 : std_logic := '0';
    signal Y_buf0, Y_buf1, Y_buf2, Y_buf3, Y_buf4, Y_buf5, Y_buf6, Y_buf7, Y_buf8, Y_buf9, Y_buf10, Y_buf11, Y_buf12, Y_buf13, Y_buf14, Y_buf15 : std_logic := '0';
    signal REG0, REG0_n : std_logic := '0';
    signal REG1, REG1_n : std_logic := '0';
    signal REG2, REG2_n : std_logic := '0';
    signal REG3, REG3_n : std_logic := '0';
    signal REG4, REG4_n : std_logic := '0';
    signal REG5, REG5_n : std_logic := '0';
    signal REG6, REG6_n : std_logic := '0';
    signal REG7, REG7_n : std_logic := '0';
    signal REG8, REG8_n : std_logic := '0';
    signal REG9, REG9_n : std_logic := '0';
    signal REG10, REG10_n : std_logic := '0';
    signal REG11, REG11_n : std_logic := '0';
    signal REG12, REG12_n : std_logic := '0';
    signal REG13, REG13_n : std_logic := '0';
    signal REG14, REG14_n : std_logic := '0';
    signal REG15, REG15_n : std_logic := '0';
begin
    Y_and0 <= A_and0 and B_and0;
    Y_and1 <= A_and1 and B_and1;
    Y_and2 <= A_and2 and B_and2;
    Y_and3 <= A_and3 and B_and3;
    Y_and4 <= A_and4 and B_and4;
    Y_and5 <= A_and5 and B_and5;
    Y_and6 <= A_and6 and B_and6;
    Y_and7 <= A_and7 and B_and7;
    Y_and8 <= A_and8 and B_and8;
    Y_and9 <= A_and9 and B_and9;
    Y_and10 <= A_and10 and B_and10;
    Y_and11 <= A_and11 and B_and11;
    Y_and12 <= A_and12 and B_and12;
    Y_and13 <= A_and13 and B_and13;
    Y_and14 <= A_and14 and B_and14;
    Y_and15 <= A_and15 and B_and15;
    Y_or0 <= A_or0 or B_or0;
    Y_or1 <= A_or1 or B_or1;
    Y_or2 <= A_or2 or B_or2;
    Y_or3 <= A_or3 or B_or3;
    Y_or4 <= A_or4 or B_or4;
    Y_or5 <= A_or5 or B_or5;
    Y_or6 <= A_or6 or B_or6;
    Y_or7 <= A_or7 or B_or7;
    Y_or8 <= A_or8 or B_or8;
    Y_or9 <= A_or9 or B_or9;
    Y_or10 <= A_or10 or B_or10;
    Y_or11 <= A_or11 or B_or11;
    Y_or12 <= A_or12 or B_or12;
    Y_or13 <= A_or13 or B_or13;
    Y_or14 <= A_or14 or B_or14;
    Y_or15 <= A_or15 or B_or15;
    Y_xor0 <= A_xor0 xor B_xor0;
    Y_xor1 <= A_xor1 xor B_xor1;
    Y_xor2 <= A_xor2 xor B_xor2;
    Y_xor3 <= A_xor3 xor B_xor3;
    Y_xor4 <= A_xor4 xor B_xor4;
    Y_xor5 <= A_xor5 xor B_xor5;
    Y_xor6 <= A_xor6 xor B_xor6;
    Y_xor7 <= A_xor7 xor B_xor7;
    Y_xor8 <= A_xor8 xor B_xor8;
    Y_xor9 <= A_xor9 xor B_xor9;
    Y_xor10 <= A_xor10 xor B_xor10;
    Y_xor11 <= A_xor11 xor B_xor11;
    Y_xor12 <= A_xor12 xor B_xor12;
    Y_xor13 <= A_xor13 xor B_xor13;
    Y_xor14 <= A_xor14 xor B_xor14;
    Y_xor15 <= A_xor15 xor B_xor15;
    Y_nand0 <= A_nand0 nand B_nand0;
    Y_nand1 <= A_nand1 nand B_nand1;
    Y_nand2 <= A_nand2 nand B_nand2;
    Y_nand3 <= A_nand3 nand B_nand3;
    Y_nand4 <= A_nand4 nand B_nand4;
    Y_nand5 <= A_nand5 nand B_nand5;
    Y_nand6 <= A_nand6 nand B_nand6;
    Y_nand7 <= A_nand7 nand B_nand7;
    Y_nand8 <= A_nand8 nand B_nand8;
    Y_nand9 <= A_nand9 nand B_nand9;
    Y_nand10 <= A_nand10 nand B_nand10;
    Y_nand11 <= A_nand11 nand B_nand11;
    Y_nand12 <= A_nand12 nand B_nand12;
    Y_nand13 <= A_nand13 nand B_nand13;
    Y_nand14 <= A_nand14 nand B_nand14;
    Y_nand15 <= A_nand15 nand B_nand15;
    Y_nor0 <= A_nor0 nor B_nor0;
    Y_nor1 <= A_nor1 nor B_nor1;
    Y_nor2 <= A_nor2 nor B_nor2;
    Y_nor3 <= A_nor3 nor B_nor3;
    Y_nor4 <= A_nor4 nor B_nor4;
    Y_nor5 <= A_nor5 nor B_nor5;
    Y_nor6 <= A_nor6 nor B_nor6;
    Y_nor7 <= A_nor7 nor B_nor7;
    Y_nor8 <= A_nor8 nor B_nor8;
    Y_nor9 <= A_nor9 nor B_nor9;
    Y_nor10 <= A_nor10 nor B_nor10;
    Y_nor11 <= A_nor11 nor B_nor11;
    Y_nor12 <= A_nor12 nor B_nor12;
    Y_nor13 <= A_nor13 nor B_nor13;
    Y_nor14 <= A_nor14 nor B_nor14;
    Y_nor15 <= A_nor15 nor B_nor15;
    Y_xnor0 <= A_xnor0 xnor B_xnor0;
    Y_xnor1 <= A_xnor1 xnor B_xnor1;
    Y_xnor2 <= A_xnor2 xnor B_xnor2;
    Y_xnor3 <= A_xnor3 xnor B_xnor3;
    Y_xnor4 <= A_xnor4 xnor B_xnor4;
    Y_xnor5 <= A_xnor5 xnor B_xnor5;
    Y_xnor6 <= A_xnor6 xnor B_xnor6;
    Y_xnor7 <= A_xnor7 xnor B_xnor7;
    Y_xnor8 <= A_xnor8 xnor B_xnor8;
    Y_xnor9 <= A_xnor9 xnor B_xnor9;
    Y_xnor10 <= A_xnor10 xnor B_xnor10;
    Y_xnor11 <= A_xnor11 xnor B_xnor11;
    Y_xnor12 <= A_xnor12 xnor B_xnor12;
    Y_xnor13 <= A_xnor13 xnor B_xnor13;
    Y_xnor14 <= A_xnor14 xnor B_xnor14;
    Y_xnor15 <= A_xnor15 xnor B_xnor15;
    Y_not0 <= not A_not0;
    Y_buf0 <= A_buf0;
    Y_not1 <= not A_not1;
    Y_buf1 <= A_buf1;
    Y_not2 <= not A_not2;
    Y_buf2 <= A_buf2;
    Y_not3 <= not A_not3;
    Y_buf3 <= A_buf3;
    Y_not4 <= not A_not4;
    Y_buf4 <= A_buf4;
    Y_not5 <= not A_not5;
    Y_buf5 <= A_buf5;
    Y_not6 <= not A_not6;
    Y_buf6 <= A_buf6;
    Y_not7 <= not A_not7;
    Y_buf7 <= A_buf7;
    Y_not8 <= not A_not8;
    Y_buf8 <= A_buf8;
    Y_not9 <= not A_not9;
    Y_buf9 <= A_buf9;
    Y_not10 <= not A_not10;
    Y_buf10 <= A_buf10;
    Y_not11 <= not A_not11;
    Y_buf11 <= A_buf11;
    Y_not12 <= not A_not12;
    Y_buf12 <= A_buf12;
    Y_not13 <= not A_not13;
    Y_buf13 <= A_buf13;
    Y_not14 <= not A_not14;
    Y_buf14 <= A_buf14;
    Y_not15 <= not A_not15;
    Y_buf15 <= A_buf15;

    process(CLK) begin
        if rising_edge(CLK) then
            REG0   <= Y_and0;
            REG0_n <= Y_nand0;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG1   <= Y_and1;
            REG1_n <= Y_nand1;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG2   <= Y_and2;
            REG2_n <= Y_nand2;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG3   <= Y_and3;
            REG3_n <= Y_nand3;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG4   <= Y_and4;
            REG4_n <= Y_nand4;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG5   <= Y_and5;
            REG5_n <= Y_nand5;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG6   <= Y_and6;
            REG6_n <= Y_nand6;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG7   <= Y_and7;
            REG7_n <= Y_nand7;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG8   <= Y_and8;
            REG8_n <= Y_nand8;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG9   <= Y_and9;
            REG9_n <= Y_nand9;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG10   <= Y_and10;
            REG10_n <= Y_nand10;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG11   <= Y_and11;
            REG11_n <= Y_nand11;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG12   <= Y_and12;
            REG12_n <= Y_nand12;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG13   <= Y_and13;
            REG13_n <= Y_nand13;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG14   <= Y_and14;
            REG14_n <= Y_nand14;
        end if;
    end process;
    process(CLK) begin
        if rising_edge(CLK) then
            REG15   <= Y_and15;
            REG15_n <= Y_nand15;
        end if;
    end process;

    process begin
        A_and0 <= '0'; A_and1 <= '0'; A_and2 <= '0'; A_and3 <= '0'; A_and4 <= '0'; A_and5 <= '0'; A_and6 <= '0'; A_and7 <= '0'; A_and8 <= '0'; A_and9 <= '0'; A_and10 <= '0'; A_and11 <= '0'; A_and12 <= '0'; A_and13 <= '0'; A_and14 <= '0'; A_and15 <= '0'; A_or0 <= '0'; A_or1 <= '0'; A_or2 <= '0'; A_or3 <= '0'; A_or4 <= '0'; A_or5 <= '0'; A_or6 <= '0'; A_or7 <= '0'; A_or8 <= '0'; A_or9 <= '0'; A_or10 <= '0'; A_or11 <= '0'; A_or12 <= '0'; A_or13 <= '0'; A_or14 <= '0'; A_or15 <= '0'; A_xor0 <= '0'; A_xor1 <= '0'; A_xor2 <= '0'; A_xor3 <= '0'; A_xor4 <= '0'; A_xor5 <= '0'; A_xor6 <= '0'; A_xor7 <= '0'; A_xor8 <= '0'; A_xor9 <= '0'; A_xor10 <= '0'; A_xor11 <= '0'; A_xor12 <= '0'; A_xor13 <= '0'; A_xor14 <= '0'; A_xor15 <= '0'; A_nand0 <= '0'; A_nand1 <= '0'; A_nand2 <= '0'; A_nand3 <= '0'; A_nand4 <= '0'; A_nand5 <= '0'; A_nand6 <= '0'; A_nand7 <= '0'; A_nand8 <= '0'; A_nand9 <= '0'; A_nand10 <= '0'; A_nand11 <= '0'; A_nand12 <= '0'; A_nand13 <= '0'; A_nand14 <= '0'; A_nand15 <= '0'; A_nor0 <= '0'; A_nor1 <= '0'; A_nor2 <= '0'; A_nor3 <= '0'; A_nor4 <= '0'; A_nor5 <= '0'; A_nor6 <= '0'; A_nor7 <= '0'; A_nor8 <= '0'; A_nor9 <= '0'; A_nor10 <= '0'; A_nor11 <= '0'; A_nor12 <= '0'; A_nor13 <= '0'; A_nor14 <= '0'; A_nor15 <= '0'; A_xnor0 <= '0'; A_xnor1 <= '0'; A_xnor2 <= '0'; A_xnor3 <= '0'; A_xnor4 <= '0'; A_xnor5 <= '0'; A_xnor6 <= '0'; A_xnor7 <= '0'; A_xnor8 <= '0'; A_xnor9 <= '0'; A_xnor10 <= '0'; A_xnor11 <= '0'; A_xnor12 <= '0'; A_xnor13 <= '0'; A_xnor14 <= '0'; A_xnor15 <= '0'; A_not0 <= '0'; A_not1 <= '0'; A_not2 <= '0'; A_not3 <= '0'; A_not4 <= '0'; A_not5 <= '0'; A_not6 <= '0'; A_not7 <= '0'; A_not8 <= '0'; A_not9 <= '0'; A_not10 <= '0'; A_not11 <= '0'; A_not12 <= '0'; A_not13 <= '0'; A_not14 <= '0'; A_not15 <= '0'; A_buf0 <= '0'; A_buf1 <= '0'; A_buf2 <= '0'; A_buf3 <= '0'; A_buf4 <= '0'; A_buf5 <= '0'; A_buf6 <= '0'; A_buf7 <= '0'; A_buf8 <= '0'; A_buf9 <= '0'; A_buf10 <= '0'; A_buf11 <= '0'; A_buf12 <= '0'; A_buf13 <= '0'; A_buf14 <= '0'; A_buf15 <= '0'; B_and0 <= '0'; B_and1 <= '0'; B_and2 <= '0'; B_and3 <= '0'; B_and4 <= '0'; B_and5 <= '0'; B_and6 <= '0'; B_and7 <= '0'; B_and8 <= '0'; B_and9 <= '0'; B_and10 <= '0'; B_and11 <= '0'; B_and12 <= '0'; B_and13 <= '0'; B_and14 <= '0'; B_and15 <= '0'; B_or0 <= '0'; B_or1 <= '0'; B_or2 <= '0'; B_or3 <= '0'; B_or4 <= '0'; B_or5 <= '0'; B_or6 <= '0'; B_or7 <= '0'; B_or8 <= '0'; B_or9 <= '0'; B_or10 <= '0'; B_or11 <= '0'; B_or12 <= '0'; B_or13 <= '0'; B_or14 <= '0'; B_or15 <= '0'; B_xor0 <= '0'; B_xor1 <= '0'; B_xor2 <= '0'; B_xor3 <= '0'; B_xor4 <= '0'; B_xor5 <= '0'; B_xor6 <= '0'; B_xor7 <= '0'; B_xor8 <= '0'; B_xor9 <= '0'; B_xor10 <= '0'; B_xor11 <= '0'; B_xor12 <= '0'; B_xor13 <= '0'; B_xor14 <= '0'; B_xor15 <= '0'; B_nand0 <= '0'; B_nand1 <= '0'; B_nand2 <= '0'; B_nand3 <= '0'; B_nand4 <= '0'; B_nand5 <= '0'; B_nand6 <= '0'; B_nand7 <= '0'; B_nand8 <= '0'; B_nand9 <= '0'; B_nand10 <= '0'; B_nand11 <= '0'; B_nand12 <= '0'; B_nand13 <= '0'; B_nand14 <= '0'; B_nand15 <= '0'; B_nor0 <= '0'; B_nor1 <= '0'; B_nor2 <= '0'; B_nor3 <= '0'; B_nor4 <= '0'; B_nor5 <= '0'; B_nor6 <= '0'; B_nor7 <= '0'; B_nor8 <= '0'; B_nor9 <= '0'; B_nor10 <= '0'; B_nor11 <= '0'; B_nor12 <= '0'; B_nor13 <= '0'; B_nor14 <= '0'; B_nor15 <= '0'; B_xnor0 <= '0'; B_xnor1 <= '0'; B_xnor2 <= '0'; B_xnor3 <= '0'; B_xnor4 <= '0'; B_xnor5 <= '0'; B_xnor6 <= '0'; B_xnor7 <= '0'; B_xnor8 <= '0'; B_xnor9 <= '0'; B_xnor10 <= '0'; B_xnor11 <= '0'; B_xnor12 <= '0'; B_xnor13 <= '0'; B_xnor14 <= '0'; B_xnor15 <= '0'; CLK <= '0';
        wait for 10 ns;
        CLK <= '1';
        wait for 10 ns;
        A_and0 <= '1'; A_and1 <= '1'; A_and2 <= '1'; A_and3 <= '1'; A_and4 <= '1'; A_and5 <= '1'; A_and6 <= '1'; A_and7 <= '1'; A_and8 <= '1'; A_and9 <= '1'; A_and10 <= '1'; A_and11 <= '1'; A_and12 <= '1'; A_and13 <= '1'; A_and14 <= '1'; A_and15 <= '1'; A_or0 <= '1'; A_or1 <= '1'; A_or2 <= '1'; A_or3 <= '1'; A_or4 <= '1'; A_or5 <= '1'; A_or6 <= '1'; A_or7 <= '1'; A_or8 <= '1'; A_or9 <= '1'; A_or10 <= '1'; A_or11 <= '1'; A_or12 <= '1'; A_or13 <= '1'; A_or14 <= '1'; A_or15 <= '1'; A_xor0 <= '1'; A_xor1 <= '1'; A_xor2 <= '1'; A_xor3 <= '1'; A_xor4 <= '1'; A_xor5 <= '1'; A_xor6 <= '1'; A_xor7 <= '1'; A_xor8 <= '1'; A_xor9 <= '1'; A_xor10 <= '1'; A_xor11 <= '1'; A_xor12 <= '1'; A_xor13 <= '1'; A_xor14 <= '1'; A_xor15 <= '1'; A_nand0 <= '1'; A_nand1 <= '1'; A_nand2 <= '1'; A_nand3 <= '1'; A_nand4 <= '1'; A_nand5 <= '1'; A_nand6 <= '1'; A_nand7 <= '1'; A_nand8 <= '1'; A_nand9 <= '1'; A_nand10 <= '1'; A_nand11 <= '1'; A_nand12 <= '1'; A_nand13 <= '1'; A_nand14 <= '1'; A_nand15 <= '1'; A_nor0 <= '1'; A_nor1 <= '1'; A_nor2 <= '1'; A_nor3 <= '1'; A_nor4 <= '1'; A_nor5 <= '1'; A_nor6 <= '1'; A_nor7 <= '1'; A_nor8 <= '1'; A_nor9 <= '1'; A_nor10 <= '1'; A_nor11 <= '1'; A_nor12 <= '1'; A_nor13 <= '1'; A_nor14 <= '1'; A_nor15 <= '1'; A_xnor0 <= '1'; A_xnor1 <= '1'; A_xnor2 <= '1'; A_xnor3 <= '1'; A_xnor4 <= '1'; A_xnor5 <= '1'; A_xnor6 <= '1'; A_xnor7 <= '1'; A_xnor8 <= '1'; A_xnor9 <= '1'; A_xnor10 <= '1'; A_xnor11 <= '1'; A_xnor12 <= '1'; A_xnor13 <= '1'; A_xnor14 <= '1'; A_xnor15 <= '1'; A_not0 <= '1'; A_not1 <= '1'; A_not2 <= '1'; A_not3 <= '1'; A_not4 <= '1'; A_not5 <= '1'; A_not6 <= '1'; A_not7 <= '1'; A_not8 <= '1'; A_not9 <= '1'; A_not10 <= '1'; A_not11 <= '1'; A_not12 <= '1'; A_not13 <= '1'; A_not14 <= '1'; A_not15 <= '1'; A_buf0 <= '1'; A_buf1 <= '1'; A_buf2 <= '1'; A_buf3 <= '1'; A_buf4 <= '1'; A_buf5 <= '1'; A_buf6 <= '1'; A_buf7 <= '1'; A_buf8 <= '1'; A_buf9 <= '1'; A_buf10 <= '1'; A_buf11 <= '1'; A_buf12 <= '1'; A_buf13 <= '1'; A_buf14 <= '1'; A_buf15 <= '1'; CLK <= '0';
        wait for 10 ns;
        CLK <= '1';
        wait for 10 ns;
        B_and0 <= '1'; B_and1 <= '1'; B_and2 <= '1'; B_and3 <= '1'; B_and4 <= '1'; B_and5 <= '1'; B_and6 <= '1'; B_and7 <= '1'; B_and8 <= '1'; B_and9 <= '1'; B_and10 <= '1'; B_and11 <= '1'; B_and12 <= '1'; B_and13 <= '1'; B_and14 <= '1'; B_and15 <= '1'; B_or0 <= '1'; B_or1 <= '1'; B_or2 <= '1'; B_or3 <= '1'; B_or4 <= '1'; B_or5 <= '1'; B_or6 <= '1'; B_or7 <= '1'; B_or8 <= '1'; B_or9 <= '1'; B_or10 <= '1'; B_or11 <= '1'; B_or12 <= '1'; B_or13 <= '1'; B_or14 <= '1'; B_or15 <= '1'; B_xor0 <= '1'; B_xor1 <= '1'; B_xor2 <= '1'; B_xor3 <= '1'; B_xor4 <= '1'; B_xor5 <= '1'; B_xor6 <= '1'; B_xor7 <= '1'; B_xor8 <= '1'; B_xor9 <= '1'; B_xor10 <= '1'; B_xor11 <= '1'; B_xor12 <= '1'; B_xor13 <= '1'; B_xor14 <= '1'; B_xor15 <= '1'; B_nand0 <= '1'; B_nand1 <= '1'; B_nand2 <= '1'; B_nand3 <= '1'; B_nand4 <= '1'; B_nand5 <= '1'; B_nand6 <= '1'; B_nand7 <= '1'; B_nand8 <= '1'; B_nand9 <= '1'; B_nand10 <= '1'; B_nand11 <= '1'; B_nand12 <= '1'; B_nand13 <= '1'; B_nand14 <= '1'; B_nand15 <= '1'; B_nor0 <= '1'; B_nor1 <= '1'; B_nor2 <= '1'; B_nor3 <= '1'; B_nor4 <= '1'; B_nor5 <= '1'; B_nor6 <= '1'; B_nor7 <= '1'; B_nor8 <= '1'; B_nor9 <= '1'; B_nor10 <= '1'; B_nor11 <= '1'; B_nor12 <= '1'; B_nor13 <= '1'; B_nor14 <= '1'; B_nor15 <= '1'; B_xnor0 <= '1'; B_xnor1 <= '1'; B_xnor2 <= '1'; B_xnor3 <= '1'; B_xnor4 <= '1'; B_xnor5 <= '1'; B_xnor6 <= '1'; B_xnor7 <= '1'; B_xnor8 <= '1'; B_xnor9 <= '1'; B_xnor10 <= '1'; B_xnor11 <= '1'; B_xnor12 <= '1'; B_xnor13 <= '1'; B_xnor14 <= '1'; B_xnor15 <= '1'; CLK <= '0';
        wait for 10 ns;
        CLK <= '1';
        wait for 10 ns;
        wait;
    end process;
end architecture;
