library ieee;
use ieee.std_logic_1164.all;

entity bad_tb is
end entity;

architecture test of bad_tb is
  signal A : std_logic := '0';
begin
  A <= '1';
end architecture;
