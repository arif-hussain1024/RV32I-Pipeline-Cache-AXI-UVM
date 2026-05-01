// =============================================================================
// RISC-V UVM Environment
// Integrates AXI agent, scoreboard, and functional coverage
// =============================================================================
class riscv_env extends uvm_env;
  `uvm_component_utils(riscv_env)

  axi4_lite_agent   axi_agent;
  riscv_scoreboard  scoreboard;
  riscv_coverage    coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    axi_agent  = axi4_lite_agent::type_id::create("axi_agent", this);
    scoreboard = riscv_scoreboard::type_id::create("scoreboard", this);
    coverage   = riscv_coverage::type_id::create("coverage", this);

    // Set agent as active (has driver + sequencer)
    uvm_config_db#(uvm_active_passive_enum)::set(this, "axi_agent", "is_active", UVM_ACTIVE);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect AXI monitor to scoreboard and coverage
    axi_agent.mon.ap.connect(scoreboard.axi_export);
    axi_agent.mon.ap.connect(coverage.analysis_export);
  endfunction

endclass
