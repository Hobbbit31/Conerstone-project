-- =============================================================
-- Circuit  : 32 Parallel Independent Full Adders
-- File     : parallel_full_adders.vhd
--
-- WHAT THIS CIRCUIT DOES:
--   Contains 32 separate 1-bit full adders running in parallel.
--   Each adder computes:
--     Si    = Ai xor Bi xor Cini   (sum bit)
--     Couti = (Ai and Bi) or (Cini and (Ai xor Bi))  (carry out)
--   There are NO carry connections between adders — adder 0 and
--   adder 1 share no signals at all. All 32 are fully independent.
--
-- HOW EACH FULL ADDER IS BUILT (5 gates, 3 layers):
--   t_xori   = Ai  xor Bi        (Layer 0 — XOR gate)
--   Si       = t_xori xor Cini   (Layer 1 — XOR gate, depends on t_xori)
--   t_and1_i = Ai  and Bi        (Layer 0 — AND gate, independent)
--   t_and2_i = Cini and t_xori   (Layer 1 — AND gate, depends on t_xori)
--   Couti    = t_and1_i or t_and2_i  (Layer 2 — OR gate)
--
-- WHY THIS MATTERS FOR PARALLELISM:
--   32 adders x 5 gates = 160 gates total, across 3 layers.
--   Every layer has 32 or 64 processes running in parallel:
--     Layer 0: 64 processes (32 XOR + 32 AND, all independent)
--     Layer 1: 64 processes (32 XOR + 32 AND, all independent)
--     Layer 2: 32 processes (32 OR gates)
--   This shows SUSTAINED parallelism across multiple dependency levels,
--   not just a single burst. It also tests that the barrier between
--   layers works correctly — Layer 1 must not start before Layer 0 finishes.
--
-- DEPENDENCY GRAPH:
--   Layer 0: 64 gates (32 t_xor XORs + 32 t_and1 ANDs)
--   Layer 1: 64 gates (32 S XORs + 32 t_and2 ANDs)
--   Layer 2: 32 gates (32 Cout ORs)
--   Total  : 160 gates in 3 layers
--
-- SIGNALS:
--   A0..A31    : first operand inputs
--   B0..B31    : second operand inputs
--   Cin0..Cin31: carry inputs
--   S0..S31    : sum outputs
--   Cout0..Cout31 : carry outputs
--   t_xor0..t_xor31, t_and1_0..t_and1_31, t_and2_0..t_and2_31 : intermediates
--
-- STIMULUS — 4 test vectors (10 ns each):
--   t=0  : A=0, B=0, Cin=0  -> S=0, Cout=0  (0+0+0=0)
--   t=10 : A=1, B=0, Cin=0  -> S=1, Cout=0  (1+0+0=1)
--   t=20 : A=1, B=1, Cin=0  -> S=0, Cout=1  (1+1+0=10)
--   t=30 : A=1, B=1, Cin=1  -> S=1, Cout=1  (1+1+1=11)
--
-- HOW TO BENCHMARK:
--   OMP_NUM_THREADS=1 ./simulator test_vhdl/large/parallel_full_adders.vhd t1.vcd
--   OMP_NUM_THREADS=4 ./simulator test_vhdl/large/parallel_full_adders.vhd t4.vcd
--   diff t1.vcd t4.vcd   <-- must be empty (bit-identical output)
-- =============================================================

entity parallel_full_adders_tb is
end entity;

