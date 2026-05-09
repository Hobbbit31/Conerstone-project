entity and_gate_tb is
end entity;

architecture test of and_gate_tb is
  signal A, B, OUT1 : std_logic := '0';
begin
  OUT1 <= A and B;

  process
  begin
    A <= '0'; B <= '0';
    wait for 10 ns;
    A <= '1';
    wait for 10 ns;
    B <= '1';
    wait for 10 ns;
    A <= '0';
    wait for 10 ns;
    wait;
  end process;
end architecture;
