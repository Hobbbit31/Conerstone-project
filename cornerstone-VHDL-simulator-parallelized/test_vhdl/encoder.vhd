entity encoder_tb is
end entity;

architecture test of encoder_tb is
  signal D0, D1, D2, D3 : std_logic := '0';
  signal Y0, Y1 : std_logic := '0';
  signal V : std_logic := '0';
begin
  -- 4-to-2 priority encoder with valid bit
  -- Y1 Y0 encodes highest active input
  Y1 <= D3 or D2;
  Y0 <= D3 or ((not D2) and D1);
  V  <= D3 or D2 or D1 or D0;

  process
  begin
    -- No input active => V=0
    D3 <= '0'; D2 <= '0'; D1 <= '0'; D0 <= '0';
    wait for 10 ns;
    -- D0 only => Y=00, V=1
    D0 <= '1';
    wait for 10 ns;
    -- D1 active => Y=01, V=1
    D1 <= '1'; D0 <= '0';
    wait for 10 ns;
    -- D2 active => Y=10, V=1
    D2 <= '1'; D1 <= '0';
    wait for 10 ns;
    -- D3 active => Y=11, V=1
    D3 <= '1'; D2 <= '0';
    wait for 10 ns;
    -- D3 and D0 both active => Y=11 (priority), V=1
    D0 <= '1';
    wait for 10 ns;
    -- D2 and D1 both active => Y=10 (priority), V=1
    D3 <= '0'; D2 <= '1'; D1 <= '1'; D0 <= '0';
    wait for 10 ns;
    wait;
  end process;
end architecture;