architecture rtl of parallel_full_adders_tb is
    signal A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16, A17, A18, A19, A20, A21, A22, A23, A24, A25, A26, A27, A28, A29, A30, A31 : std_logic := '0';
    signal B0, B1, B2, B3, B4, B5, B6, B7, B8, B9, B10, B11, B12, B13, B14, B15, B16, B17, B18, B19, B20, B21, B22, B23, B24, B25, B26, B27, B28, B29, B30, B31 : std_logic := '0';
    signal Cin0, Cin1, Cin2, Cin3, Cin4, Cin5, Cin6, Cin7, Cin8, Cin9, Cin10, Cin11, Cin12, Cin13, Cin14, Cin15, Cin16, Cin17, Cin18, Cin19, Cin20, Cin21, Cin22, Cin23, Cin24, Cin25, Cin26, Cin27, Cin28, Cin29, Cin30, Cin31 : std_logic := '0';
    signal S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15, S16, S17, S18, S19, S20, S21, S22, S23, S24, S25, S26, S27, S28, S29, S30, S31 : std_logic := '0';
    signal Cout0, Cout1, Cout2, Cout3, Cout4, Cout5, Cout6, Cout7, Cout8, Cout9, Cout10, Cout11, Cout12, Cout13, Cout14, Cout15, Cout16, Cout17, Cout18, Cout19, Cout20, Cout21, Cout22, Cout23, Cout24, Cout25, Cout26, Cout27, Cout28, Cout29, Cout30, Cout31 : std_logic := '0';
    signal t_xor0, t_xor1, t_xor2, t_xor3, t_xor4, t_xor5, t_xor6, t_xor7, t_xor8, t_xor9, t_xor10, t_xor11, t_xor12, t_xor13, t_xor14, t_xor15, t_xor16, t_xor17, t_xor18, t_xor19, t_xor20, t_xor21, t_xor22, t_xor23, t_xor24, t_xor25, t_xor26, t_xor27, t_xor28, t_xor29, t_xor30, t_xor31 : std_logic := '0';
    signal t_and1_0, t_and1_1, t_and1_2, t_and1_3, t_and1_4, t_and1_5, t_and1_6, t_and1_7, t_and1_8, t_and1_9, t_and1_10, t_and1_11, t_and1_12, t_and1_13, t_and1_14, t_and1_15, t_and1_16, t_and1_17, t_and1_18, t_and1_19, t_and1_20, t_and1_21, t_and1_22, t_and1_23, t_and1_24, t_and1_25, t_and1_26, t_and1_27, t_and1_28, t_and1_29, t_and1_30, t_and1_31 : std_logic := '0';
    signal t_and2_0, t_and2_1, t_and2_2, t_and2_3, t_and2_4, t_and2_5, t_and2_6, t_and2_7, t_and2_8, t_and2_9, t_and2_10, t_and2_11, t_and2_12, t_and2_13, t_and2_14, t_and2_15, t_and2_16, t_and2_17, t_and2_18, t_and2_19, t_and2_20, t_and2_21, t_and2_22, t_and2_23, t_and2_24, t_and2_25, t_and2_26, t_and2_27, t_and2_28, t_and2_29, t_and2_30, t_and2_31 : std_logic := '0';
