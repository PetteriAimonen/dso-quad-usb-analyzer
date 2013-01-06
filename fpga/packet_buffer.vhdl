-- Stores up to 4 packets for filtering purposes and allows comparison
-- operations on them. All operations are performed sequentially, typically
-- 1 clock cycle per byte.

package PacketBuffer_pkg is
    type BufferCommand is (
        IDLE,
        UPDATE_LEN, -- Internal state for command execution
        WRITE, -- Write out packet at position N and clear it.
        READ,  -- Read a new packet to position N
        FLUSH, -- Write out packet N and also input until EOP.
        DROP,  -- Drop packet at position N
        CMP,   -- Compare packet 0 to packet N
        SHIFT, -- Move packet 0 to N, 1 to N+1, etc.
        FLAGR  -- Set the repeat flag on packet N
    );
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.PacketBuffer_pkg.all;

entity PacketBuffer is
    generic (
        timeout_g:      natural := 72000000
    );
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
    subtype length_t is unsigned(6 downto 0);
    type length_array_t is array(0 to 3) of length_t;
    signal lengths_r:   length_array_t;

    -- Length of the packet given as argument to current command
    signal arglen_r:    length_t;
    signal tmplen_r:    length_t;
    
    -- Command interface
    signal cmd_r:       BufferCommand;
    signal arg_r:       unsigned(1 downto 0);
    signal status_r:    std_logic;
    
    -- State counter for command execution, increments every cycle.
    signal counter_r:   unsigned(8 downto 0);
    
    -- Temporary data for command execution
    signal temp_r:      std_logic_vector(7 downto 0);
    signal flag_r:      std_logic;
    signal flag2_r:     std_logic;
    signal flag_delay_r:std_logic;
    
    -- Packet shifting index
    signal shift_r:     unsigned(1 downto 0);
    
    -- Packet read timeout counter
    signal prescaler_r: unsigned(14 downto 0);
    constant timeout_c: integer := (timeout_g + 16383) / 16384;
    signal timeout_r:   integer range 0 to timeout_c;
    signal timeouted_r: std_logic;
    
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
        port map (clk, rst_n, fifo_out, fifo_read_r, fifo_valid,
            data_in, write_in, fifo_count);
    
    process (clk, rst_n)
    begin
        if rst_n = '0' then
            lengths_r <= (others => (others => '0'));
            arglen_r <= (others => '0');
            tmplen_r <= (others => '0');
            
            cmd_r <= IDLE;
            arg_r <= (others => '0');
            status_r <= '0';
            counter_r <= (others => '0');
            temp_r <= (others => '0');
            flag_r <= '0';
            flag_delay_r <= '0';
            flag2_r <= '0';
            shift_r <= (others => '0');
            
            fifo_read_r <= '0';
            
            timeout_r <= timeout_c;
            prescaler_r <= (others => '0');
            timeouted_r <= '0';
            
            ram_wdata <= (others => '0');
            ram_waddr <= (others => '0');
            ram_we <= '0';
            ram_raddr <= (others => '0');
            ram_re <= '0';
            
            data_out_r <= (others => '0');
            write_out_r <= '0';
            
        elsif rising_edge(clk) then
            counter_r <= counter_r + 1;
            flag_delay_r <= flag_r;
            prescaler_r <= prescaler_r + 1;
            
            if timeout_r /= 0 then
                if prescaler_r(14) = '1' then
                    prescaler_r(14) <= '0';
                    timeout_r <= timeout_r - 1;
                end if;
            else
                timeouted_r <= '1';
            end if;
            
            case cmd_r is
                when IDLE =>
                    data_out_r <= (others => '-');
                    write_out_r <= '0';
                    fifo_read_r <= '0';
                    ram_we <= '0';
                    ram_re <= '0';
                    ram_waddr <= (others => '-');
                    ram_wdata <= (others => '-');
                    ram_raddr <= (others => '-');
                    counter_r <= (others => '0');
                    temp_r <= (others => '0');
                    flag_r <= '0';
                    flag_delay_r <= '0';
                    flag2_r <= '0';
                    timeout_r <= timeout_c;
                    timeouted_r <= '0';
                    
                    cmd_r <= cmd;
                    arg_r <= unsigned(arg);
                    arglen_r <= lengths_r(to_integer(unsigned(arg)));
                    tmplen_r <= lengths_r(to_integer(unsigned(arg)));
                    
                when UPDATE_LEN =>
                    fifo_read_r <= '0';
                    write_out_r <= '0';
                    
                    -- Store modified packet length
                    lengths_r(to_integer(unsigned(arg_r))) <= arglen_r;
                    
                    cmd_r <= IDLE;
                
                when WRITE =>
                    ram_re <= '1';
                    ram_raddr(8 downto 7) <= std_logic_vector(arg_r + shift_r);
                    ram_raddr(6 downto 0) <= std_logic_vector(counter_r(6 downto 0));
                    
                    -- 2 cycle delay from RAM read to data available
                    if counter_r >= 2 then
                        write_out_r <= '1';
                        data_out_r <= "0" & ram_rdata;
                    end if;
                    
                    -- Detect end of packet early (to pipeline the cmp delay)
                    if counter_r(6 downto 0) = arglen_r then
                        flag_r <= '1';
                    end if;
                    
                    if flag_r = '1' then
                        data_out_r(8) <= '1'; -- EOP marker
                        arglen_r <= (others => '0');
                        cmd_r <= UPDATE_LEN;
                        if counter_r = 0 then
                            status_r <= '0'; -- Buffer was empty
                        else
                            status_r <= '1'; -- Wrote out packet
                        end if;
                    end if;
                
                when READ =>
                    assert counter_r /= 0 or arglen_r = 0
                        report "Overwriting packet!";
                    
                    -- There is 2 cycle delay from fifo_read to output update.
                    -- We pipeline so that new data is read every other cycle.
                    -- We can't pipeline deeper, because we need to detect
                    -- EOP before we read too far.
                    fifo_read_r <= '1';
                    ram_we <= '0';
                    if fifo_valid = '1' and fifo_read_r = '1' then
                        -- Store byte to RAM
                        fifo_read_r <= '0';
                        ram_we <= '1';
                        ram_waddr(8 downto 7) <= std_logic_vector(arg_r + shift_r);
                        ram_waddr(6 downto 0) <= std_logic_vector(arglen_r);
                        ram_wdata <= fifo_out(7 downto 0);
                        
                        flag2_r <= fifo_out(8);
                        arglen_r <= arglen_r + 1;
                        
                        if arglen_r = 126 then
                            -- Too long packet
                            cmd_r <= UPDATE_LEN;
                            status_r <= '0';
                        end if;
                    elsif flag2_r = '1' then
                        -- End of packet
                        fifo_read_r <= '0';
                        cmd_r <= UPDATE_LEN;
                        status_r <= '1';
                    elsif timeouted_r = '1' then
                        -- Timeout on read
                        cmd_r <= UPDATE_LEN;
                        status_r <= '0';
                    end if;
                
                when FLUSH =>
                    ram_re <= '1';
                    ram_raddr(8 downto 7) <= std_logic_vector(arg_r + shift_r);
                    ram_raddr(6 downto 0) <= std_logic_vector(counter_r(6 downto 0));
                    
                    if arglen_r = 0 then
                        -- No packet to flush
                        cmd_r <= IDLE;
                        status_r <= '0';
                    end if;
                    
                    -- 2 cycle delay from RAM read to data available
                    if counter_r >= 2 then
                        write_out_r <= '1';
                        data_out_r <= "0" & ram_rdata;
                    end if;
                    
                    if counter_r(6 downto 0) = arglen_r then
                        flag_r <= '1';
                    end if;
                    
                    if flag_delay_r = '1' then
                        -- Then pass through input until EOP.
                        fifo_read_r <= '1';
                        write_out_r <= '0';
                        data_out_r <= (others => '-');
                        
                        if fifo_valid = '1' and fifo_read_r = '1' then
                            flag2_r <= fifo_out(8);
                            fifo_read_r <= '0';
                            data_out_r <= fifo_out;
                            write_out_r <= '1';
                        elsif flag2_r = '1' then
                            -- End of packet
                            arglen_r <= (others => '0');
                            fifo_read_r <= '0';
                            cmd_r <= UPDATE_LEN;
                            status_r <= '1';
                        end if;
                    end if;
                
                when DROP =>
                    if arglen_r = 0 then
                        status_r <= '0'; -- No packet
                    else
                        status_r <= '1';
                    end if;
                    arglen_r <= (others => '0');
                    cmd_r <= UPDATE_LEN;
                
                when CMP =>
                    ram_re <= '1';
                    
                    if arglen_r /= lengths_r(0) then
                        -- Packet lengths differ
                        flag2_r <= '1';
                    end if;
                    
                    if counter_r(0) = '0' then
                        -- Read packet 0 byte
                        ram_raddr(8 downto 7) <= std_logic_vector(shift_r);
                    else
                        -- Read packet N byte
                        ram_raddr(8 downto 7) <= std_logic_vector(arg_r + shift_r);
                    end if;
                    ram_raddr(6 downto 0) <= std_logic_vector(counter_r(7 downto 1));
                    
                    if counter_r(0) = '1' then
                        tmplen_r <= tmplen_r - 1;
                    end if;
                    
                    if counter_r >= 2 then
                        temp_r <= ram_rdata xor temp_r;
                        
                        if tmplen_r <= 4 and tmplen_r > 0 then
                            -- Ignore differences in timestamp
                            temp_r <= (others => '0');
                        end if;
                        
                        if counter_r(0) = '0' then
                            -- Check results of previous compare
                            if temp_r /= X"00" then
                               -- Packet bytes don't match
                               flag2_r <= '1';
                            end if;
                        end if;
                    end if;
                    
                    if tmplen_r = 0 and counter_r(0) = '1' then
                        -- End of packet
                        flag_r <= '1';
                    end if;
                    
                    if flag2_r = '1' then
                        -- Packets are different
                        cmd_r <= IDLE;
                        status_r <= '0';
                    elsif flag_delay_r = '1' then
                        -- EOP is delayed so that comparison has finished
                        cmd_r <= IDLE;
                        status_r <= '1';
                    end if;
                
                when SHIFT =>
                    assert arg_r = "01" report "Only shifts by 1 supported";
                    lengths_r(0) <= lengths_r(3);
                    lengths_r(1) <= lengths_r(0);
                    lengths_r(2) <= lengths_r(1);
                    lengths_r(3) <= lengths_r(2);
                    shift_r <= shift_r - arg_r;
                    cmd_r <= IDLE;
                
                when FLAGR =>
                    ram_re <= '1';
                    ram_raddr(8 downto 7) <= std_logic_vector(arg_r + shift_r);
                    ram_raddr(6 downto 0) <= std_logic_vector(arglen_r - 1);
                    
                    -- 2 cycle delay for ram access
                    if counter_r(1) = '1' then
                        ram_we <= '1';
                        ram_waddr <= ram_raddr;
                        ram_wdata <= ram_rdata;
                        ram_wdata(2) <= '1'; -- Set repeat flag
                        cmd_r <= IDLE;
                    end if;
                
                when others =>
                    cmd_r <= IDLE;
            end case;
        end if;
    end process;
end architecture;
