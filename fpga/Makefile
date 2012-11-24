VHDL_SOURCE = config.vhdl edge_matcher.vhdl \
	fifo.vhdl usb_rx_phy.vhdl usb_decoder.vhdl \
	fpga_top.vhdl

all: syntax_check run_tbs

clean:
	rm *.o *.cf

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

run_tbs: tb_usb_decoder tb_fifo tb_edge_matcher
	./tb_usb_decoder
	./tb_fifo
	./tb_edge_matcher

