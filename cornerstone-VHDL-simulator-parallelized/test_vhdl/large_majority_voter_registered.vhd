-- =============================================================
-- Circuit  : Registered Majority Voter with Parity, MUX, and SR Error Latch
-- File     : majority_voter_registered.vhd
--
-- WHAT THIS CIRCUIT DOES:
--   This is a complex test circuit that exercises every supported gate
--   type and every process pattern available in this VHDL simulator subset.
--
--   It takes three single-bit voter inputs (A, B, C) and computes two
--   combinational results:
--
--     Majority Vote (MAJ):
--       Output is 1 when 2 or more of the 3 inputs are 1.
--       Implemented as: (A AND B) OR (B AND C) OR (A AND C)
--       Uses three AND gates for the pair products, then two OR gates
--       to combine them (the codegen flattens the 3-way OR into a temp
--       signal _t0 = t_ab OR t_bc, then MAJ_comb = _t0 OR t_ac).
--
--     Odd Parity (PAR):
--       Output is 1 when an odd number of inputs are 1.
--       Implemented as a chain: t_xor = A XOR B, then PAR_comb = t_xor XOR C.
--       Two XOR gates in series.
--
--   Both results are stored in D flip-flops (MAJ_reg, PAR_reg) that
--   capture the combinational value on every rising edge of CLK.
--
--   A 2:1 MUX (MUX_OUT) selects which registered-path combinational
--   signal to expose: SEL=1 shows MAJ_comb, SEL=0 shows PAR_comb.
--   This is a combinational MUX (not registered), so MUX_OUT updates
--   immediately whenever SEL, MAJ_comb, or PAR_comb change.
--
--   An SR latch (ERR) acts as a sticky error flag: S_err=1 sets it to 1
--   and it holds that value even after S_err returns to 0. R_err=1
--   clears it back to 0.
--
--   Three additional signals (t_nand, t_nor, t_xnor) compute NAND, NOR,
--   and XNOR of A and B. They serve as the Q_NOT label signals for the
--   two DFFs and also demonstrate that all 9 combinational gate types
--   are exercised in a single file.
--
-- GATE TYPES USED (all 9 combinational + both sequential):
--   AND   -> t_ab, t_bc, t_ac
--   OR    -> MAJ_comb
--   XOR   -> t_xor, PAR_comb
--   NAND  -> t_nand
--   NOR   -> t_nor
--   XNOR  -> t_xnor
--   DFF   -> MAJ_reg (rising-edge flip-flop)
--   DFF   -> PAR_reg (rising-edge flip-flop)
--   MUX   -> MUX_OUT (2:1 combinational mux)
--   SR    -> ERR     (NOR-based set-reset latch)
--
-- PROCESS PATTERNS USED (all 4 supported by the codegen):
--   1. Concurrent signal assignment  -- combinational logic outside any process
--   2. DFF  process (rising_edge)    -- process(CLK) if rising_edge(CLK) then Q<=D
--   3. MUX  process (if/else)        -- process(...) if SEL='1' then Y<=A else Y<=B
--   4. SR   process (if/elsif)       -- process(S,R) if S='1' ... elsif R='1' ...
--
-- SIGNAL FLOW:
--
--   A --+-- AND --> t_ab --+
--   B --+                  +-- OR --> _t0 --+
--   B --+-- AND --> t_bc --+                +-- OR --> MAJ_comb --> DFF(CLK) --> MAJ_reg
--   C --+                                   |
--   A --+-- AND --> t_ac -------------------+
--   C --+
--
--   A --+-- XOR --> t_xor --+
--   B --+                   +-- XOR --> PAR_comb --> DFF(CLK) --> PAR_reg
--   C  ----------------------+
--
--   MAJ_comb --+
--   PAR_comb --+-- MUX(SEL) --> MUX_OUT
--   SEL -------+
--
--   S_err --+
--   R_err --+-- SR Latch --> ERR
--
-- EXPECTED OUTPUT AT EACH TIME STEP:
--   t=0  : all inputs 0; t_nand=1, t_nor=1, t_xnor=1 (NAND/NOR/XNOR of 0,0 = 1)
--   t=5  : CLK rises; MAJ_reg=0, PAR_reg captures 0 (was init 1, now 0)
--   t=10 : A=1,B=1,C=0; MAJ_comb=1, PAR_comb=0, t_nand=0, t_nor=0
--   t=15 : CLK rises; MAJ_reg=1, MAJ_reg_n=0 (complement)
--   t=20 : A=1,B=0,C=1, SEL=1; MAJ_comb=1 (via t_ac=1), MUX_OUT=1
--          PAR_comb glitches 0->1->0 across two delta cycles — this is
--          correct IEEE 1076 behavior: t_xor updates before C's effect
--          on PAR_comb is re-evaluated in the next delta.
--   t=25 : CLK rises; no change (MAJ still 1, PAR still 0)
--   t=30 : A=1,B=0,C=0, SEL=0; MAJ_comb=0, PAR_comb=1, MUX_OUT->1
--          MUX_OUT briefly goes 0 (SEL changes first) then 1 (PAR_comb arrives)
--   t=35 : CLK rises; MAJ_reg=0, MAJ_reg_n=1, PAR_reg=1, PAR_reg_n=0
--   t=40 : S_err=1; SR latch sets ERR=1 immediately (no clock)
--   t=45 : S_err=0; ERR holds 1 (latch memory — no change)
--   t=50 : R_err=1; SR latch clears ERR=0
-- =============================================================

