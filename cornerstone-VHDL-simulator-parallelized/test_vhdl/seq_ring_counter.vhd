-- test_vhdl/seq_ring_counter.vhd
-- SEQUENTIAL CIRCUIT
-- A 4-bit Ring Counter using individual signals and BUF gates.
entity seq_ring_counter is
end entity;

architecture rtl of seq_ring_counter is
    signal CLK, D_IN : std_logic := '0';
    signal Q0, Q1, Q2, Q3 : std_logic := '0';
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

    process(CLK) begin
        if rising_edge(CLK) then
            Q3 <= Q2;
        end if;
    end process;
    
    -- Stimulus does the recirculation manually
    process begin
        -- Cycle 1
        D_IN <= '1'; CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        -- Cycle 2 (Manually set D_IN to Q3)
        D_IN <= '0'; CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        -- Cycle 3
        D_IN <= '0'; CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        -- Cycle 4
        D_IN <= '0'; CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        -- Cycle 5 (Ring back: Q3 was 1)
        D_IN <= '1'; CLK <= '0'; wait for 5 ns;
        CLK <= '1'; wait for 5 ns;
        wait;
    end process;
end architecture;
