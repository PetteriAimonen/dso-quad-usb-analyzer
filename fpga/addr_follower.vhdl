-- Detects "set address" setup transactions on the USB bus and takes note
-- of the new address. This allows to filter the packets coming to/from the
-- newest plugged in device.
--
-- The sequence to detect is:
-- 2D -- -- TT TT TT TT EE                              SETUP
-- C3 00 05 XX 00 00 00 00 00 -- -- TT TT TT TT EE      DATA0
-- D2 TT TT TT TT EE                                    ACK
--
-- If the ACK is missing, the request was to some other port of the hub
-- and is therefore ignored.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AddrFollower is
    port (
        clk:            in std_logic;
        rst_n:          in std_logic;

        -- Data input
        data_in:        in std_logic_vector(8 downto 0);
        write_in:       in std_logic;

        -- Detected address or 0.
        addr_out:       out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of AddrFollower is
    type PacketState is (
        WAITEND, SETUP, DATA, ACK
    );
    
    constant setup_c : std_logic_vector(0 to 7 * 8 + 7) :=
        X"2D00000000000000";
    constant setup_mask_c : std_logic_vector(0 to 7) :=
         "10000001";
    
    constant data_c : std_logic_vector(0 to 15 * 8 + 7) :=
        X"C3000500000000000000000000000000";
    constant data_mask_c : std_logic_vector(0 to 15) :=
        "1110111110000001";
    
    constant ack_c : std_logic_vector(0 to 5 * 8 + 7) :=
        X"D20000000000";
    constant ack_mask_c : std_logic_vector(0 to 5) :=
        "100001";
    
    signal state_r:     PacketState;
    signal index_r:     integer range 0 to 15;
    signal new_addr_r:  std_logic_vector(6 downto 0);
begin
    process (clk, rst_n)
    begin
        if rst_n = '0' then
            state_r <= SETUP;
            index_r <= 0;
            addr_out <= (others => '0');
            new_addr_r <= (others => '0');
        elsif rising_edge(clk) then
            if write_in = '1' then
                if index_r /= 15 then
                    index_r <= index_r + 1;
                end if;
                
                case state_r is
                    when WAITEND =>
                        index_r <= 0;
                        if data_in(8) = '1' then
                            state_r <= SETUP;
                        end if;
                
                    when SETUP =>
                        if setup_mask_c(index_r) = '1' and
                           data_in(7 downto 0) /= setup_c(index_r * 8 to index_r * 8 + 7) then
                            state_r <= WAITEND;
                        end if;
                        
                        if index_r = 7 then
                            index_r <= 0;
                            if data_in(8) = '1' then
                                -- SETUP packet ok
                                state_r <= DATA;
                            else
                                -- Expected EOP
                                state_r <= WAITEND;
                            end if;
                        end if;
                    
                    when DATA =>
                        if data_mask_c(index_r) = '1' and
                           data_in(7 downto 0) /= data_c(index_r * 8 to index_r * 8 + 7) then
                            state_r <= WAITEND;
                        end if;
                        
                        if index_r = 3 then
                            new_addr_r <= data_in(6 downto 0);
                        end if;
                        
                        if index_r = 15 then
                            index_r <= 0;
                            if data_in(8) = '1' then
                                -- DATA packet ok
                                state_r <= ACK;
                            else
                                -- Expected EOP
                                state_r <= WAITEND;
                            end if;
                        end if;
                    
                    when ACK =>
                        if ack_mask_c(index_r) = '1' and
                           data_in(7 downto 0) /= ack_c(index_r * 8 to index_r * 8 + 7) then
                            state_r <= WAITEND;
                        end if;
                        
                        if index_r = 5 then
                            index_r <= 0;
                            if data_in(8) = '1' then
                                -- ACK packet ok
                                addr_out <= new_addr_r;
                                state_r <= SETUP;
                            else
                                -- Expected EOP
                                state_r <= WAITEND;
                            end if;
                        end if;
                end case;
                
                if data_in(8) = '1' and data_in(1) = '1' then
                    -- USB reset
                    state_r <= SETUP;
                    index_r <= 0;
                    new_addr_r <= (others => '0');
                    addr_out <= (others => '0');
                end if;
            end if;
        end if;
    end process;
end architecture;
