-- large_alu_8bit.vhd
-- 8-bit ALU testbench: tests AND, OR, XOR, NAND, NOR, XNOR, NOT on all 8 bits
-- simultaneously. Each bit pair (A0/B0 .. A7/B7) drives 6 gate operations.
-- Total: 8 bits x 7 ops = 56 concurrent gate processes + 1 stimulus process.
-- All gate processes are in Layer 0 (fully independent) — maximum parallelism.

entity large_alu_8bit_tb is
end large_alu_8bit_tb;

architecture sim of large_alu_8bit_tb is

    -- 8-bit input bus A
    signal A0, A1, A2, A3, A4, A5, A6, A7 : std_logic := '0';
    -- 8-bit input bus B
    signal B0, B1, B2, B3, B4, B5, B6, B7 : std_logic := '0';

    -- AND outputs
    signal AND0, AND1, AND2, AND3, AND4, AND5, AND6, AND7 : std_logic := '0';
    -- OR outputs
    signal OR0, OR1, OR2, OR3, OR4, OR5, OR6, OR7 : std_logic := '0';
    -- XOR outputs
    signal XOR0, XOR1, XOR2, XOR3, XOR4, XOR5, XOR6, XOR7 : std_logic := '0';
    -- NAND outputs
    signal NAND0, NAND1, NAND2, NAND3, NAND4, NAND5, NAND6, NAND7 : std_logic := '0';
    -- NOR outputs
    signal NOR0, NOR1, NOR2, NOR3, NOR4, NOR5, NOR6, NOR7 : std_logic := '0';
    -- XNOR outputs
    signal XNOR0, XNOR1, XNOR2, XNOR3, XNOR4, XNOR5, XNOR6, XNOR7 : std_logic := '0';
    -- NOT outputs (on A bus)
    signal NOTA0, NOTA1, NOTA2, NOTA3, NOTA4, NOTA5, NOTA6, NOTA7 : std_logic := '0';

