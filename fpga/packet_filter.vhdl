-- Filters USB packets based on the packet ID field.
-- Takes a bit array of filter masks.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity PacketFilter is
    port (
        clk:            in std_logic;
        rst_n:          in std_logic;

        -- '1' to block packet, '0' to allow it through
        filter:         in std_logic_vector(15 downto 0);
        
        -- Data input
        data_in:        in std_logic_vector(8 downto 0);
        write_in:       in std_logic;
        
        -- Data output
        data_out:       out std_logic_vector(8 downto 0);
        write_out:      out std_logic
    );
end entity;

architecture rtl of PacketFilter is
    -- When new = 1, the next write starts a new packet.
    -- When ignore = 1, the current packet should be ignored.
    signal new_r: std_logic;
    signal ignore_r:    std_logic;
    
    -- Registers for block outputs
    signal data_out_r:  std_logic_vector(8 downto 0);
    signal write_out_r: std_logic;
begin
    data_out <= data_out_r;
    write_out <= write_out_r;

    process (clk, rst_n)
        variable packet_id_v: unsigned(3 downto 0);
    begin
        if rst_n = '0' then
            data_out_r <= (others => '0');
            write_out_r <= '0';
            new_r <= '1';
            ignore_r <= '0';
        elsif rising_edge(clk) then
            data_out_r <= data_in;
        
            if write_in = '1' then
                if data_in(8) = '1' then
                    -- End of packet
                    write_out_r <= not ignore_r;
                    new_r <= '1';
                    ignore_r <= '0';
                elsif new_r = '1' then
                    -- Start of new packet
                    -- Filter only if packet id is valid
                    packet_id_v := unsigned(data_in(3 downto 0));
                    if (data_in(3 downto 0) = not data_in(7 downto 4)) and
                        (filter(to_integer(packet_id_v)) = '1') then
                        ignore_r <= '1';
                        write_out_r <= '0';
                    else
                        ignore_r <= '0';
                        write_out_r <= '1';
                    end if;
                    new_r <= '0';
                else
                    -- Packet contents
                    write_out_r <= not ignore_r;
                end if;
            else
                write_out_r <= '0';
            end if;
        end if;
    end process;
end architecture;