-- test_vhdl/comb_basic_gates.vhd
entity comb_basic_gates is
end entity;

architecture test of comb_basic_gates is
    signal A, B, C, D : std_logic := '0';
    signal y1, y2, y3, y4, y5, y6 : std_logic := '0';
begin
    y1 <= A and B;
    y2 <= C or D;
    y3 <= A xor C;
    y4 <= B nand D;
    y5 <= A nor B;
    y6 <= C xnor D;

    process begin
        A<='0'; B<='0'; C<='0'; D<='0'; wait for 10 ns;
        A<='1'; B<='0'; C<='1'; D<='0'; wait for 10 ns;
        A<='1'; B<='1'; C<='1'; D<='1'; wait for 10 ns;
        wait;
    end process;
end architecture;