begin
    t_xor0   <= A0 xor B0;
    S0       <= t_xor0 xor Cin0;
    t_and1_0 <= A0 and B0;
    t_and2_0 <= Cin0 and t_xor0;
    Cout0    <= t_and1_0 or t_and2_0;
    t_xor1   <= A1 xor B1;
    S1       <= t_xor1 xor Cin1;
    t_and1_1 <= A1 and B1;
    t_and2_1 <= Cin1 and t_xor1;
    Cout1    <= t_and1_1 or t_and2_1;
    t_xor2   <= A2 xor B2;
    S2       <= t_xor2 xor Cin2;
    t_and1_2 <= A2 and B2;
    t_and2_2 <= Cin2 and t_xor2;
    Cout2    <= t_and1_2 or t_and2_2;
    t_xor3   <= A3 xor B3;
    S3       <= t_xor3 xor Cin3;
    t_and1_3 <= A3 and B3;
    t_and2_3 <= Cin3 and t_xor3;
    Cout3    <= t_and1_3 or t_and2_3;
    t_xor4   <= A4 xor B4;
    S4       <= t_xor4 xor Cin4;
    t_and1_4 <= A4 and B4;
    t_and2_4 <= Cin4 and t_xor4;
    Cout4    <= t_and1_4 or t_and2_4;
    t_xor5   <= A5 xor B5;
    S5       <= t_xor5 xor Cin5;
    t_and1_5 <= A5 and B5;
    t_and2_5 <= Cin5 and t_xor5;
    Cout5    <= t_and1_5 or t_and2_5;
    t_xor6   <= A6 xor B6;
    S6       <= t_xor6 xor Cin6;
    t_and1_6 <= A6 and B6;
    t_and2_6 <= Cin6 and t_xor6;
    Cout6    <= t_and1_6 or t_and2_6;
    t_xor7   <= A7 xor B7;
    S7       <= t_xor7 xor Cin7;
    t_and1_7 <= A7 and B7;
    t_and2_7 <= Cin7 and t_xor7;
    Cout7    <= t_and1_7 or t_and2_7;
    t_xor8   <= A8 xor B8;
    S8       <= t_xor8 xor Cin8;
    t_and1_8 <= A8 and B8;
    t_and2_8 <= Cin8 and t_xor8;
    Cout8    <= t_and1_8 or t_and2_8;
    t_xor9   <= A9 xor B9;
    S9       <= t_xor9 xor Cin9;
    t_and1_9 <= A9 and B9;
    t_and2_9 <= Cin9 and t_xor9;
    Cout9    <= t_and1_9 or t_and2_9;
    t_xor10   <= A10 xor B10;
    S10       <= t_xor10 xor Cin10;
    t_and1_10 <= A10 and B10;
    t_and2_10 <= Cin10 and t_xor10;
    Cout10    <= t_and1_10 or t_and2_10;
    t_xor11   <= A11 xor B11;
    S11       <= t_xor11 xor Cin11;
    t_and1_11 <= A11 and B11;
    t_and2_11 <= Cin11 and t_xor11;
    Cout11    <= t_and1_11 or t_and2_11;
    t_xor12   <= A12 xor B12;
    S12       <= t_xor12 xor Cin12;
    t_and1_12 <= A12 and B12;
    t_and2_12 <= Cin12 and t_xor12;
    Cout12    <= t_and1_12 or t_and2_12;
    t_xor13   <= A13 xor B13;
    S13       <= t_xor13 xor Cin13;
    t_and1_13 <= A13 and B13;
    t_and2_13 <= Cin13 and t_xor13;
    Cout13    <= t_and1_13 or t_and2_13;
    t_xor14   <= A14 xor B14;
    S14       <= t_xor14 xor Cin14;
    t_and1_14 <= A14 and B14;
    t_and2_14 <= Cin14 and t_xor14;
    Cout14    <= t_and1_14 or t_and2_14;
    t_xor15   <= A15 xor B15;
    S15       <= t_xor15 xor Cin15;
    t_and1_15 <= A15 and B15;
    t_and2_15 <= Cin15 and t_xor15;
    Cout15    <= t_and1_15 or t_and2_15;
    t_xor16   <= A16 xor B16;
    S16       <= t_xor16 xor Cin16;
    t_and1_16 <= A16 and B16;
    t_and2_16 <= Cin16 and t_xor16;
    Cout16    <= t_and1_16 or t_and2_16;
    t_xor17   <= A17 xor B17;
    S17       <= t_xor17 xor Cin17;
    t_and1_17 <= A17 and B17;
    t_and2_17 <= Cin17 and t_xor17;
    Cout17    <= t_and1_17 or t_and2_17;
    t_xor18   <= A18 xor B18;
    S18       <= t_xor18 xor Cin18;
    t_and1_18 <= A18 and B18;
    t_and2_18 <= Cin18 and t_xor18;
    Cout18    <= t_and1_18 or t_and2_18;
    t_xor19   <= A19 xor B19;
    S19       <= t_xor19 xor Cin19;
    t_and1_19 <= A19 and B19;
    t_and2_19 <= Cin19 and t_xor19;
    Cout19    <= t_and1_19 or t_and2_19;
    t_xor20   <= A20 xor B20;
    S20       <= t_xor20 xor Cin20;
    t_and1_20 <= A20 and B20;
    t_and2_20 <= Cin20 and t_xor20;
    Cout20    <= t_and1_20 or t_and2_20;
    t_xor21   <= A21 xor B21;
    S21       <= t_xor21 xor Cin21;
    t_and1_21 <= A21 and B21;
    t_and2_21 <= Cin21 and t_xor21;
    Cout21    <= t_and1_21 or t_and2_21;
    t_xor22   <= A22 xor B22;
    S22       <= t_xor22 xor Cin22;
    t_and1_22 <= A22 and B22;
    t_and2_22 <= Cin22 and t_xor22;
    Cout22    <= t_and1_22 or t_and2_22;
    t_xor23   <= A23 xor B23;
    S23       <= t_xor23 xor Cin23;
    t_and1_23 <= A23 and B23;
    t_and2_23 <= Cin23 and t_xor23;
    Cout23    <= t_and1_23 or t_and2_23;
    t_xor24   <= A24 xor B24;
    S24       <= t_xor24 xor Cin24;
    t_and1_24 <= A24 and B24;
    t_and2_24 <= Cin24 and t_xor24;
    Cout24    <= t_and1_24 or t_and2_24;
    t_xor25   <= A25 xor B25;
    S25       <= t_xor25 xor Cin25;
    t_and1_25 <= A25 and B25;
    t_and2_25 <= Cin25 and t_xor25;
    Cout25    <= t_and1_25 or t_and2_25;
    t_xor26   <= A26 xor B26;
    S26       <= t_xor26 xor Cin26;
    t_and1_26 <= A26 and B26;
    t_and2_26 <= Cin26 and t_xor26;
    Cout26    <= t_and1_26 or t_and2_26;
    t_xor27   <= A27 xor B27;
    S27       <= t_xor27 xor Cin27;
    t_and1_27 <= A27 and B27;
    t_and2_27 <= Cin27 and t_xor27;
    Cout27    <= t_and1_27 or t_and2_27;
    t_xor28   <= A28 xor B28;
    S28       <= t_xor28 xor Cin28;
    t_and1_28 <= A28 and B28;
    t_and2_28 <= Cin28 and t_xor28;
    Cout28    <= t_and1_28 or t_and2_28;
    t_xor29   <= A29 xor B29;
    S29       <= t_xor29 xor Cin29;
    t_and1_29 <= A29 and B29;
    t_and2_29 <= Cin29 and t_xor29;
    Cout29    <= t_and1_29 or t_and2_29;
    t_xor30   <= A30 xor B30;
    S30       <= t_xor30 xor Cin30;
    t_and1_30 <= A30 and B30;
    t_and2_30 <= Cin30 and t_xor30;
    Cout30    <= t_and1_30 or t_and2_30;
    t_xor31   <= A31 xor B31;
    S31       <= t_xor31 xor Cin31;
    t_and1_31 <= A31 and B31;
    t_and2_31 <= Cin31 and t_xor31;
    Cout31    <= t_and1_31 or t_and2_31;

    process begin
        A0 <= '0'; A1 <= '0'; A2 <= '0'; A3 <= '0'; A4 <= '0'; A5 <= '0'; A6 <= '0'; A7 <= '0'; A8 <= '0'; A9 <= '0'; A10 <= '0'; A11 <= '0'; A12 <= '0'; A13 <= '0'; A14 <= '0'; A15 <= '0'; A16 <= '0'; A17 <= '0'; A18 <= '0'; A19 <= '0'; A20 <= '0'; A21 <= '0'; A22 <= '0'; A23 <= '0'; A24 <= '0'; A25 <= '0'; A26 <= '0'; A27 <= '0'; A28 <= '0'; A29 <= '0'; A30 <= '0'; A31 <= '0'; B0 <= '0'; B1 <= '0'; B2 <= '0'; B3 <= '0'; B4 <= '0'; B5 <= '0'; B6 <= '0'; B7 <= '0'; B8 <= '0'; B9 <= '0'; B10 <= '0'; B11 <= '0'; B12 <= '0'; B13 <= '0'; B14 <= '0'; B15 <= '0'; B16 <= '0'; B17 <= '0'; B18 <= '0'; B19 <= '0'; B20 <= '0'; B21 <= '0'; B22 <= '0'; B23 <= '0'; B24 <= '0'; B25 <= '0'; B26 <= '0'; B27 <= '0'; B28 <= '0'; B29 <= '0'; B30 <= '0'; B31 <= '0'; Cin0 <= '0'; Cin1 <= '0'; Cin2 <= '0'; Cin3 <= '0'; Cin4 <= '0'; Cin5 <= '0'; Cin6 <= '0'; Cin7 <= '0'; Cin8 <= '0'; Cin9 <= '0'; Cin10 <= '0'; Cin11 <= '0'; Cin12 <= '0'; Cin13 <= '0'; Cin14 <= '0'; Cin15 <= '0'; Cin16 <= '0'; Cin17 <= '0'; Cin18 <= '0'; Cin19 <= '0'; Cin20 <= '0'; Cin21 <= '0'; Cin22 <= '0'; Cin23 <= '0'; Cin24 <= '0'; Cin25 <= '0'; Cin26 <= '0'; Cin27 <= '0'; Cin28 <= '0'; Cin29 <= '0'; Cin30 <= '0'; Cin31 <= '0';
        wait for 10 ns;
        A0 <= '1'; A1 <= '1'; A2 <= '1'; A3 <= '1'; A4 <= '1'; A5 <= '1'; A6 <= '1'; A7 <= '1'; A8 <= '1'; A9 <= '1'; A10 <= '1'; A11 <= '1'; A12 <= '1'; A13 <= '1'; A14 <= '1'; A15 <= '1'; A16 <= '1'; A17 <= '1'; A18 <= '1'; A19 <= '1'; A20 <= '1'; A21 <= '1'; A22 <= '1'; A23 <= '1'; A24 <= '1'; A25 <= '1'; A26 <= '1'; A27 <= '1'; A28 <= '1'; A29 <= '1'; A30 <= '1'; A31 <= '1';
        wait for 10 ns;
        B0 <= '1'; B1 <= '1'; B2 <= '1'; B3 <= '1'; B4 <= '1'; B5 <= '1'; B6 <= '1'; B7 <= '1'; B8 <= '1'; B9 <= '1'; B10 <= '1'; B11 <= '1'; B12 <= '1'; B13 <= '1'; B14 <= '1'; B15 <= '1'; B16 <= '1'; B17 <= '1'; B18 <= '1'; B19 <= '1'; B20 <= '1'; B21 <= '1'; B22 <= '1'; B23 <= '1'; B24 <= '1'; B25 <= '1'; B26 <= '1'; B27 <= '1'; B28 <= '1'; B29 <= '1'; B30 <= '1'; B31 <= '1';
        wait for 10 ns;
        Cin0 <= '1'; Cin1 <= '1'; Cin2 <= '1'; Cin3 <= '1'; Cin4 <= '1'; Cin5 <= '1'; Cin6 <= '1'; Cin7 <= '1'; Cin8 <= '1'; Cin9 <= '1'; Cin10 <= '1'; Cin11 <= '1'; Cin12 <= '1'; Cin13 <= '1'; Cin14 <= '1'; Cin15 <= '1'; Cin16 <= '1'; Cin17 <= '1'; Cin18 <= '1'; Cin19 <= '1'; Cin20 <= '1'; Cin21 <= '1'; Cin22 <= '1'; Cin23 <= '1'; Cin24 <= '1'; Cin25 <= '1'; Cin26 <= '1'; Cin27 <= '1'; Cin28 <= '1'; Cin29 <= '1'; Cin30 <= '1'; Cin31 <= '1';
        wait for 10 ns;
        wait;
    end process;
end architecture;
