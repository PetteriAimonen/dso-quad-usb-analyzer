-- This is a configuration register for setting operation mode.
--
-- The top 2 bits select the register:
-- 00: Main config
-- 01: Addr filter min & max address
--
-- Main configuration bits:
--  0: Read FIFO data (0) or FIFO count (1)
--  1: Enable USB decoder
--  2: Enable repeat filter
--  3: Always let addr 0 through in addrfilt
--  4: Follow newest device for addrfilt
--  8: Ignore SOF packets
--  9: Ignore PRE packets

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
        cfg_enable:     out std_logic;
        cfg_rfilter:    out std_logic;
        cfg_passzero:   out std_logic;
        cfg_followaddr: out std_logic;
        cfg_ign_SOF:    out std_logic;
        cfg_ign_PRE:    out std_logic;
        
        cfg_minaddr:    out std_logic_vector(6 downto 0);
        cfg_maxaddr:    out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of Config is
    signal config_r:    std_logic_vector(13 downto 0);
    signal minaddr_r:   std_logic_vector(6 downto 0);
    signal maxaddr_r:   std_logic_vector(6 downto 0);
begin
    cfg_read_count <= config_r(0);
    cfg_enable <= config_r(1);
    cfg_rfilter <= config_r(2);
    cfg_passzero <= config_r(3);
    cfg_followaddr <= config_r(4);
    cfg_ign_SOF <= config_r(8);
    cfg_ign_PRE <= config_r(9);
    cfg_minaddr <= minaddr_r;
    cfg_maxaddr <= maxaddr_r;
    
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            config_r <= (others => '0');
            minaddr_r <= (others => '0');
            maxaddr_r <= (others => '1');
        elsif rising_edge(clk) then
            if fsmc_ce = '1' and fsmc_nwr = '0' then
                if fsmc_db(15 downto 14) = "00" then
                    config_r <= fsmc_db(13 downto 0);
                elsif fsmc_db(15 downto 14) = "01" then
                    minaddr_r <= fsmc_db(6 downto 0);
                    maxaddr_r <= fsmc_db(13 downto 7);
                end if;
            end if;
        end if;
    end process;
end architecture;