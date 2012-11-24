library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_usb_decoder is
end entity;

architecture testbench of tb_usb_decoder is
    signal clk:            std_logic;
    signal rst_n:          std_logic;
    
    -- D+, D- and the resolved differential signal.
    signal dplus:          std_logic;
    signal dminus:         std_logic;
    signal ddiff:          std_logic;
    
    -- Output data from decoder
    signal data_out:       std_logic_vector(8 downto 0);
    signal write:          std_logic;

    -- Test data to feed in (samplerate 12 MHz)
    constant data_minus: std_logic_vector(0 to 50) :=
        "000000000000101010111001001110100101001110010000000";
    constant data_plus: std_logic_vector(0 to 50) :=
        "111111111111010101000110110001011010110001100011111";
        
    -- Output packet
    subtype OutValue is std_logic_vector(8 downto 0);
    type OutArray is array(7 downto 0) of OutValue;
    signal buffer_r:    OutArray;
begin
    dec1: entity work.USBDecoder
        port map (clk, rst_n, dplus, dminus, ddiff, data_out, write);
    
    ddiff <= dplus;
    
    process
        variable idx_v: natural;
    
        -- 72 MHz clock
        procedure clock is
            constant PERIOD: time := 13.888 ns;
        begin
            clk <= '0'; wait for PERIOD/2; clk <= '1'; wait for PERIOD/2;
        end procedure;
        
        -- 6 clock cycles = 1 USB FS period
        -- Toggle the clock and receive data.
        procedure clock_fs(count: integer) is
        begin
            for c in 1 to count loop
                clock;
                if write = '1' then
                    buffer_r(idx_v) <= data_out;
                    idx_v := idx_v + 1;
                end if;
            end loop;
        end procedure;
    begin
        rst_n <= '0';
        dplus <= '1';
        dminus <= '0';
        
        clock;
        
        rst_n <= '1';
        
        clock;
        clock;
        
        -- Test simple packet decoding
        idx_v := 0;
        for i in data_plus'range loop
            dplus <= data_plus(i);
            dminus <= data_minus(i);
            clock_fs(6);
        end loop;
        
        clock_fs(6);
        clock_fs(6);
        clock_fs(6);
        
        assert idx_v = 4 report "Packet length is wrong";
        assert buffer_r(0) = "0" & X"A5" report "Byte 1 wrong";
        assert buffer_r(1) = "0" & X"11" report "Byte 2 wrong";
        assert buffer_r(2) = "0" & X"5A" report "Byte 3 wrong";
        assert buffer_r(3) = "1" & X"00" report "EOP wrong";
        
        report "Simulation ended" severity note;
        wait;
    end process;
end architecture;