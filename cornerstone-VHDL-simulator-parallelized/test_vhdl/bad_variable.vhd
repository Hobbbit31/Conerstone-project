entity bad_tb is
end entity;

architecture test of bad_tb is
  variable x : std_logic := '0';
begin
  x <= '1';
end architecture;
