library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.PacketBuffer_pkg.all;

entity tb_packet_buffer is
end entity;

architecture testbench of tb_packet_buffer is
    signal clk:                 std_logic;
    signal rst_n:               std_logic;
    signal data_in:             std_logic_vector(8 downto 0);
    signal write_in:            std_logic;
    signal data_out:            std_logic_vector(8 downto 0);
    signal write_out:           std_logic;
    signal cmd:                 BufferCommand;
    signal arg:                 std_logic_vector(1 downto 0);
    signal busy:                std_logic;
    signal status:              std_logic;
    
    signal fifo_out:    std_logic_vector(8 downto 0);
    signal fifo_count:  std_logic_vector(15 downto 0);
    signal fifo_read:   std_logic;
begin
    -- We collect output from the block to a fifo for inspection
    output_fifo: entity work.FIFO
        generic map (width_g => 9, depth_g => 256)
        port map (clk, rst_n, fifo_out, fifo_read, data_out, write_out, fifo_count);
    
    -- The packet buffer being tested
    buf0: entity work.PacketBuffer
        port map (clk, rst_n, data_in, write_in, data_out, write_out, cmd, arg, busy, status);
    
    process
        procedure clock is
            constant PERIOD: time := 1 us;
        begin
            clk <= '0'; wait for PERIOD/2; clk <= '1'; wait for PERIOD/2;
        end procedure;
        
        procedure write_packet(data : std_logic_vector(0 to 63)) is
        begin
            for i in 0 to 6 loop
                data_in <= "0" & data(i * 8 to i * 8 + 7);
                write_in <= '1';
                clock;
            end loop;
            
            data_in <= "1" & data(56 to 63);
            write_in <= '1';
            clock;
            
            write_in <= '0';
        end procedure;
        
        procedure verify_packet(data : std_logic_vector(0 to 63)) is
        begin
            clock;
            clock;
            clock;
            assert to_integer(unsigned(fifo_count)) = 8
                report "Packet length wrong!";
            
            for i in 0 to 7 loop
                assert fifo_out(7 downto 0) = data(i * 8 to i * 8 + 7)
                    report "Packet byte " & integer'image(i) & " is wrong";
                
                if i = 7 then
                    assert fifo_out(8) = '1' report "Expected EOP";
                else
                    assert fifo_out(8) = '0' report "Premature EOP";
                end if;
                
                fifo_read <= '1';
                clock;
                fifo_read <= '0';
                clock;
                clock;
            end loop;
        end procedure;
    begin
        rst_n <= '0';
        fifo_read <= '0';
        data_in <= (others => '-');
        write_in <= '0';
        clock;
        rst_n <= '1';
        
        -- Test READ-WRITE roundtrip
        write_packet(X"01000000AAAAAA00");
        
        cmd <= READ;
        arg <= "00";
        clock;
        cmd <= IDLE;
        
        while busy = '1' loop
            clock;
        end loop;
        
        cmd <= WRITE;
        arg <= "00";
        clock;
        cmd <= IDLE;
        
        while busy = '1' loop
            clock;
        end loop;
        
        verify_packet(X"01000000AAAAAA00");
        
        wait;
    end process;
end architecture;