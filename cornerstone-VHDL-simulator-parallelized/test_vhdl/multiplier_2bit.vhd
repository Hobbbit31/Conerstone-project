entity multiplier_2bit_tb is
end entity;

architecture test of multiplier_2bit_tb is
  signal A0, A1, B0, B1 : std_logic := '0';
  signal P0, P1, P2, P3 : std_logic := '0';
  signal pp0, pp1, pp2, pp3 : std_logic := '0';
  signal c1, c2 : std_logic := '0';
  signal s1 : std_logic := '0';
begin
  -- Partial products
  pp0 <= A0 and B0;
  pp1 <= A1 and B0;
  pp2 <= A0 and B1;
  pp3 <= A1 and B1;

  -- P0 = pp0
  P0 <= pp0;

  -- P1 = pp1 XOR pp2, carry c1
  P1 <= pp1 xor pp2;
  c1 <= pp1 and pp2;

  -- P2 = pp3 XOR c1, carry c2
  P2 <= pp3 xor c1;
  P3 <= pp3 and c1;

  process
  begin
    -- 0 * 0 = 0
    A1 <= '0'; A0 <= '0'; B1 <= '0'; B0 <= '0';
    wait for 10 ns;
    -- 1 * 1 = 1
    A1 <= '0'; A0 <= '1'; B1 <= '0'; B0 <= '1';
    wait for 10 ns;
    -- 2 * 3 = 6 (10 * 11 = 0110)
    A1 <= '1'; A0 <= '0'; B1 <= '1'; B0 <= '1';
    wait for 10 ns;
    -- 3 * 3 = 9 (11 * 11 = 1001)
    A1 <= '1'; A0 <= '1'; B1 <= '1'; B0 <= '1';
    wait for 10 ns;
    -- 3 * 2 = 6
    A1 <= '1'; A0 <= '1'; B1 <= '1'; B0 <= '0';
    wait for 10 ns;
    -- 1 * 3 = 3
    A1 <= '0'; A0 <= '1'; B1 <= '1'; B0 <= '1';
    wait for 10 ns;
    wait;
  end process;
end architecture;
