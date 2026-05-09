-- test_vhdl/comb_complex_logic.vhd
entity comb_complex_logic is
end entity;

architecture test of comb_complex_logic is
    signal A, B, C, D : std_logic := '0';
    signal w1, w2, w3, w4 : std_logic := '0';
    signal y_out : std_logic := '0';
begin
    w1 <= A and B;
    w2 <= C or D;
    w3 <= w1 xor w2;
    w4 <= w1 nand w3;
    y_out <= w4 nor w2;

    process begin
        A<='0'; B<='0'; C<='0'; D<='0'; wait for 10 ns;
        A<='1'; B<='0'; C<='1'; D<='0'; wait for 10 ns;
        A<='1'; B<='1'; C<='1'; D<='1'; wait for 10 ns;
        A<='0'; B<='1'; C<='0'; D<='1'; wait for 10 ns;
        wait;
    end process;
end architecture;
