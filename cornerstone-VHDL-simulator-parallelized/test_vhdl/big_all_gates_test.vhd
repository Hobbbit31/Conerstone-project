-- test_vhdl/big_all_gates_test.vhd
entity big_all_gates_test is
end entity;

architecture test of big_all_gates_test is
    signal A, B, C, D, S, CLK : std_logic := '0';
    signal y_and, y_or, y_not, y_nand, y_nor, y_xor, y_xnor, y_buf, y_mux : std_logic := '0';
    signal q_reg : std_logic := '0';
    signal s_not, w1, w2 : std_logic := '0';
begin
    -- Simple logic
    y_and  <= A and B;
    y_or   <= C or D;
    y_not  <= not A;
    y_nand <= A nand C;
    y_nor  <= B nor D;
    y_xor  <= A xor D;
    y_xnor <= B xnor C;
    y_buf  <= D;
    
    -- Mux logic
    s_not <= not S;
    w1 <= A and s_not;
    w2 <= B and S;
    y_mux <= w1 or w2;

    -- Sequential logic
    process(CLK) begin
        if rising_edge(CLK) then
            q_reg <= y_mux;
        end if;
    end process;

    -- Stimulus
    process begin
        A<='0'; B<='0'; C<='0'; D<='0'; S<='0'; CLK<='0'; wait for 5 ns;
        A<='1'; B<='1'; wait for 5 ns;
        CLK<='1'; wait for 5 ns;
        CLK<='0'; S<='1'; C<='1'; D<='1'; wait for 5 ns;
        CLK<='1'; wait for 5 ns;
        wait;
    end process;
end architecture;
