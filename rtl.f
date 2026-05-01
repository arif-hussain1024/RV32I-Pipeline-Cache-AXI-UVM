// =============================================================================
// File List: RTL Sources
// Usage: vcs -f rtl.f  or  xrun -f rtl.f
// =============================================================================

// Package (must be compiled first)
rtl/core/riscv_pkg.sv

// Core pipeline modules
rtl/core/program_counter.sv
rtl/core/register_file.sv
rtl/core/decoder.sv
rtl/core/alu.sv
rtl/core/branch_unit.sv
rtl/core/hazard_unit.sv
rtl/core/riscv_core.sv

// Cache subsystem
rtl/cache/icache.sv
rtl/cache/dcache.sv

// Bus interface
rtl/bus/axi4_lite_master.sv

// Clock gating
rtl/clock_gating/clock_gating.sv

// Top level
rtl/top/riscv_soc_top.sv
