library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_packet_filter is
end entity;

architecture testbench of tb_packet_filter is
    signal clk:                 std_logic;
    signal rst_n:               std_logic;

    signal filter:              std_logic_vector(15 downto 0);
    signal data_in:             std_logic_vector(8 downto 0);
    signal write_in:            std_logic;
    signal data_out:            std_logic_vector(8 downto 0);
    signal write_out:           std_logic;
begin
    filt1: entity work.PacketFilter
        port map(clk, rst_n, filter, data_in, write_in, data_out, write_out);
    
    process
        procedure clock is
            constant PERIOD: time := 1 us;
        begin
            clk <= '0'; wait for PERIOD/2; clk <= '1'; wait for PERIOD/2;
        end procedure;
    begin
        rst_n <= '0';
        filter <= X"0002";
        data_in <= (others => '0');
        write_in <= '0';
        
        clock;
        rst_n <= '1';
        
        clock;
        
        -- Send a packet that should pass
        write_in <= '1';
        data_in <= "0" & X"A5";
        clock;
        assert data_out = "0" & X"A5" and write_out = '1'
            report "Packet should go through";
        
        data_in <= "0" & X"E1";
        clock;
        assert data_out = "0" & X"E1" and write_out = '1'
            report "Packet should go through";
        
        data_in <= "1" & X"00";
        clock;
        assert data_out = "1" & X"00" and write_out = '1'
            report "Packet should go through";
        write_in <= '0';
        clock;
        
        -- Send a packet that should be filtered
        write_in <= '1';
        data_in <= "0" & X"E1";
        clock;
        assert write_out = '0' report "Packet should be dropped";
        
        data_in <= "0" & X"00";
        clock;
        assert write_out = '0' report "Packet should be dropped";
        
        data_in <= "1" & X"00";
        clock;
        assert write_out = '0' report "Packet should be dropped";
        write_in <= '0';
        
        report "Simulation ended" severity note;
        wait;
    end process;
end architecture;