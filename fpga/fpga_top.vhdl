library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fpga_top is
    generic (
        fifo_depth_g:   natural := 8192
    );
    
    port (
        clk:      in     std_logic;
        rst_n:    in     std_logic;
        
        -- Memory bus
        fsmc_ce:  in     std_logic;
        fsmc_nwr: in     std_logic;
        fsmc_nrd: in     std_logic;
        fsmc_db:  inout  std_logic_vector(15 downto 0);
        
        -- ADC signals
        adc_sleep: out   std_logic;
        cha_clk:   out   std_logic;
        chb_clk:   out   std_logic;
        
        -- Oscilloscope data inputs
        cha_din:   in    std_logic_vector(7 downto 0);
        chb_din:   in    std_logic_vector(7 downto 0)
     );
end entity;

architecture rtl of fpga_top is
    -- Input channels before and after edge matching
    -- 1 = d+, 0 = d-
    signal ch_ab:               std_logic_vector(1 downto 0);
    signal ch_ab_matched:       std_logic_vector(1 downto 0);
    
    -- Configuration register signals
    signal cfg_read_count:      std_logic;
    
    -- USB decoder signals
    signal dec_data:            std_logic_vector(8 downto 0);
    signal dec_write:           std_logic;
    
    -- FIFO outputs
    signal fifo_data_out:       std_logic_vector(8 downto 0);
    signal fifo_count:          std_logic_vector(15 downto 0);
    signal fifo_read:           std_logic;
    
    -- Output data bus
    signal output_data:         std_logic_vector(15 downto 0);
    
    -- FSMC read signal (to detect edges)
    signal fsmc_was_read_r:     boolean;
    signal fsmc_nrd_edge:       std_logic;
begin
    -- ADC is clocked directly from 72 MHz output from the STM32
    adc_sleep <= '1';
    cha_clk <= clk;
    chb_clk <= clk;
    
    -- Configuration register
    config1: entity work.Config
        port map (clk, rst_n, fsmc_ce, fsmc_nwr, fsmc_db, 
            cfg_read_count);
    
    -- Binarization of ADC data.
    -- In 200mV range, din >= 128 gives 1 V threshold voltage
    -- Note: apparently these have to be inverted.
    ch_ab(0) <= not cha_din(7);
    ch_ab(1) <= not chb_din(7);
    
    -- Matching of edges
    em1: entity work.EdgeMatcher
        generic map (width_g => 2)
        port map (clk, rst_n, ch_ab, ch_ab_matched);
    
    -- USB signalling decoder
    dec1: entity work.USBDecoder
        port map (clk, rst_n,
            ch_ab_matched(1), ch_ab_matched(0), ch_ab_matched(1),
            dec_data, dec_write);
    
    -- FIFO storage of data
    fifo1: entity work.FIFO
        generic map (width_g => 9, depth_g => fifo_depth_g)
        port map (clk, rst_n, fifo_data_out, fifo_read,
            dec_data, dec_write, fifo_count);
    
    -- Remove values from FIFO on rising edge of fsmc_nrd
    process (clk, rst_n)
    begin
        if rst_n = '0' then
            fsmc_was_read_r <= false;
        elsif rising_edge(clk) then
            fsmc_was_read_r <= (fsmc_nrd = '0' and fsmc_ce = '1');
        end if;
    end process;
    fsmc_nrd_edge <= '1' when (fsmc_nrd = '1' and fsmc_was_read_r) else '0';
    
    -- Output either fifo data (if cfg_read_count = 0) or fifo count
    output_data <= "0000000" & fifo_data_out when (cfg_read_count = '0') else fifo_count;
    fifo_read <= fsmc_nrd_edge when (cfg_read_count = '0') else '0';
    
    -- FSMC bus control
    fsmc_db <= output_data
        when (fsmc_nrd = '0' and fsmc_ce = '1')
        else (others => 'Z');
end architecture;

