library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use work.std_logic_textio.all;

entity tb_addr_follower is
end entity;

architecture testbench of tb_addr_follower is
    signal clk:                 std_logic;
    signal rst_n:               std_logic;
    signal data_in:             std_logic_vector(8 downto 0);
    signal write_in:            std_logic;
    signal addr_out:            std_logic_vector(6 downto 0);
begin
    flw0: entity work.AddrFollower
        port map (clk, rst_n, data_in, write_in, addr_out);
    
    process
        file input:             text;
        variable line_in:       line;
        variable byte:          std_logic_vector(7 downto 0);
    
        procedure clock is
            constant PERIOD: time := 1 us;
        begin
            clk <= '0'; wait for PERIOD/2; clk <= '1'; wait for PERIOD/2;
        end procedure;
    begin
        file_open(input, "tb_addr_follower_input.txt", read_mode);
        
        rst_n <= '0';
        data_in <= (others => '-');
        write_in <= '0';
        clock;
        rst_n <= '1';
        
        -- Write all packets from the input file and verify that the last
        -- value on the line matches the output of the block.
        while not endfile(input) loop
            readline(input, line_in);
            next when line_in'length < 2 or line_in(1) = '#';
            
            while line_in'length > 3 loop
                hread(line_in, byte);
                data_in <= "0" & byte;
                
                if line_in'length <= 3 then
                    data_in(8) <= '1'; -- EOP
                end if;
                
                write_in <= '1';
                clock;
                write_in <= '0';
            end loop;
            
            hread(line_in, byte);
            assert addr_out = byte(6 downto 0)
                report "Expected address "
                    & integer'image(to_integer(unsigned(byte))) & " got "
                    & integer'image(to_integer(unsigned(addr_out)));
        end loop;
    
        wait;
    end process;
end architecture;