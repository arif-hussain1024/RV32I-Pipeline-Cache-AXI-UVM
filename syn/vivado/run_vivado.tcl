# =============================================================================
# Vivado TCL Script - RISC-V SoC FPGA Synthesis
# Target: Zedboard (Zynq XC7Z020-CLG484-1)
# =============================================================================

# Project setup
set proj_name "riscv_soc_fpga"
set proj_dir  "./vivado_project"
set part      "xc7z020clg484-1"

# Create project
create_project $proj_name $proj_dir -part $part -force

# Add RTL source files
set rtl_files [list \
  "../../rtl/core/riscv_pkg.sv" \
  "../../rtl/core/program_counter.sv" \
  "../../rtl/core/register_file.sv" \
  "../../rtl/core/decoder.sv" \
  "../../rtl/core/alu.sv" \
  "../../rtl/core/branch_unit.sv" \
  "../../rtl/core/hazard_unit.sv" \
  "../../rtl/core/riscv_core.sv" \
  "../../rtl/cache/icache.sv" \
  "../../rtl/cache/dcache.sv" \
  "../../rtl/bus/axi4_lite_master.sv" \
  "../../rtl/clock_gating/clock_gating.sv" \
  "../../rtl/top/riscv_soc_top.sv" \
]

foreach f $rtl_files {
  add_files -norecurse $f
}

# Add constraints
add_files -fileset constrs_1 -norecurse "../../syn/vivado/constraints.xdc"

# Set top module
set_property top riscv_soc_top [current_fileset]

# Update compile order
update_compile_order -fileset sources_1

# =============================================================================
# Synthesis
# =============================================================================
puts "=== Starting Synthesis ==="

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]

launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis status
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
  puts "ERROR: Synthesis failed!"
  exit 1
}

# Open synthesized design for reports
open_run synth_1 -name synth_1

# Reports
report_utilization -file "$proj_dir/reports/utilization_synth.rpt"
report_timing_summary -file "$proj_dir/reports/timing_synth.rpt"
report_power -file "$proj_dir/reports/power_synth.rpt"
report_clock_utilization -file "$proj_dir/reports/clock_util.rpt"

# =============================================================================
# Implementation
# =============================================================================
puts "=== Starting Implementation ==="

set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
  puts "ERROR: Implementation failed!"
  exit 1
}

# Post-implementation reports
open_run impl_1
report_utilization -file "$proj_dir/reports/utilization_impl.rpt"
report_timing_summary -file "$proj_dir/reports/timing_impl.rpt"
report_power -file "$proj_dir/reports/power_impl.rpt"
report_drc -file "$proj_dir/reports/drc.rpt"

# =============================================================================
# Comparison Report (for clock gating analysis)
# =============================================================================
puts ""
puts "========================================"
puts "  Synthesis & Implementation Complete"
puts "========================================"
puts "Reports saved to: $proj_dir/reports/"
puts ""
puts "To compare power with/without clock gating:"
puts "  1. Synthesize with clock gating (current)"
puts "  2. Modify riscv_soc_top to bypass clock_gating_ctrl"
puts "  3. Synthesize again and compare power reports"
puts "========================================"

exit
