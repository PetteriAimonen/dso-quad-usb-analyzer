-- This is a wrapper around usb_rx_phy to provide a more suitable interface
-- for protocol analyzer purposes.
--
-- Output data is 9-bit. The bottom 8 bits are the packet data. Each packet
-- is terminated by a value with top bit set. The bottom part of the
-- end-of-packet token encodes the following information:
--
-- bit 0: If 1, a PHY-level error occurred

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
    
    -- Whether any errors have occurred
    signal active_r:    std_logic; -- Packet ongoing
    signal errors_r:    std_logic; -- Errors during this packet
    signal data_out_r:  std_logic_vector(8 downto 0);
    signal write_r:     std_logic;
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
            active_r <= '0';
            errors_r <= '0';
            data_out_r <= (others => '0');
            write_r <= '0';
        elsif rising_edge(clk) then
            if active_r = '0' then
                active_r <= phy_active;
                errors_r <= '0';
                write_r <= '0';
                data_out_r <= (others => '-');
            else
                if phy_active = '1' then
                    -- Move packet data to output
                    data_out_r <= "0" & phy_data;
                    write_r <= phy_valid;
                    errors_r <= errors_r or phy_error;
                    active_r <= '1';
                else
                    -- End of packet token
                    data_out_r <= "10000000" & errors_r;
                    write_r <= '1';
                    active_r <= '0';
                    errors_r <= '0';
                end if;
            end if;
        end if;
    end process;
end architecture;
