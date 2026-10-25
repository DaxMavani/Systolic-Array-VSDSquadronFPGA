# ============================================================
# Makefile — 4x4 Systolic Array on VSDSquadron FM
# ============================================================

TOP= fpga_top
PCF_FILE= VSDSquadronFM
BOARD_FREQ= 12
CPU_FREQ= 12
FPGA_VARIANT= up5k
FPGA_PACKAGE= sg48

VERILOG_SRCS= processing_element_yo.sv \
                 pe_array_yo.sv \
                 weight_loader_yo.sv \
                 activation_skew_yo.sv \
                 output_collector_yo.sv \
                 controller_yo.sv \
                 systolic_array_top_yo.sv \
                 uart_tx.v \
                 uart_rx.v \
                 fpga_top.sv

PICO_DEVICE= /dev/ttyUSB0
BAUDS= 115200

.PHONY: all build flash time clean terminal

all: build

# ------------------------------------------------------------
build: $(TOP).bin

$(TOP).json: $(VERILOG_SRCS)
	yosys -DCPU_FREQ=$(CPU_FREQ) -q -p " \
		read_verilog -sv $(VERILOG_SRCS); \
		synth_ice40 -abc9 -device u -top $(TOP) -json $(TOP).json"

$(TOP).asc: $(TOP).json $(PCF_FILE).pcf
	nextpnr-ice40 --force \
		--json $(TOP).json \
		--pcf $(PCF_FILE).pcf \
		--asc $(TOP).asc \
		--freq $(BOARD_FREQ) \
		--$(FPGA_VARIANT) \
		--package $(FPGA_PACKAGE) \
		--opt-timing

$(TOP).timings: $(TOP).asc $(PCF_FILE).pcf
	icetime -p $(PCF_FILE).pcf \
		-P $(FPGA_PACKAGE) \
		-r $(TOP).timings \
		-d $(FPGA_VARIANT) \
		-t $(TOP).asc

$(TOP).bin: $(TOP).asc
	icepack -s $(TOP).asc $(TOP).bin

# ------------------------------------------------------------
flash: $(TOP).bin
	iceprog $(TOP).bin

time: $(TOP).timings
	@cat $(TOP).timings

clean:
	rm -f $(TOP).json $(TOP).asc $(TOP).bin $(TOP).timings
	rm -f *.log

terminal:
	sudo picocom -b $(BAUDS) $(PICO_DEVICE) \
		--imap lfcrlf,crcrlf \
		--omap delbs,crlf \
		--send-cmd "ascii-xfr -s -l 30 -n"

