-- Stores up to 4 packets for filtering purposes and allows comparison
-- operations on them. All operations are performed sequentially, typically
-- 1 clock cycle per byte.

package PacketBuffer_pkg is
    type BufferCommand is (
        IDLE,
        WRITE, -- Write out packet at position N and clear it.
        READ,  -- Read a new packet to position N
        FLUSH, -- Write out packet N and also input until EOP.
        DROP,  -- Drop packet at position N
        CMP,   -- Compare packet 0 to packet N
        SHIFT, -- Move packet 0 to 1, 1 to 2, 2 to 3, 3 to 0.
        FLAGR  -- Set the repeat flag on packet N
    );
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.PacketBuffer_pkg.all;

entity PacketBuffer is
    port (
        clk:            in std_logic;
        rst_n:          in std_logic;

        -- Data input
        data_in:        in std_logic_vector(8 downto 0);
        write_in:       in std_logic;
        
        -- Data output
        data_out:       out std_logic_vector(8 downto 0);
        write_out:      out std_logic;
        
        -- Command interface
        cmd:            in BufferCommand;
        arg:            in std_logic_vector(1 downto 0);
        busy:           out std_logic; -- Command still running
        status:         out std_logic  -- Status of last finished command
    );
end entity;

architecture rtl of PacketBuffer is
    -- Storage of packet lengths
    subtype length_t is unsigned(7 downto 0);
    type length_array_t is array(0 to 3) of length_t;
    signal lengths_r:   length_array_t;

    -- Command interface
    signal cmd_r:       BufferCommand;
    signal arg_r:       unsigned(1 downto 0);
    signal status_r:    std_logic;
    
    -- State counter for command execution, increments every cycle.
    signal counter_r:   unsigned(11 downto 0);
    
    -- Packet shifting index
    signal shift_r:     unsigned(1 downto 0);
    
    -- Packet output interface
    signal data_out_r:  std_logic_vector(8 downto 0);
    signal write_out_r: std_logic;
    
    -- Signals from input FIFO block.
    signal fifo_out:    std_logic_vector(8 downto 0);
    signal fifo_count:  std_logic_vector(15 downto 0);
    signal fifo_valid:  std_logic;
    signal fifo_read_r: std_logic;
    
    -- Signals for RAM block
    signal ram_wdata:   std_logic_vector(7 downto 0);
    signal ram_waddr:   std_logic_vector(8 downto 0);
    signal ram_we:      std_logic;
    signal ram_rdata:   std_logic_vector(7 downto 0);
    signal ram_raddr:   std_logic_vector(8 downto 0);
    signal ram_re:      std_logic;
begin
    busy <= '0' when cmd_r = IDLE else '1';
    status <= status_r;
    data_out <= data_out_r;
    write_out <= write_out_r;

    -- RAM block for storage of packets
    ram0: entity work.RAMBlock
        generic map (width_g => 8, addr_g => 9)
        port map (clk, ram_wdata, ram_waddr, ram_we, ram_rdata, ram_raddr, ram_re);

    -- FIFO for input data.
    -- We block the input at some points, so this fifo will buffer
    -- the data that arrives in the mean time. On iCE65, the smallest
    -- memory block is 256 x 16. This is more than enough for our
    -- needs.
    input_fifo: entity work.FIFO
        generic map (width_g => 9, depth_g => 256)
        port map (clk, rst_n, fifo_out, fifo_read_r,
            data_in, write_in, fifo_count);
    fifo_valid <= '1' when (fifo_count /= X"0000") else '0';
    
    process (clk)
        variable argidx_v : integer range 0 to 3;
        variable arglen_v : unsigned(7 downto 0);
    begin
        argidx_v := to_integer(arg_r + shift_r);
        arglen_v := lengths_r(argidx_v);
    
        if rst_n = '0' then
            lengths_r <= (others => (others => '0'));
            
            cmd_r <= IDLE;
            arg_r <= (others => '0');
            status_r <= '0';
            counter_r <= (others => '0');
            shift_r <= (others => '0');
            
            fifo_read_r <= '0';
            
            ram_wdata <= (others => '0');
            ram_waddr <= (others => '0');
            ram_we <= '0';
            ram_raddr <= (others => '0');
            ram_re <= '0';
            
            data_out_r <= (others => '0');
            write_out_r <= '0';
            
        elsif rising_edge(clk) then
            counter_r <= counter_r + 1;
            
            case cmd_r is
                when IDLE =>
                    data_out_r <= (others => '-');
                    write_out_r <= '0';
                    fifo_read_r <= '0';
                    cmd_r <= cmd;
                    arg_r <= unsigned(arg);
                    counter_r <= (others => '0');
                
                    ram_we <= '0';
                    ram_re <= '0';
                    ram_waddr <= (others => '-');
                    ram_wdata <= (others => '-');
                    ram_raddr <= (others => '-');
                
                when WRITE =>
                    ram_re <= '1';
                    ram_raddr(8 downto 7) <= std_logic_vector(arg_r + shift_r);
                    ram_raddr(6 downto 0) <= std_logic_vector(counter_r(6 downto 0));
                    
                    -- 2 cycle delay from RAM read to data available
                    if counter_r >= 2 then
                        write_out_r <= '1';
                        data_out_r <= "0" & ram_rdata;
                    end if;
                    
                    if counter_r = arglen_v + 1 then
                        data_out_r(8) <= '1'; -- EOP marker
                        arglen_v := (others => '0');
                        cmd_r <= IDLE;
                        if counter_r = 0 then
                            status_r <= '0'; -- Buffer was empty
                        else
                            status_r <= '1'; -- Wrote out packet
                        end if;
                    end if;
                
                when READ =>
                    if counter_r = 0 then
                        assert arglen_v = 0 report "Overwriting packet!";
                    end if;
                    
                    fifo_read_r <= '1';
                    
                    -- There is 2 cycle delay from fifo_read to output update.
                    if fifo_valid = '1' and counter_r >= 2 then
                        -- Store byte to RAM
                        ram_we <= '1';
                        ram_waddr(8 downto 7) <= std_logic_vector(arg_r + shift_r);
                        ram_waddr(6 downto 0) <= std_logic_vector(arglen_v(6 downto 0));
                        ram_wdata <= fifo_out(7 downto 0);
                        
                        arglen_v := arglen_v + 1;
                        
                        if fifo_out(8) = '1' then
                            -- End of packet
                            cmd_r <= IDLE;
                            status_r <= '1';
                        end if;
                    else
                        -- Wait for data
                        ram_we <= '0';
                    end if;
                    
                when others =>
                    cmd_r <= IDLE;
            end case;
            
            lengths_r(argidx_v) <= arglen_v;
        end if;
    end process;
end architecture;
