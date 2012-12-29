-- Simulation / interface model for the iCE65 RAM modules.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity RAMBlock is
    generic (
        width_g:        natural := 16; -- Width of data words
        addr_g:         natural := 8   -- Number of bits in address
    );
    
    port (
        clk:            in std_logic;
        
        -- Write port
        wdata:          in std_logic_vector(width_g - 1 downto 0);
        waddr:          in std_logic_vector(addr_g - 1 downto 0);
        we:             in std_logic;
        
        -- Read port
        rdata:          out std_logic_vector(width_g - 1 downto 0);
        raddr:          in std_logic_vector(addr_g - 1 downto 0);
        re:             in std_logic
    );
end entity;

architecture rtl of RAMBlock is
    constant depth_g : natural := 2**addr_g;

    subtype word_t is std_logic_vector(width_g - 1 downto 0);
    type array_t is array(0 to depth_g - 1) of word_t;
    signal mem_r: array_t;
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem_r(to_integer(unsigned(waddr))) <= wdata;
            end if;
            
            if re = '1' then
                rdata <= mem_r(to_integer(unsigned(raddr)));
            end if;
        end if;
    end process;
end architecture;