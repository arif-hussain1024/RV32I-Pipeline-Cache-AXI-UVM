## =============================================================================
## Vivado Constraints for Zedboard (Zynq XC7Z020)
## RISC-V SoC FPGA Prototyping
## =============================================================================

## Clock (100 MHz from Zynq PS or external oscillator)
create_clock -period 10.000 -name sys_clk [get_ports clk]

## Reset (active-low, directly mapped to button or PS)
set_property PACKAGE_PIN T18 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

## Test enable (directly tied low for FPGA)
## set_property PACKAGE_PIN ... [get_ports test_en]

## Clock uncertainty
set_clock_uncertainty 0.100 [get_clocks sys_clk]

## False paths on reset
set_false_path -from [get_ports rst_n]

## Input/output delay constraints for AXI interface
## (Adjust based on actual board routing)
set_input_delay -clock sys_clk -max 2.0 [get_ports {m_axi_*ready}]
set_input_delay -clock sys_clk -max 2.0 [get_ports {m_axi_rdata[*]}]
set_input_delay -clock sys_clk -max 2.0 [get_ports {m_axi_rresp[*]}]
set_input_delay -clock sys_clk -max 2.0 [get_ports {m_axi_rvalid}]
set_input_delay -clock sys_clk -max 2.0 [get_ports {m_axi_bresp[*]}]
set_input_delay -clock sys_clk -max 2.0 [get_ports {m_axi_bvalid}]

set_output_delay -clock sys_clk -max 2.0 [get_ports {m_axi_a*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {m_axi_w*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {m_axi_bready}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {m_axi_rready}]

## Area and timing optimization
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
