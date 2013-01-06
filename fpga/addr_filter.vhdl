-- Filters USB packets based on the address.
--
-- 1. When token packet is received, checks the address
-- 2. If address is ok, passes all packets until next token packet.
-- 3. If address is blocked, filters following packets until next token:
--    data0, data1, data2, mdata, ack, nak, stall.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AddrFilter is
    port (
        clk:            in std_logic;
        rst_n:          in std_logic;

        minaddr:        in std_logic_vector(6 downto 0);
        maxaddr:        in std_logic_vector(6 downto 0);
        pass_zero:      in std_logic;
        
        -- Data input
        data_in:        in std_logic_vector(8 downto 0);
        write_in:       in std_logic;
        
        -- Data output
        data_out:       out std_logic_vector(8 downto 0);
        write_out:      out std_logic
    );
end entity;

architecture rtl of AddrFilter is
    type PacketState is (PID, PIDCHECK, ADDR, ADDRCHECK, PASS_PID, PASS_ADDR, PASS_ADDR2, PASS_REST, DROP);
    signal state_r:     PacketState;

    signal pid_r:       std_logic_vector(7 downto 0);
    signal addr_r:      std_logic_vector(7 downto 0);
    
    signal addr_ok_r:   std_logic;
begin
    process (clk, rst_n)
        variable addr_v: unsigned(6 downto 0);
    begin
        if rst_n = '0' then
            state_r <= PID;
            addr_ok_r <= '1';
            data_out <= (others => '0');
            write_out <= '0';
        elsif rising_edge(clk) then
            write_out <= '0';
            data_out <= (others => '-');
        
            case state_r is
                when PID =>
                    pid_r <= data_in(7 downto 0);
                    if write_in = '1' then
                        state_r <= PIDCHECK;
                    end if;
                
                when PIDCHECK =>
                    if pid_r(7 downto 4) /= not pid_r(3 downto 0) then
                        -- Invalid pid, pass through
                        state_r <= PASS_PID;
                    elsif pid_r(3 downto 0) = "0001" or
                          pid_r(3 downto 0) = "1001" or
                          pid_r(3 downto 0) = "1101" then
                        -- Token packet
                        state_r <= ADDR;
                    elsif pid_r(3 downto 0) = "0010" or
                          pid_r(3 downto 0) = "0011" or
                          pid_r(3 downto 0) = "0111" or
                          pid_r(3 downto 0) = "1010" or
                          pid_r(3 downto 0) = "1011" or
                          pid_r(3 downto 0) = "1110" or
                          pid_r(3 downto 0) = "1111" then
                        -- Packet that we will filter
                        if addr_ok_r = '1' then
                            state_r <= PASS_PID;
                        else
                            state_r <= DROP;
                        end if;
                    else
                        state_r <= PASS_PID;
                    end if;
                            
                when ADDR =>
                    addr_r <= data_in(7 downto 0);
                    if write_in = '1' then
                        state_r <= ADDRCHECK;
                    end if;
                
                when ADDRCHECK =>
                    addr_v := unsigned(addr_r(6 downto 0));
                    if addr_v = 0 and pass_zero = '1' then
                        addr_ok_r <= '1';
                        state_r <= PASS_ADDR;
                    elsif addr_v >= unsigned(minaddr) and addr_v <= unsigned(maxaddr) then
                        addr_ok_r <= '1';
                        state_r <= PASS_ADDR;
                    else
                        addr_ok_r <= '0';
                        state_r <= DROP;
                    end if;
                
                when PASS_PID =>
                    data_out <= "0" & pid_r;
                    write_out <= '1';
                    state_r <= PASS_REST;
                
                when PASS_ADDR =>
                    data_out <= "0" & pid_r;
                    write_out <= '1';
                    state_r <= PASS_ADDR2;
                
                when PASS_ADDR2 =>
                    data_out <= "0" & addr_r;
                    write_out <= '1';
                    state_r <= PASS_REST;
                
                when PASS_REST =>
                    data_out <= data_in;
                    write_out <= write_in;
                
                when DROP =>
                    write_out <= '0';
            end case;
            
            -- Always back to PID state when packet ends
            if write_in = '1' and data_in(8) = '1' then
                state_r <= PID;
            end if;
        end if;
    end process;
end architecture;