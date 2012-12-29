-- This is a wrapper around usb_rx_phy to provide a more suitable interface
-- for protocol analyzer purposes.
--
-- Output data is 9-bit. Packet begins with timestamp and ends with EOP token.
-- The bottom 8 bits are the packet data. Bit 9 marks EOP.
--
-- [4 bytes timestamp] [Packet data] [1-byte EOP]
--
-- The bottom part of the
-- end-of-packet token encodes the following information:
--
-- bit 0: If 1, a PHY-level error occurred
-- bit 1: If 1, a USB reset has occurred
-- bit 2: If 1, repeating sequence starts

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity USBDecoder is
    port (
        clk:            in std_logic;
        rst_n:          in std_logic;
        
        -- D+, D- and the resolved differential signal.
        dplus:          in std_logic;
        dminus:         in std_logic;
        ddiff:          in std_logic;
        
        -- Output data.
        data_out:       out std_logic_vector(8 downto 0);
        write:          out std_logic
    );
end entity;

architecture rtl of USBDecoder is
    -- Signals of the USB PHY
    signal phy_fs_ce:   std_logic; -- 12 MHz PLL clock enable
    signal phy_data:    std_logic_vector(7 downto 0); -- Data from PHY
    signal phy_valid:   std_logic; -- Data valid, active for each byte.
    signal phy_active:  std_logic; -- Packet ongoing, inactive between packets
    signal phy_error:   std_logic; -- RX error
    signal phy_enable:  std_logic; -- Enable receiver
    signal phy_state:   std_logic_vector(1 downto 0); -- Status on the input lines
    
    -- Bits in the EOP token
    signal errors_r:    std_logic; -- Errors during this packet
    signal reset_r:     std_logic; -- USB reset has occurred
    
    -- Detection of USB reset
    signal reset_cnt_r: integer range 0 to 180;
    
    -- Registers for block outputs
    signal data_out_r:  std_logic_vector(8 downto 0);
    signal write_r:     std_logic;

    -- Millisecond counter for the timestamp
    signal prescaler_r:  integer range 0 to 72000;
    signal timestamp_r:  unsigned(31 downto 0);
    signal packettime_r: std_logic_vector(31 downto 0);
    
    -- State machine for writing the packet.
    type State is (IDLE, PAYLOAD, TIME1, TIME2, TIME3, TIME4, EOP);
    signal state_r: State;
begin
    phy1: entity work.usb_rx_phy
        port map(
            clk => clk,
            rst => rst_n,
            fs_ce_o => phy_fs_ce,
            rxd => ddiff,
            rxdp => dplus,
            rxdn => dminus,
            DataIn_o => phy_data,
            RxValid_o => phy_valid,
            RxActive_o => phy_active,
            RxError_o => phy_error,
            RxEn_i => phy_enable,
            LineState => phy_state
        );
    
    data_out <= data_out_r;
    write <= write_r;
    phy_enable <= '1';
    
    process (clk, rst_n)
    begin
        if rst_n = '0' then
            errors_r <= '0';
            reset_r <= '0';
            reset_cnt_r <= 0;
            data_out_r <= (others => '0');
            write_r <= '0';
            timestamp_r <= (others => '0');
            packettime_r <= (others => '0');
            prescaler_r <= 0;
            state_r <= IDLE;
        elsif rising_edge(clk) then
            if prescaler_r = 71999 then
                prescaler_r <= 0;
                timestamp_r <= timestamp_r + 1;
            else
                prescaler_r <= prescaler_r + 1;
            end if;
        
            -- Monitor line state to detect USB reset
            if reset_r = '1' then
                -- Wait for the reset to get reported
            elsif reset_cnt_r = 180 then -- 2.5 us
                reset_r <= '1';
                reset_cnt_r <= 0;
            elsif dplus = '1' or dminus = '1' then
                reset_cnt_r <= 0;
            else
                reset_cnt_r <= reset_cnt_r + 1;
            end if;
        
            -- State machine controls the packet writing.
            case state_r is
                when IDLE =>
                    -- Prepare for start of packet
                    write_r <= '0';
                    data_out_r <= (others => '-');
                    packettime_r <= std_logic_vector(timestamp_r);
                    
                    if phy_active = '1' then
                        state_r <= PAYLOAD;
                    end if;
                
                    if (dplus = '1' or dminus = '1') and reset_r = '1' then
                        -- Report the USB reset when it ends
                        state_r <= TIME1;
                    end if;
                
                when PAYLOAD =>
                    -- Move packet data to output
                    data_out_r <= "0" & phy_data;
                    write_r <= phy_valid;
                    errors_r <= errors_r or phy_error;
                
                    if phy_active = '0' then
                        state_r <= TIME1;
                    end if;
                
                when TIME1 =>
                    data_out_r <= "0" & packettime_r(7 downto 0);
                    write_r <= '1';
                    state_r <= TIME2;
                
                when TIME2 =>
                    data_out_r <= "0" & packettime_r(15 downto 8);
                    write_r <= '1';
                    state_r <= TIME3;
                
                when TIME3 =>
                    data_out_r <= "0" & packettime_r(23 downto 16);
                    write_r <= '1';
                    state_r <= TIME4;
                
                when TIME4 =>
                    data_out_r <= "0" & packettime_r(31 downto 24);
                    write_r <= '1';
                    state_r <= EOP;
                
                when EOP => 
                    -- End of packet token
                    data_out_r <= "1000000" & reset_r & errors_r;
                    write_r <= '1';
                    errors_r <= '0';
                    reset_r <= '0';
                    state_r <= IDLE;
            end case;
        end if;
    end process;
end architecture;
