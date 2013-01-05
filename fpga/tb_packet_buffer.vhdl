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
    signal fifo_valid:  std_logic;
begin
    -- We collect output from the block to a fifo for inspection
    output_fifo: entity work.FIFO
        generic map (width_g => 9, depth_g => 256)
        port map (clk, rst_n, fifo_out, fifo_read, fifo_valid, data_out, write_out, fifo_count);
    
    -- The packet buffer being tested
    buf0: entity work.PacketBuffer
        generic map (timeout_g => 4096)
        port map (clk, rst_n, data_in, write_in, data_out, write_out, cmd, arg, busy, status);
    
    process
        procedure clock is
            constant PERIOD: time := 1 us;
        begin
            clk <= '0'; wait for PERIOD/2; clk <= '1'; wait for PERIOD/2;
        end procedure;
        
        procedure write_packet(
            data : std_logic_vector(0 to 63);
            delay : integer := 0
            ) is
        begin
            for i in 0 to 6 loop
                data_in <= "0" & data(i * 8 to i * 8 + 7);
                write_in <= '1';
                clock;
                write_in <= '0';
                
                for i in 1 to delay loop
                    clock;
                end loop;
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
        
        procedure wait_complete is
        begin
            while busy = '1' loop
                clock;
            end loop;
        end procedure;
  
        procedure start_cmd(cmd_n : BufferCommand; arg_n : std_logic_vector(1 downto 0)) is
        begin
            assert busy = '0' report "Tried to start new command while busy!";
            
            cmd <= cmd_n;
            arg <= arg_n;
            clock;
            cmd <= IDLE;
        end procedure;
                  
    begin
        rst_n <= '0';
        fifo_read <= '0';
        data_in <= (others => '-');
        write_in <= '0';
        cmd <= IDLE;
        arg <= "00";
        clock;
        rst_n <= '1';
        
        -- Test READ-WRITE roundtrip
        write_packet(X"AAAAAA0100000000");
        
        start_cmd(READ, "00");
        wait_complete;
        assert status = '1' report "READ failed";
        
        start_cmd(WRITE, "00");
        wait_complete;
        assert status = '1' report "WRITE failed";
        
        verify_packet(X"AAAAAA0100000000");
        
        -- Test slow packet READ
        start_cmd(READ, "10");
        write_packet(X"1122334455667788", 5);
        wait_complete;
        assert status = '1' report "READ failed";
        
        start_cmd(WRITE, "10");
        wait_complete;
        assert status = '1' report "WRITE failed";
        
        verify_packet(X"1122334455667788");
        
        -- Test CMP when packets are equal except timestamp
        write_packet(X"5566770000000088");
        write_packet(X"5566771111111188");
        start_cmd(READ, "00");
        wait_complete;
        start_cmd(READ, "01");
        wait_complete;
        
        start_cmd(CMP, "01");
        wait_complete;
        
        assert status = '1' report "Packets should compare equal";
        
        start_cmd(DROP, "00"); wait_complete;
        start_cmd(DROP, "01"); wait_complete;
        
        -- Test CMP when packets differ (in EOP)
        write_packet(X"5566770000000088");
        start_cmd(READ, "00");
        wait_complete;
        assert status = '1' report "READ failed";
        write_packet(X"5566771111111189");
        start_cmd(READ, "11");
        wait_complete;
        assert status = '1' report "READ failed";
        
        start_cmd(CMP, "11");
        wait_complete;
        
        assert status = '0' report "Packets should compare different (1)";
        
        start_cmd(DROP, "00"); wait_complete;
        start_cmd(DROP, "11"); wait_complete;
        
        -- Test CMP when packets differ (right before timestamp)
        write_packet(X"5566770000000088");
        start_cmd(READ, "00");
        wait_complete;
        assert status = '1' report "READ failed";
        write_packet(X"5566781111111188");
        start_cmd(READ, "11");
        wait_complete;
        assert status = '1' report "READ failed";
        
        start_cmd(CMP, "11");
        wait_complete;
        
        assert status = '0' report "Packets should compare different (2)";
        
        start_cmd(DROP, "00"); wait_complete;
        start_cmd(DROP, "11"); wait_complete;
        
        -- Test CMP when packets differ (at beginning)
        write_packet(X"5466770000000088");
        start_cmd(READ, "00");
        wait_complete;
        assert status = '1' report "READ failed";
        write_packet(X"5566771111111188");
        start_cmd(READ, "11");
        wait_complete;
        assert status = '1' report "READ failed";
        
        start_cmd(CMP, "11");
        wait_complete;
        
        assert status = '0' report "Packets should compare different (3)";
        
        start_cmd(DROP, "00"); wait_complete;
        start_cmd(DROP, "11"); wait_complete;
        
        -- Test SHIFT and FLAGR
        start_cmd(SHIFT, "01");
        wait_complete;
        
        write_packet(X"1122335555555500");
        start_cmd(READ, "00");
        wait_complete;
        assert status = '1' report "READ failed";
        
        start_cmd(SHIFT, "01");
        wait_complete;
        
        start_cmd(FLAGR, "01");
        wait_complete;
        
        start_cmd(WRITE, "01");
        wait_complete;
        assert status = '1' report "WRITE failed";
        
        verify_packet(X"1122335555555504");
        
        -- Test overlong packets and FLUSH
        start_cmd(READ, "00");
        write_in <= '1';
        for i in 0 to 255 loop
            data_in <= "0" & std_logic_vector(to_unsigned(i, 8));
            clock;
        end loop;
        data_in <= "1" & X"00";
        clock;
        write_in <= '0';
        
        wait_complete;
        assert status = '0' report "Packet shouldn't fit in buffer";
        
        start_cmd(FLUSH, "00");
        
        for i in 0 to 255 loop
            while fifo_valid = '0' loop
                clock;
            end loop;
            
            assert fifo_out = "0" & std_logic_vector(to_unsigned(i, 8))
                report "Wrong byte at position " & integer'image(i);
            
            fifo_read <= '1';
            clock;
            fifo_read <= '0';
            clock;
            clock;
        end loop;
        
        while fifo_valid = '0' loop
            clock;
        end loop;
        assert fifo_out = "1" & X"00" report "Wrong EOP";
        fifo_read <= '1';
        clock;
        fifo_read <= '0';
        clock;
        clock;
        
        wait_complete;
        clock;
        clock;
        
        assert unsigned(fifo_count) = 0 report "Unexpected data";
        
        -- Test packet reading timeout
        start_cmd(READ, "00");
        wait_complete;
        assert status = '0' report "Read should timeout";
        
        wait;
    end process;
end architecture;