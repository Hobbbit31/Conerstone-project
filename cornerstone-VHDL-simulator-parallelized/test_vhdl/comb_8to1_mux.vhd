-- test_vhdl/comb_8to1_mux.vhd
-- COMBINATIONAL CIRCUIT
-- This is an 8-to-1 Multiplexer built using individual signals.
entity comb_8to1_mux is
end entity;

architecture rtl of comb_8to1_mux is
    signal D0, D1, D2, D3, D4, D5, D6, D7 : std_logic := '0';
    signal S2, S1, S0 : std_logic := '0';
    signal sn2, sn1, sn0 : std_logic := '0';
    signal w0, w1, w2, w3, w4, w5, w6, w7 : std_logic := '0';
    signal Y : std_logic := '0';
begin
    sn2 <= not S2;
    sn1 <= not S1;
    sn0 <= not S0;

    w0 <= D0 and sn2 and sn1 and sn0;
    w1 <= D1 and sn2 and sn1 and S0;
    w2 <= D2 and sn2 and S1 and sn0;
    w3 <= D3 and sn2 and S1 and S0;
    w4 <= D4 and S2 and sn1 and sn0;
    w5 <= D5 and S2 and sn1 and S0;
    w6 <= D6 and S2 and S1 and sn0;
    w7 <= D7 and S2 and S1 and S0;

    Y <= w0 or w1 or w2 or w3 or w4 or w5 or w6 or w7;

    process begin
        D0<='0'; D1<='1'; D2<='0'; D3<='1'; D4<='0'; D5<='1'; D6<='0'; D7<='1';
        S2<='0'; S1<='0'; S0<='0'; wait for 10 ns; -- Select D0 (0)
        S0<='1'; wait for 10 ns; -- Select D1 (1)
        S1<='1'; S0<='0'; wait for 10 ns; -- Select D2 (0)
        S0<='1'; wait for 10 ns; -- Select D3 (1)
        wait;
    end process;
end architecture;
