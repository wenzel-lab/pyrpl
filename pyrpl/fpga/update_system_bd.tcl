################################################################################
# Vivado tcl script for building RedPitaya FPGA in non project mode
#
# Usage:
# vivado -mode tcl -source red_pitaya_vivado.tcl
################################################################################

################################################################################
# Initialize Vivado
################################################################################

set_param general.maxThreads 12

################################################################################
# define paths
################################################################################

set path_rtl rtl
set path_ip  ip
set path_sdc sdc

set path_out out
set path_sdk sdk

file mkdir $path_out
file mkdir $path_sdk

################################################################################
# setup an in memory project
################################################################################

set old_part xc7z010clg400-1
set new_part xc7z020clg400-1
set block_design $path_ip/bd/system.bd

create_project -in_memory -part $old_part
#create_project openfads ./openfads -part $part

# experimental attempts to avoid a warning
#get_projects
#get_designs
#list_property  [current_project]
#set_property FAMILY 7SERIES [current_project]
#set_property SIM_DEVICE 7SERIES [current_project]

add_files $block_design
open_bd_design [get_files $block_design]

# Set part to the 7020 after loading the 7010 system.bd
set_property part $new_part [current_project]
# report_ip_status -name ip_status

# Upgrade the ip and exchange it for the parts needed with 7020
upgrade_ip [get_ips  {system_proc_sys_reset_0 system_processing_system7_0 system_axi_protocol_converter_0_0 system_xlconstant_0 system_xadc_0}] -log ip_upgrade.log
validate_bd_design

## Write the updated system block design (bd)
# generate_target all $path_ip/system.bd

# export_ip_user_files -of_objects [get_ips {system_proc_sys_reset_0 system_processing_system7_0 system_axi_protocol_converter_0_0 system_xlconstant_0 system_xadc_0}] -no_script -sync -force -quiet

# Export the updated block design tcl file
write_bd_tcl -force $path_ip/system_bd_7020.tcl


exit

################################################################################
# create PS BD (processing system block design)
################################################################################

# # file was created from GUI using "write_bd_tcl -force ip/system_bd.tcl"
# # create PS BD
# source                            $path_ip/system_bd.tcl

# # generate SDK files
# generate_target all [get_files    system.bd]
# write_hwdef              -file    $path_sdk/red_pitaya.hwdef

# ################################################################################
# # read files:
# # 1. RTL design sources
# # 2. IP database files
# # 3. constraints
# ################################################################################

# # template
# #read_verilog                      $path_rtl/...

# read_verilog                      .gen/sources_1/bd/system/hdl/system_wrapper.v

# #exit

# read_verilog                      $path_rtl/axi_master.v
# read_verilog                      $path_rtl/axi_slave.v
# read_verilog                      $path_rtl/axi_wr_fifo.v

# read_verilog                      $path_rtl/red_pitaya_ams.v
# read_verilog                      $path_rtl/red_pitaya_asg_ch.v
# read_verilog                      $path_rtl/red_pitaya_asg.v
# read_verilog                      $path_rtl/red_pitaya_dfilt1.v
# read_verilog                      $path_rtl/red_pitaya_hk.v
# read_verilog                      $path_rtl/red_pitaya_pid_block.v
# read_verilog                      $path_rtl/red_pitaya_dsp.v
# read_verilog                      $path_rtl/red_pitaya_pll.sv
# read_verilog                      $path_rtl/red_pitaya_ps.v
# read_verilog                      $path_rtl/red_pitaya_pwm.sv
# read_verilog                      $path_rtl/red_pitaya_scope.v
# read_verilog                      $path_rtl/red_pitaya_top.v

# #custom modules
# read_verilog                      $path_rtl/red_pitaya_adv_trigger.v
# read_verilog                      $path_rtl/red_pitaya_saturate.v
# read_verilog                      $path_rtl/red_pitaya_product_sat.v
# read_verilog                      $path_rtl/red_pitaya_iir_block.v
# read_verilog                      $path_rtl/red_pitaya_iq_modulator_block.v
# read_verilog                      $path_rtl/red_pitaya_lpf_block.v
# read_verilog                      $path_rtl/red_pitaya_filter_block.v
# #read_verilog                     $path_rtl/red_pitaya_iq_lpf_block.v
# read_verilog                      $path_rtl/red_pitaya_iq_demodulator_block.v
# read_verilog                      $path_rtl/red_pitaya_pfd_block.v
# #read_verilog                     $path_rtl/red_pitaya_iq_hpf_block.v
# read_verilog                      $path_rtl/red_pitaya_iq_fgen_block.v
# read_verilog                      $path_rtl/red_pitaya_iq_block.v
# read_verilog                      $path_rtl/red_pitaya_trigger_block.v
# read_verilog                      $path_rtl/red_pitaya_prng.v
# read_verilog                      $path_rtl/red_pitaya_fads.sv
# read_verilog                      $path_rtl/red_pitaya_mux.v
# read_verilog                      $path_rtl/red_pitaya_clock_helpers.v

# #constraints
# read_xdc                          $path_sdc/red_pitaya.xdc

# ################################################################################
# # run synthesis
# # report utilization and timing estimates
# # write checkpoint design
# ################################################################################

# #synth_design -top red_pitaya_top
# synth_design -top red_pitaya_top -flatten_hierarchy none -bufg 16 -keep_equivalent_registers

# write_checkpoint         -force   $path_out/post_synth
# report_timing_summary    -file    $path_out/post_synth_timing_summary.rpt
# report_power             -file    $path_out/post_synth_power.rpt

# ################################################################################
# # run placement and logic optimization
# # report utilization and timing estimates
# # write checkpoint design
# ################################################################################

# opt_design
# power_opt_design
# report_utilization       -file    $path_out/pre_place_util.rpt
# place_design
# phys_opt_design
# write_checkpoint         -force   $path_out/post_place
# report_timing_summary    -file    $path_out/post_place_timing_summary.rpt
# #write_hwdef              -file    $path_sdk/red_pitaya.hwdef

# ################################################################################
# # run router
# # report actual utilization and timing,
# # write checkpoint design
# # run drc, write verilog and xdc out
# ################################################################################

# route_design
# write_checkpoint         -force   $path_out/post_route
# report_timing_summary    -file    $path_out/post_route_timing_summary.rpt
# report_timing            -file    $path_out/post_route_timing.rpt -sort_by group -max_paths 100 -path_type summary
# report_clock_utilization -file    $path_out/clock_util.rpt
# report_utilization       -file    $path_out/post_route_util.rpt
# report_power             -file    $path_out/post_route_power.rpt
# report_drc               -file    $path_out/post_imp_drc.rpt
# #write_verilog            -force   $path_out/bft_impl_netlist.v
# #write_xdc -no_fixed_only -force   $path_out/bft_impl.xdc

# ################################################################################
# # generate a bitstream
# ################################################################################

# set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
# write_bitstream -force $path_out/red_pitaya.bit

# ################################################################################
# # generate the .bin file for flashing via 'cat red_pitaya.bin > /dev/xdevcfg'
# ################################################################################

# set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
# write_bitstream -force $path_out/red_pitaya_uncompressed.bit
# write_cfgmem -force -format BIN -size 2 -interface SMAPx32 -disablebitswap -loadbit "up 0x0 $path_out/red_pitaya_uncompressed.bit" red_pitaya.bin

# ################################################################################
# # generate system definition
# ################################################################################

# # write_sysdef             -hwdef   $path_sdk/red_pitaya.hwdef \
# #                          -bitfile $path_out/red_pitaya.bit \
# #                          -file    $path_sdk/red_pitaya.sysdef

# exit
