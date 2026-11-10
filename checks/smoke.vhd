library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity smoke_vhdl is end entity;
architecture test of smoke_vhdl is
begin
  process
    variable a, b : unsigned(7 downto 0);
    variable sum : unsigned(8 downto 0);
  begin
    a := to_unsigned(255, 8);
    b := to_unsigned(1, 8);
    sum := resize(a, 9) + resize(b, 9);
    assert sum = to_unsigned(256, 9) severity failure;
    wait;
  end process;
end architecture;
