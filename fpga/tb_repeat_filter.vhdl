library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use work.std_logic_textio.all;

entity tb_repeat_filter is
end entity;

architecture testbench of tb_repeat_filter is
    signal clk:                 std_logic;
    signal rst_n:               std_logic;
    signal enable:              std_logic;
    signal data_in:             std_logic_vector(8 downto 0);
    signal write_in:            std_logic;
    signal data_out:            std_logic_vector(8 downto 0);
    signal write_out:           std_logic;
    
    signal fifo_out:            std_logic_vector(8 downto 0);
    signal fifo_count:          std_logic_vector(15 downto 0);
    signal fifo_read:           std_logic;
begin
    filt0: entity work.RepeatFilter
        port map (clk, rst_n, enable, data_in, write_in, data_out, write_out);
    
    -- We collect output from the block to a fifo for inspection
    output_fifo: entity work.FIFO
        generic map (width_g => 9, depth_g => 1024)
        port map (clk, rst_n, fifo_out, fifo_read, data_out, write_out, fifo_count);
    
    process
        file input:             text;
        file output:            text;
        variable line_in:       line;
        variable byte:          std_logic_vector(7 downto 0);
    
        procedure clock is
            constant PERIOD: time := 1 us;
        begin
            clk <= '0'; wait for PERIOD/2; clk <= '1'; wait for PERIOD/2;
        end procedure;
    begin
        file_open(input, "tb_repeat_filter_input.txt", read_mode);
        
        rst_n <= '0';
        enable <= '1';
        data_in <= (others => '-');
        write_in <= '0';
        fifo_read <= '0';
        clock;
        rst_n <= '1';
        
        while not endfile(input) loop
            readline(input, line_in);
            next when line_in'length < 2 or line_in(1) = '#';
            
            while line_in'length > 3 loop
                hread(line_in, byte);            
                data_in <= "0" & byte;
                clock;
            end loop;
            
            hread(line_in, byte);
            data_in <= "1" & byte;
            clock;
        end loop;
    
        wait;
    end process;
end architecture;