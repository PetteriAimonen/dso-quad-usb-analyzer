-- This is a 16-bit configuration register for setting operation mode.
--
-- Configuration register bits:
--  0: Read FIFO data (0) or FIFO count (1)
--  8: Ignore SOF tokens
--  9: Ignore IN tokens
-- 10: Ignore OUT tokens
-- 11: Ignore PRE packets
-- 12: Ignore ACK packets
-- 13: Ignore NAK packets

library ieee;
use ieee.std_logic_1164.all;

entity Config is
    port (
        clk:            in std_logic;
        rst_n:          in std_logic;

        fsmc_ce:        in std_logic;
        fsmc_nwr:       in std_logic;
        fsmc_db:        in std_logic_vector(15 downto 0);

        cfg_read_count: out std_logic;
        cfg_ign_SOF:    out std_logic;
        cfg_ign_IN:     out std_logic;
        cfg_ign_OUT:    out std_logic;
        cfg_ign_PRE:    out std_logic;
        cfg_ign_ACK:    out std_logic;
        cfg_ign_NAK:    out std_logic
    );
end entity;

architecture rtl of Config is
    signal config_r: std_logic_vector(15 downto 0);
begin
    cfg_read_count <= config_r(0);
    cfg_ign_SOF <= config_r(8);
    cfg_ign_IN  <= config_r(9);
    cfg_ign_OUT <= config_r(10);
    cfg_ign_PRE <= config_r(11);
    cfg_ign_ACK <= config_r(12);
    cfg_ign_NAK <= config_r(13);
    
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            config_r <= (others => '0');
        elsif rising_edge(clk) then
            if fsmc_ce = '1' and fsmc_nwr = '0' then
                config_r <= fsmc_db;
            end if;
        end if;
    end process;
end architecture;