entity majority_voter_registered_tb is
end entity;

architecture rtl of majority_voter_registered_tb is
    signal A, B, C   : std_logic := '0';
    signal CLK       : std_logic := '0';
    signal SEL       : std_logic := '0';
    signal S_err     : std_logic := '0';
    signal R_err     : std_logic := '0';
    signal t_ab, t_bc, t_ac : std_logic := '0';
    signal MAJ_comb          : std_logic := '0';
    signal t_xor    : std_logic := '0';
    signal PAR_comb : std_logic := '0';
    signal t_nand : std_logic := '0';
    signal t_nor  : std_logic := '0';
    signal t_xnor : std_logic := '0';
    signal MAJ_reg, MAJ_reg_n : std_logic := '0';
    signal PAR_reg, PAR_reg_n : std_logic := '1';
    signal MUX_OUT : std_logic := '0';
    signal ERR     : std_logic := '0';
begin
    t_ab <= A and B;
    t_bc <= B and C;
    t_ac <= A and C;
    MAJ_comb <= t_ab or t_bc or t_ac;

    t_xor    <= A xor B;
    PAR_comb <= t_xor xor C;

    t_nand <= A nand B;
    t_nor  <= A nor B;
    t_xnor <= A xnor B;

    process(CLK) begin
        if rising_edge(CLK) then
            MAJ_reg   <= MAJ_comb;
            MAJ_reg_n <= t_nand;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            PAR_reg   <= PAR_comb;
            PAR_reg_n <= t_xnor;
        end if;
    end process;

    process(SEL, MAJ_comb, PAR_comb) begin
        if SEL='1' then
            MUX_OUT <= MAJ_comb;
        else
            MUX_OUT <= PAR_comb;
        end if;
    end process;

    process(S_err, R_err) begin
        if S_err='1' then
            ERR <= '1';
        elsif R_err='1' then
            ERR <= '0';
        end if;
    end process;

    process begin
        A <= '0'; B <= '0'; C <= '0'; CLK <= '0'; SEL <= '0'; S_err <= '0'; R_err <= '0';
        wait for 5 ns;
        CLK <= '1';
        wait for 5 ns;
        A <= '1'; B <= '1'; C <= '0'; CLK <= '0';
        wait for 5 ns;
        CLK <= '1';
        wait for 5 ns;
        A <= '1'; B <= '0'; C <= '1'; CLK <= '0'; SEL <= '1';
        wait for 5 ns;
        CLK <= '1';
        wait for 5 ns;
        A <= '1'; B <= '0'; C <= '0'; CLK <= '0'; SEL <= '0';
        wait for 5 ns;
        CLK <= '1';
        wait for 5 ns;
        CLK <= '0'; S_err <= '1';
        wait for 5 ns;
        S_err <= '0';
        wait for 5 ns;
        R_err <= '1';
        wait for 5 ns;
        wait;
    end process;
end architecture;
