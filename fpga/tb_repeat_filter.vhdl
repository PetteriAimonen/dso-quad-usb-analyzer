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
    signal fifo_valid:          std_logic;
    signal fifo_read:           std_logic;
begin
    filt0: entity work.RepeatFilter
        generic map (timeout_g => 4096)
        port map (clk, rst_n, enable, data_in, write_in, data_out, write_out);
    
    -- We collect output from the block to a fifo for inspection
    output_fifo: entity work.FIFO
        generic map (width_g => 9, depth_g => 1024)
        port map (clk, rst_n, fifo_out, fifo_read, fifo_valid, data_out, write_out, fifo_count);
    
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
        file_open(output, "tb_repeat_filter_output.txt", write_mode);
        
        rst_n <= '0';
        enable <= '1';
        data_in <= (others => '-');
        write_in <= '0';
        fifo_read <= '0';
        clock;
        rst_n <= '1';
        
        -- Write all packets from the input file
        while not endfile(input) loop
            readline(input, line_in);
            next when line_in'length < 2 or line_in(1) = '#';
            
            while line_in'length > 3 loop
                hread(line_in, byte);            
                data_in <= "0" & byte;
                write_in <= '1';
                clock;
                write_in <= '0';
                clock; clock; clock; clock;
            end loop;
            
            hread(line_in, byte);
            data_in <= "1" & byte;
            write_in <= '1';
            clock;
            write_in <= '0';
            clock; clock; clock; clock;
        end loop;
    
        -- Wait for the timeout to make sure everything is written to fifo
        for i in 0 to 16384 loop
            clock;
        end loop;
    
        -- Write all packets to the output file
        while unsigned(fifo_count) > 0 loop
            line_in := new string'("");
            while fifo_out(8) = '0' loop
                hwrite(line_in, fifo_out(7 downto 0), right, 2);
                write(line_in, string'(" "));
                
                fifo_read <= '1';
                clock;
                fifo_read <= '0';
                clock; clock;
            end loop;
        
            hwrite(line_in, fifo_out(7 downto 0), right, 2);
            writeline(output, line_in);
            
            fifo_read <= '1';
            clock;
            fifo_read <= '0';
            clock; clock;
        end loop;
    
        wait;
    end process;
end architecture;