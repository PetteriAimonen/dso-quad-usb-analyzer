-- Detects repeating packet sequences of lengths 1 or 2 and collapses them.
-- This saves buffer capacity and makes the packet traces easier to read.
--
-- The suppression of repeated packets is signalled by setting bit 2 in the
-- packet's EOP byte. The packet with the indicator is sent when the repeating
-- sequence starts. When the sequence ends, the last packet is let through.
--
-- To stop the last packet in a capture from getting stuck in the buffer,
-- the buffers are flushed after a given delay after receiving last packet.
--
-- This is not an easy task to implement in hardware, but fortunately we
-- have a lot of clock cycles to spare. New USB bytes arrive at most once
-- per 48 clock cycles.
--
-- The implementation consists of two parts: 1) a packet buffer, that takes
-- commands to read, write and compare packets, and 2) control logic written
-- similar to a computer program.
--
-- Pseudo-code:
--
-- --------------------
-- Main processing loop
-- 
--     0. Write out packet 0 (if any).
--     1. Read in packet 0.
--     2. If enable = 0, goto 0.
--     3. If too long or timeout, goto 60
--     4. Compare to 1
--     5. If equal, goto 20
--     6. Compare to 2
--     7. If equal, goto 40
--     8. Shift and goto 0
-- 
-- ---------------
-- Repeat length 1
-- The latest packet of the sequence is kept in buffer 1.
-- New packets go to buffer 0 and are compared to buffer 1.
-- 
-- Send marker for start of sequence    
--     20. Flag 1
--     21. Write out 3
--     22. Write out 2
--     23. Write out 1
-- 
-- Drop packets as long as they repeat
--     24. Shift
--     25. Read in packet 0.
--     26. If too long or timeout, goto 60
--     27. Compare to 1
--     28. If not equal, goto 8.
--     29. Drop 1, goto 24.
-- 
-- ---------------
-- Repeat length 2
-- The two latest packets of sequence are kept in 1 and 2.
-- New packets are compared to 2, which is then dropped and shifted.
-- 
-- Wait for next packet to verify that both packets of sequence repeat.
--     40. Shift
--     41. Write out 0
--     42. Read in packet 0.
--     43. If too long or timeout, goto 60
--     44. Compare to 2
--     45. If not equal, goto 3.
-- 
-- Send markers for start of sequence
--     46. Flag 2
--     47. Flag 3
--     48. Write out 3
--     49. Write out 2
-- 
-- Drop packets while they repeat.
--     50. Shift
--     51. Read in packet 0.
--     52. If too long or timeout, goto 60
--     53. Compare to 2
--     54. If not equal, goto 8.
--     55. Drop 2, goto 50.
-- 
-- ---------------------------------
-- Flushing when there is read error
-- 
--     60. Write out 3
--     61. Write out 2
--     62. Write out 1
--     63. Flush 0, goto 1.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.PacketBuffer_pkg.all;

entity RepeatFilter is
    generic (
        timeout_g:      natural := 72000000
    );
    port (
        clk:            in std_logic;
        rst_n:          in std_logic;

        -- Perform filtering?
        enable:         in std_logic;
        
        -- Data input.
        data_in:        in std_logic_vector(8 downto 0);
        write_in:       in std_logic;
        
        -- Data output
        data_out:       out std_logic_vector(8 downto 0);
        write_out:      out std_logic
    );
end entity;

architecture rtl of RepeatFilter is
    -- Current line in program
    signal line_r:              integer range 0 to 255;

    -- Signals for packet buffer
    signal cmd:                 BufferCommand;
    signal arg:                 std_logic_vector(1 downto 0);
    signal busy:                std_logic;
    signal status:              std_logic;
begin
    buf0: entity work.PacketBuffer
        generic map (timeout_g => timeout_g)
        port map (clk, rst_n, data_in, write_in, data_out, write_out, cmd, arg, busy, status);
    
    process (rst_n, clk) is
    begin
        if rst_n = '0' then
            line_r <= 0;
            cmd <= IDLE;
            arg <= "00";
        elsif rising_edge(clk) then
            cmd <= IDLE;
            
            if busy = '0' and cmd = IDLE then
                line_r <= line_r + 1;
                case line_r is
                    -- Main processing loop
                    when 0 => cmd <= WRITE; arg <= "00";
                    when 1 => cmd <= READ; arg <= "00";
                    when 2 => if enable = '0' then line_r <= 0; end if;
                    when 3 => if status = '0' then line_r <= 60; end if;
                    when 4 => cmd <= CMP; arg <= "01";
                    when 5 => if status = '1' then line_r <= 20; end if;
                    when 6 => cmd <= CMP; arg <= "10";
                    when 7 => if status = '1' then line_r <= 40; end if;
                    when 8 => cmd <= SHIFT; arg <= "01"; line_r <= 0;
                    
                    -- Repeat length 1
                    when 20 => cmd <= FLAGR; arg <= "01";
                    when 21 => cmd <= WRITE; arg <= "11";
                    when 22 => cmd <= WRITE; arg <= "10";
                    when 23 => cmd <= WRITE; arg <= "01";
                    when 24 => cmd <= SHIFT; arg <= "01";
                    when 25 => cmd <= READ; arg <= "00";
                    when 26 => if status = '0' then line_r <= 60; end if;
                    when 27 => cmd <= CMP; arg <= "01";
                    when 28 => if status = '0' then line_r <= 8; end if;
                    when 29 => cmd <= DROP; arg <= "01"; line_r <= 24;
                    
                    -- Repeat length 2
                    when 40 => cmd <= SHIFT; arg <= "01";
                    when 41 => cmd <= WRITE; arg <= "00";
                    when 42 => cmd <= READ; arg <= "00";
                    when 43 => if status = '0' then line_r <= 60; end if;
                    when 44 => cmd <= CMP; arg <= "10";
                    when 45 => if status = '0' then line_r <= 3; end if;
                    when 46 => cmd <= FLAGR; arg <= "10";
                    when 47 => cmd <= FLAGR; arg <= "11";
                    when 48 => cmd <= WRITE; arg <= "11";
                    when 49 => cmd <= WRITE; arg <= "10";
                    when 50 => cmd <= SHIFT; arg <= "01";
                    when 51 => cmd <= READ; arg <= "00";
                    when 52 => if status = '0' then line_r <= 60; end if;
                    when 53 => cmd <= CMP; arg <= "10";
                    when 54 => if status = '0' then line_r <= 8; end if;
                    when 55 => cmd <= DROP; arg <= "10"; line_r <= 50;
                    
                    -- Flush after read error
                    when 60 => cmd <= WRITE; arg <= "11";
                    when 61 => cmd <= WRITE; arg <= "10";
                    when 62 => cmd <= WRITE; arg <= "01";
                    when 63 => cmd <= FLUSH; arg <= "00"; line_r <= 1;
                    
                    when others =>
                end case;
            end if;
        end if;
    end process;
end architecture;