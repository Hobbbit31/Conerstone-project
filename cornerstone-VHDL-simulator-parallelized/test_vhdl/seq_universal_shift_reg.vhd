-- test_vhdl/seq_universal_shift_reg.vhd
-- SEQUENTIAL CIRCUIT
-- A 4-bit Universal Shift Register.
entity seq_universal_shift_reg is
end entity;

architecture rtl of seq_universal_shift_reg is
    signal CLK, D_IN : std_logic := '0';
    signal Q0, Q1, Q2, Q3 : std_logic := '0';
    signal w0, w1, w2, w3 : std_logic := '0';
    signal LOAD : std_logic := '0';
    signal P0, P1, P2, P3 : std_logic := '0';
begin
    w0 <= (D_IN and (not LOAD)) or (P0 and LOAD);
    process(CLK) begin
        if rising_edge(CLK) then
            Q0 <= w0;
        end if;
    end process;

    w1 <= (Q0 and (not LOAD)) or (P1 and LOAD);
    process(CLK) begin
        if rising_edge(CLK) then
            Q1 <= w1;
        end if;
    end process;

    w2 <= (Q1 and (not LOAD)) or (P2 and LOAD);
    process(CLK) begin
        if rising_edge(CLK) then
            Q2 <= w2;
        end if;
    end process;

    w3 <= (Q2 and (not LOAD)) or (P3 and LOAD);
    process(CLK) begin
        if rising_edge(CLK) then
            Q3 <= w3;
        end if;
    end process;

    process begin
        P3<='1'; P2<='0'; P1<='1'; P0<='0'; LOAD<='1'; CLK<='0'; wait for 5 ns;
        CLK<='1'; wait for 5 ns;
        LOAD<='0'; D_IN<='1'; CLK<='0'; wait for 5 ns;
        CLK<='1'; wait for 5 ns;
        CLK<='0'; D_IN<='0'; wait for 5 ns;
        CLK<='1'; wait for 5 ns;
        wait;
    end process;
end architecture;