begin

    -- AND operations (Layer 0 — independent)
    AND0 <= A0 and B0;
    AND1 <= A1 and B1;
    AND2 <= A2 and B2;
    AND3 <= A3 and B3;
    AND4 <= A4 and B4;
    AND5 <= A5 and B5;
    AND6 <= A6 and B6;
    AND7 <= A7 and B7;

    -- OR operations (Layer 0 — independent)
    OR0 <= A0 or B0;
    OR1 <= A1 or B1;
    OR2 <= A2 or B2;
    OR3 <= A3 or B3;
    OR4 <= A4 or B4;
    OR5 <= A5 or B5;
    OR6 <= A6 or B6;
    OR7 <= A7 or B7;

    -- XOR operations (Layer 0 — independent)
    XOR0 <= A0 xor B0;
    XOR1 <= A1 xor B1;
    XOR2 <= A2 xor B2;
    XOR3 <= A3 xor B3;
    XOR4 <= A4 xor B4;
    XOR5 <= A5 xor B5;
    XOR6 <= A6 xor B6;
    XOR7 <= A7 xor B7;

    -- NAND operations (Layer 0 — independent)
    NAND0 <= A0 nand B0;
    NAND1 <= A1 nand B1;
    NAND2 <= A2 nand B2;
    NAND3 <= A3 nand B3;
    NAND4 <= A4 nand B4;
    NAND5 <= A5 nand B5;
    NAND6 <= A6 nand B6;
    NAND7 <= A7 nand B7;

    -- NOR operations (Layer 0 — independent)
    NOR0 <= A0 nor B0;
    NOR1 <= A1 nor B1;
    NOR2 <= A2 nor B2;
    NOR3 <= A3 nor B3;
    NOR4 <= A4 nor B4;
    NOR5 <= A5 nor B5;
    NOR6 <= A6 nor B6;
    NOR7 <= A7 nor B7;

    -- XNOR operations (Layer 0 — independent)
    XNOR0 <= A0 xnor B0;
    XNOR1 <= A1 xnor B1;
    XNOR2 <= A2 xnor B2;
    XNOR3 <= A3 xnor B3;
    XNOR4 <= A4 xnor B4;
    XNOR5 <= A5 xnor B5;
    XNOR6 <= A6 xnor B6;
    XNOR7 <= A7 xnor B7;

    -- NOT on A bus (Layer 0 — independent)
    NOTA0 <= not A0;
    NOTA1 <= not A1;
    NOTA2 <= not A2;
    NOTA3 <= not A3;
    NOTA4 <= not A4;
    NOTA5 <= not A5;
    NOTA6 <= not A6;
    NOTA7 <= not A7;

    -- Stimulus: cycle through all 4 input combinations per bit pair
    process begin
        -- t=0: A=00000000 B=00000000
        A0 <= '0'; A1 <= '0'; A2 <= '0'; A3 <= '0';
        A4 <= '0'; A5 <= '0'; A6 <= '0'; A7 <= '0';
        B0 <= '0'; B1 <= '0'; B2 <= '0'; B3 <= '0';
        B4 <= '0'; B5 <= '0'; B6 <= '0'; B7 <= '0';
        wait for 10 ns;

        -- t=10: A=11111111 B=00000000
        A0 <= '1'; A1 <= '1'; A2 <= '1'; A3 <= '1';
        A4 <= '1'; A5 <= '1'; A6 <= '1'; A7 <= '1';
        B0 <= '0'; B1 <= '0'; B2 <= '0'; B3 <= '0';
        B4 <= '0'; B5 <= '0'; B6 <= '0'; B7 <= '0';
        wait for 10 ns;

        -- t=20: A=00000000 B=11111111
        A0 <= '0'; A1 <= '0'; A2 <= '0'; A3 <= '0';
        A4 <= '0'; A5 <= '0'; A6 <= '0'; A7 <= '0';
        B0 <= '1'; B1 <= '1'; B2 <= '1'; B3 <= '1';
        B4 <= '1'; B5 <= '1'; B6 <= '1'; B7 <= '1';
        wait for 10 ns;

        -- t=30: A=11111111 B=11111111
        A0 <= '1'; A1 <= '1'; A2 <= '1'; A3 <= '1';
        A4 <= '1'; A5 <= '1'; A6 <= '1'; A7 <= '1';
        B0 <= '1'; B1 <= '1'; B2 <= '1'; B3 <= '1';
        B4 <= '1'; B5 <= '1'; B6 <= '1'; B7 <= '1';
        wait for 10 ns;

        -- t=40: A=10101010 B=01010101 (alternating)
        A0 <= '1'; A1 <= '0'; A2 <= '1'; A3 <= '0';
        A4 <= '1'; A5 <= '0'; A6 <= '1'; A7 <= '0';
        B0 <= '0'; B1 <= '1'; B2 <= '0'; B3 <= '1';
        B4 <= '0'; B5 <= '1'; B6 <= '0'; B7 <= '1';
        wait for 10 ns;

        -- t=50: A=01010101 B=10101010 (flipped alternating)
        A0 <= '0'; A1 <= '1'; A2 <= '0'; A3 <= '1';
        A4 <= '0'; A5 <= '1'; A6 <= '0'; A7 <= '1';
        B0 <= '1'; B1 <= '0'; B2 <= '1'; B3 <= '0';
        B4 <= '1'; B5 <= '0'; B6 <= '1'; B7 <= '0';
        wait for 10 ns;

        -- t=60: A=11110000 B=00001111
        A0 <= '1'; A1 <= '1'; A2 <= '1'; A3 <= '1';
        A4 <= '0'; A5 <= '0'; A6 <= '0'; A7 <= '0';
        B0 <= '0'; B1 <= '0'; B2 <= '0'; B3 <= '0';
        B4 <= '1'; B5 <= '1'; B6 <= '1'; B7 <= '1';
        wait for 10 ns;

        -- t=70: A=00001111 B=11110000
        A0 <= '0'; A1 <= '0'; A2 <= '0'; A3 <= '0';
        A4 <= '1'; A5 <= '1'; A6 <= '1'; A7 <= '1';
        B0 <= '1'; B1 <= '1'; B2 <= '1'; B3 <= '1';
        B4 <= '0'; B5 <= '0'; B6 <= '0'; B7 <= '0';
        wait for 10 ns;

        wait;
    end process;

end sim;
