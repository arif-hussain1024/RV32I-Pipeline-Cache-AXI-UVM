# =============================================================================
# OpenSTA Static Timing Analysis Script
# Target: SKY130 standard cell library
# =============================================================================

# Read liberty file (update path to your SKY130 installation)
# read_liberty /path/to/sky130_fd_sc_hd__tt_025C_1v80.lib
# For demo, use a placeholder:
# read_liberty $env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# Read synthesized netlist
read_verilog syn/yosys/riscv_soc_synth.v

# Link design
link_design riscv_soc_top

# Define clock (100 MHz = 10ns period)
create_clock -name clk -period 10.0 [get_ports clk]

# Set clock uncertainty
set_clock_uncertainty 0.25 [get_clocks clk]

# Input/output delays
set_input_delay -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]

# Don't time reset path
set_false_path -from [get_ports rst_n]

# =============================================================================
# Timing Reports
# =============================================================================

# Setup timing (worst negative slack)
report_checks -path_delay max -sort_by_slack \
  -format full_clock_expanded \
  -fields {slew cap input_pins nets fanout} \
  -digits 4 \
  > syn/yosys/timing_setup.rpt

# Hold timing
report_checks -path_delay min -sort_by_slack \
  -format full_clock_expanded \
  -fields {slew cap input_pins nets fanout} \
  -digits 4 \
  > syn/yosys/timing_hold.rpt

# Top 20 critical paths
report_checks -path_delay max -sort_by_slack \
  -group_count 20 \
  -endpoint_count 20 \
  > syn/yosys/timing_critical_paths.rpt

# Worst slack summary
report_worst_slack -max
report_worst_slack -min

# Clock skew
report_clock_skew

# Design statistics
report_design_area
report_power

puts "========================================="
puts "STA Complete. Reports in syn/yosys/"
puts "========================================="

exit
