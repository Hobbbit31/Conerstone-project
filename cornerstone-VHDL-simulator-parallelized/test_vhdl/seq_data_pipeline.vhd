-- test_vhdl/seq_data_pipeline.vhd
entity seq_data_pipeline is
end entity;

architecture test of seq_data_pipeline is
    signal CLK, D_IN : std_logic := '0';
    signal R1, R2, R3 : std_logic := '0';
    signal w1, w2 : std_logic := '0';
begin
    -- Stage 1
    process(CLK) begin
        if rising_edge(CLK) then
            R1 <= D_IN;
        end if;
    end process;

    -- Stage 2
    w1 <= not R1;
    process(CLK) begin
        if rising_edge(CLK) then
            R2 <= w1;
        end if;
    end process;

    -- Stage 3
    w2 <= R1 xor R2;
    process(CLK) begin
        if rising_edge(CLK) then
            R3 <= w2;
        end if;
    end process;

    process begin
        D_IN <= '1'; CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        CLK <= '0'; D_IN <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        wait;
    end process;
end architecture;
