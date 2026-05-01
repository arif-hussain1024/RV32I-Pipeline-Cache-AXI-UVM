#!/bin/bash
# =============================================================================
# Simulation Runner Script
# Supports: basic testbench, UVM tests, regression with multiple seeds
# =============================================================================

set -e

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RTL_DIR="$PROJ_DIR/rtl"
VERIF_DIR="$PROJ_DIR/verif"
SIM_DIR="$PROJ_DIR/sim"

# RTL file list
RTL_FILES=(
  "$RTL_DIR/core/riscv_pkg.sv"
  "$RTL_DIR/core/program_counter.sv"
  "$RTL_DIR/core/register_file.sv"
  "$RTL_DIR/core/decoder.sv"
  "$RTL_DIR/core/alu.sv"
  "$RTL_DIR/core/branch_unit.sv"
  "$RTL_DIR/core/hazard_unit.sv"
  "$RTL_DIR/core/riscv_core.sv"
  "$RTL_DIR/cache/icache.sv"
  "$RTL_DIR/cache/dcache.sv"
  "$RTL_DIR/bus/axi4_lite_master.sv"
  "$RTL_DIR/clock_gating/clock_gating.sv"
  "$RTL_DIR/top/riscv_soc_top.sv"
)

# UVM verification files
UVM_FILES=(
  "$VERIF_DIR/uvm/agents/axi4_lite_if.sv"
  "$VERIF_DIR/uvm/agents/axi4_lite_txn.sv"
  "$VERIF_DIR/uvm/agents/axi4_lite_driver.sv"
  "$VERIF_DIR/uvm/agents/axi4_lite_monitor.sv"
  "$VERIF_DIR/uvm/agents/axi4_lite_agent.sv"
  "$VERIF_DIR/uvm/scoreboards/riscv_scoreboard.sv"
  "$VERIF_DIR/uvm/sequences/riscv_sequences.sv"
  "$VERIF_DIR/uvm/env/riscv_coverage.sv"
  "$VERIF_DIR/uvm/env/riscv_env.sv"
  "$VERIF_DIR/uvm/tests/riscv_tests.sv"
  "$VERIF_DIR/sva/riscv_sva.sv"
  "$VERIF_DIR/tb/tb_top.sv"
)

usage() {
  echo "Usage: $0 [command] [options]"
  echo ""
  echo "Commands:"
  echo "  basic              Run basic (non-UVM) testbench"
  echo "  uvm <test_name>    Run UVM test (riscv_random_test, riscv_hazard_test, etc.)"
  echo "  regression         Run regression with multiple seeds"
  echo "  synth              Run Yosys synthesis"
  echo "  clean              Remove simulation artifacts"
  echo ""
  echo "Options:"
  echo "  --seed <N>         Set random seed (default: random)"
  echo "  --waves            Enable waveform dump"
  echo "  --gui              Open waveform viewer after simulation"
}

run_basic() {
  echo "=== Running Basic Testbench ==="
  mkdir -p "$SIM_DIR/basic"
  cd "$SIM_DIR/basic"

  # Using VCS (substitute with your simulator)
  echo "Compiling..."
  echo "vcs -sverilog -full64 -debug_access+all ${RTL_FILES[@]} $VERIF_DIR/tb/tb_basic.sv -o simv"
  echo ""
  echo "Running..."
  echo "./simv"
  echo ""
  echo "NOTE: Replace echo commands with actual simulator invocation"
  echo "For Icarus: iverilog -g2012 -o sim ${RTL_FILES[@]} $VERIF_DIR/tb/tb_basic.sv && vvp sim"
}

run_uvm() {
  local test_name=${1:-riscv_random_test}
  local seed=${2:-$RANDOM}

  echo "=== Running UVM Test: $test_name (seed: $seed) ==="
  mkdir -p "$SIM_DIR/uvm"
  cd "$SIM_DIR/uvm"

  echo "Compile command (VCS):"
  echo "vcs -sverilog -full64 -debug_access+all -ntb_opts uvm \\"
  echo "    ${RTL_FILES[@]} ${UVM_FILES[@]} \\"
  echo "    +UVM_TESTNAME=$test_name +ntb_random_seed=$seed -o simv"
  echo ""
  echo "Run command:"
  echo "./simv +UVM_TESTNAME=$test_name +ntb_random_seed=$seed"
}

run_regression() {
  local seeds=(12345 67890 11111 22222 33333 44444 55555 99999 13579 24680)

  echo "=== Running Regression Suite ==="
  echo "Tests: riscv_random_test, riscv_hazard_test"
  echo "Seeds: ${seeds[@]}"
  echo ""

  for test in riscv_random_test riscv_hazard_test riscv_regression_test; do
    for seed in "${seeds[@]}"; do
      echo "--- $test (seed=$seed) ---"
      run_uvm "$test" "$seed"
      echo ""
    done
  done
}

run_synth() {
  echo "=== Running Yosys Synthesis ==="
  cd "$PROJ_DIR"
  echo "yosys -s syn/yosys/synth.ys"
  echo ""
  echo "For SKY130 flow:"
  echo "1. Install SKY130 PDK: pip install volare && volare enable --pdk sky130 -h $(volare latest)"
  echo "2. Update synth.ys with correct liberty file path"
  echo "3. Run: yosys -s syn/yosys/synth.ys"
  echo "4. Run OpenSTA for timing: sta syn/yosys/timing.tcl"
}

# Parse arguments
case "${1:-}" in
  basic)      run_basic ;;
  uvm)        run_uvm "$2" "$3" ;;
  regression) run_regression ;;
  synth)      run_synth ;;
  clean)      rm -rf "$SIM_DIR"; echo "Cleaned." ;;
  *)          usage ;;
esac
