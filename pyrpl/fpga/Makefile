#######################################
#
# Authors: Matej Oblak, Iztok Jeras
# (C) Red Pitaya 2013-2015
#
# Red Pitaya FPGA/SoC Makefile 
#

# build results
FPGA_BIN=out/red_pitaya.bin

FPGA_BD=ip/system_bd.tcl

#logfile for stdout and stderr
LOG=2>&1 | tee -a fpga.log

# Vivado from Xilinx provides IP handling, FPGA compilation
# hsi (hardware software interface) provides software integration
# both tools are run in batch mode with an option to avoid log/journal files
# VIVADO = vivado -nolog -nojournal -mode batch
VIVADO = /opt/Xilinx/Vivado/2023.2/bin/vivado -nolog -mode batch
VIVADO_SETTINGS = /opt/Xilinx/Vivado/2023.2/settings64.sh 

# all: clean $(FPGA_BD) $(FPGA_BIN) postclean_keeplog
all: clean $(FPGA_BIN)
# all: clean $(FPGA_BD) postclean_keeplog

debug: clean $(FPGA_BIN)

clean:
	rm -rf out .Xil .srcs sdk ip/bd/ip ip/system

settings:
	$(VIVADO_SETTINGS)

# $(FPGA_BD):
# 	$(VIVADO) -source update_system_bd.tcl $(LOG)
# 	mv NA/ps7_summary.html ip/ps7_summary_7020.html
# 	rmdir NA
# 	git restore ip/bd/system.bd

$(FPGA_BIN):
	$(VIVADO) -source red_pitaya_vivado.tcl $(LOG)

postclean:
	# mv *.xml out/
	mv *.jou out/
	mv *.prm out/
	# mv *.html out/
	mv *.log out/
	mv clockinfo.txt out/
	mv tight_setup_hold_pins.txt out/

postclean_keeplog:
	# mv *.xml out/
	mv *.jou out/
	mv *.prm out/
	# mv *.html out/
	mv clockInfo.txt out/
	mv tight_setup_hold_pins.txt out/
