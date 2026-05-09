entity ripple_carry_adder_4bit_tb is
end entity;

architecture test of ripple_carry_adder_4bit_tb is
  signal A0, A1, A2, A3 : std_logic := '0';
  signal B0, B1, B2, B3 : std_logic := '0';
  signal Cin : std_logic := '0';
  signal S0, S1, S2, S3, Cout : std_logic := '0';
  signal c0, c1, c2 : std_logic := '0';
  signal t0, t1, t2, t3, t4, t5, t6, t7 : std_logic := '0';
begin
  -- Full adder 0
  t0 <= A0 xor B0;
  S0 <= t0 xor Cin;
  t1 <= A0 and B0;
  t2 <= Cin and t0;
  c0 <= t1 or t2;

  -- Full adder 1
  t3 <= A1 xor B1;
  S1 <= t3 xor c0;
  t4 <= A1 and B1;
  t5 <= c0 and t3;
  c1 <= t4 or t5;

  -- Full adder 2
  t6 <= A2 xor B2;
  S2 <= t6 xor c1;
  t7 <= A2 and B2;
  c2 <= t7 or (c1 and t6);

  -- Full adder 3
  S3 <= (A3 xor B3) xor c2;
  Cout <= (A3 and B3) or (c2 and (A3 xor B3));

  process
  begin
    -- 0 + 0 = 0
    A3 <= '0'; A2 <= '0'; A1 <= '0'; A0 <= '0';
    B3 <= '0'; B2 <= '0'; B1 <= '0'; B0 <= '0';
    Cin <= '0';
    wait for 10 ns;
    -- 3 + 5 = 8 (0011 + 0101 = 1000)
    A3 <= '0'; A2 <= '0'; A1 <= '1'; A0 <= '1';
    B3 <= '0'; B2 <= '1'; B1 <= '0'; B0 <= '1';
    wait for 10 ns;
    -- 7 + 7 = 14 (0111 + 0111 = 1110)
    A3 <= '0'; A2 <= '1'; A1 <= '1'; A0 <= '1';
    B3 <= '0'; B2 <= '1'; B1 <= '1'; B0 <= '1';
    wait for 10 ns;
    -- 15 + 1 = 16 (1111 + 0001 = 10000, overflow)
    A3 <= '1'; A2 <= '1'; A1 <= '1'; A0 <= '1';
    B3 <= '0'; B2 <= '0'; B1 <= '0'; B0 <= '1';
    wait for 10 ns;
    -- 9 + 6 + Cin = 16 (1001 + 0110 + 1 = 10000)
    A3 <= '1'; A2 <= '0'; A1 <= '0'; A0 <= '1';
    B3 <= '0'; B2 <= '1'; B1 <= '1'; B0 <= '0';
    Cin <= '1';
    wait for 10 ns;
    wait;
  end process;
end architecture;
