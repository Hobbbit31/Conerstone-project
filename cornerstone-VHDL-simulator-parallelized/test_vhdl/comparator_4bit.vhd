entity comparator_4bit_tb is
end entity;

architecture test of comparator_4bit_tb is
  signal A0, A1, A2, A3 : std_logic := '0';
  signal B0, B1, B2, B3 : std_logic := '0';
  signal EQ, GT, LT : std_logic := '0';
  signal e0, e1, e2, e3 : std_logic := '0';
  signal g0, g1, g2, g3 : std_logic := '0';
  signal nB0, nB1, nB2, nB3 : std_logic := '0';
  signal nA0, nA1, nA2, nA3 : std_logic := '0';
begin
  -- Bit-wise equality: ei = Ai XNOR Bi = NOT(Ai XOR Bi)
  e0 <= not (A0 xor B0);
  e1 <= not (A1 xor B1);
  e2 <= not (A2 xor B2);
  e3 <= not (A3 xor B3);

  -- EQ = all bits equal
  EQ <= e3 and e2 and e1 and e0;

  -- GT (A > B): check from MSB down
  nB3 <= not B3;
  nB2 <= not B2;
  nB1 <= not B1;
  nB0 <= not B0;
  g3 <= A3 and nB3;
  g2 <= e3 and A2 and nB2;
  g1 <= e3 and e2 and A1 and nB1;
  g0 <= e3 and e2 and e1 and A0 and nB0;
  GT <= g3 or g2 or g1 or g0;

  -- LT = not EQ and not GT
  LT <= not (EQ or GT);

  process
  begin
    -- A=5, B=5 => EQ
    A3 <= '0'; A2 <= '1'; A1 <= '0'; A0 <= '1';
    B3 <= '0'; B2 <= '1'; B1 <= '0'; B0 <= '1';
    wait for 10 ns;
    -- A=7, B=3 => GT
    A3 <= '0'; A2 <= '1'; A1 <= '1'; A0 <= '1';
    B3 <= '0'; B2 <= '0'; B1 <= '1'; B0 <= '1';
    wait for 10 ns;
    -- A=2, B=10 => LT
    A3 <= '0'; A2 <= '0'; A1 <= '1'; A0 <= '0';
    B3 <= '1'; B2 <= '0'; B1 <= '1'; B0 <= '0';
    wait for 10 ns;
    -- A=0, B=0 => EQ
    A3 <= '0'; A2 <= '0'; A1 <= '0'; A0 <= '0';
    B3 <= '0'; B2 <= '0'; B1 <= '0'; B0 <= '0';
    wait for 10 ns;
    -- A=15, B=14 => GT
    A3 <= '1'; A2 <= '1'; A1 <= '1'; A0 <= '1';
    B3 <= '1'; B2 <= '1'; B1 <= '1'; B0 <= '0';
    wait for 10 ns;
    wait;
  end process;
end architecture;
