-- test_vhdl/seq_simple_shifter.vhd
entity seq_simple_shifter is
end entity;

architecture test of seq_simple_shifter is
    signal CLK, D_IN : std_logic := '0';
    signal Q0, Q1, Q2 : std_logic := '0';
begin
    process(CLK) begin
        if rising_edge(CLK) then
            Q0 <= D_IN;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            Q1 <= Q0;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            Q2 <= Q1;
        end if;
    end process;

    process begin
        D_IN <= '1'; CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        CLK <= '0'; D_IN <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        wait;
    end process;
end architecture;
