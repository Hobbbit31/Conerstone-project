-- test_vhdl/comb_priority_encoder.vhd
-- COMBINATIONAL CIRCUIT
-- A 4-to-2 Priority Encoder with individual signals.
entity comb_priority_encoder is
end entity;

architecture rtl of comb_priority_encoder is
    signal D3, D2, D1, D0 : std_logic := '0';
    signal Y1, Y0 : std_logic := '0';
    signal V : std_logic := '0';
begin
    Y1 <= D3 or D2;
    Y0 <= D3 or ((not D2) and D1);
    V  <= D3 or D2 or D1 or D0;

    process begin
        D0<='1'; wait for 10 ns;
        D1<='1'; wait for 10 ns;
        D2<='1'; wait for 10 ns;
        D3<='1'; wait for 10 ns;
        wait;
    end process;
end architecture;
