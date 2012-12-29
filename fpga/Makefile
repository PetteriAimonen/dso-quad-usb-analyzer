VHDL_SOURCE = config.vhdl edge_matcher.vhdl config.vhdl \
	fifo.vhdl usb_rx_phy.vhdl usb_decoder.vhdl \
	packet_filter.vhdl fpga_top.vhdl

TESTS = tb_usb_decoder tb_fifo tb_edge_matcher tb_packet_filter tb_packet_buffer

all: syntax_check run_tbs

clean:
	rm *.o *.cf $(TESTS)

# ----- GHDL simulator -----

syntax_check: $(VHDL_SOURCE)
	ghdl -a $(GHDL_ARGS) $^

tb_usb_decoder: usb_rx_phy.vhdl usb_decoder.vhdl tb_usb_decoder.vhdl
	ghdl -a $(GHDL_ARGS) $^
	ghdl -e $(GHDL_ARGS) $@

tb_fifo: fifo.vhdl tb_fifo.vhdl
	ghdl -a $(GHDL_ARGS) $^
	ghdl -e $(GHDL_ARGS) $@

tb_edge_matcher: edge_matcher.vhdl tb_edge_matcher.vhdl
	ghdl -a $(GHDL_ARGS) $^
	ghdl -e $(GHDL_ARGS) $@

tb_packet_filter: packet_filter.vhdl tb_packet_filter.vhdl
	ghdl -a $(GHDL_ARGS) $^
	ghdl -e $(GHDL_ARGS) $@

tb_packet_buffer: fifo.vhdl ramblock.vhdl packet_buffer.vhdl tb_packet_buffer.vhdl
	ghdl -a $(GHDL_ARGS) $^
	ghdl -e $(GHDL_ARGS) $@

tb_repeat_filter: fifo.vhdl ramblock.vhdl packet_buffer.vhdl repeat_filter.vhdl \
                  std_logic_textio.vhdl tb_repeat_filter.vhdl
	ghdl -a $(GHDL_ARGS) $^
	ghdl -e $(GHDL_ARGS) $@

run_tbs: $(TESTS)
	./tb_usb_decoder
	./tb_fifo
	./tb_edge_matcher
	./tb_packet_filter
	./tb_packet_buffer
