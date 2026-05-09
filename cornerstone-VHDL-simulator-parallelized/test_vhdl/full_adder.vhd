entity full_adder_tb is
end entity;

architecture test of full_adder_tb is
  signal A, B, Cin, Sum, Cout : std_logic := '0';
  signal t0, t1, t2 : std_logic := '0';
begin
  t0  <= A xor B;
  Sum <= t0 xor Cin;
  t1   <= A and B;
  t2   <= Cin and t0;
  Cout <= t1 or t2;

  process
  begin
    A <= '0'; B <= '0'; Cin <= '0';
    wait for 10 ns;
    A <= '1';
    wait for 10 ns;
    B <= '1';
    wait for 10 ns;
    Cin <= '1';
    wait for 10 ns;
    A <= '0'; B <= '0'; Cin <= '0';
    wait for 10 ns;
    wait;
  end process;
end architecture;
