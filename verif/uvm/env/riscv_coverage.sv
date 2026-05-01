// =============================================================================
// Functional Coverage Collector
// Covers: hazard types, cache hit/miss, branch outcomes, AXI transactions
// =============================================================================
class riscv_coverage extends uvm_subscriber #(axi4_lite_txn);
  `uvm_component_utils(riscv_coverage)

  // ---- Instruction type coverage ----
  logic [6:0] current_opcode;

  covergroup cg_instr_types;
    cp_opcode: coverpoint current_opcode {
      bins r_type   = {7'b0110011};
      bins i_alu    = {7'b0010011};
      bins load     = {7'b0000011};
      bins store    = {7'b0100011};
      bins branch   = {7'b1100011};
      bins jal      = {7'b1101111};
      bins jalr     = {7'b1100111};
      bins lui      = {7'b0110111};
      bins auipc    = {7'b0010111};
    }
  endgroup

  // ---- Hazard coverage ----
  logic is_raw_hazard;
  logic is_load_use;
  logic is_ex_fwd;
  logic is_mem_fwd;

  covergroup cg_hazards;
    cp_raw: coverpoint is_raw_hazard {
      bins no_hazard = {0};
      bins hazard    = {1};
    }
    cp_load_use: coverpoint is_load_use {
      bins no_stall = {0};
      bins stall    = {1};
    }
    cp_ex_fwd: coverpoint is_ex_fwd {
      bins no_fwd = {0};
      bins fwd    = {1};
    }
    cp_mem_fwd: coverpoint is_mem_fwd {
      bins no_fwd = {0};
      bins fwd    = {1};
    }
    // Cross coverage
    cx_hazard_type: cross cp_raw, cp_load_use;
  endgroup

  // ---- Cache coverage ----
  logic icache_hit;
  logic dcache_hit;
  logic dcache_writeback;

  covergroup cg_cache;
    cp_icache: coverpoint icache_hit {
      bins miss = {0};
      bins hit  = {1};
    }
    cp_dcache: coverpoint dcache_hit {
      bins miss = {0};
      bins hit  = {1};
    }
    cp_dcache_wb: coverpoint dcache_writeback {
      bins no_wb = {0};
      bins wb    = {1};
    }
  endgroup

  // ---- Branch coverage ----
  logic branch_taken;
  logic [2:0] branch_funct3;

  covergroup cg_branches;
    cp_taken: coverpoint branch_taken {
      bins not_taken = {0};
      bins taken     = {1};
    }
    cp_type: coverpoint branch_funct3 {
      bins beq  = {3'b000};
      bins bne  = {3'b001};
      bins blt  = {3'b100};
      bins bge  = {3'b101};
      bins bltu = {3'b110};
      bins bgeu = {3'b111};
    }
    cx_branch: cross cp_taken, cp_type;
  endgroup

  // ---- AXI transaction coverage ----
  covergroup cg_axi with function sample(axi4_lite_txn txn);
    cp_dir: coverpoint txn.is_write {
      bins read  = {0};
      bins write = {1};
    }
    cp_resp: coverpoint txn.resp {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_instr_types = new();
    cg_hazards     = new();
    cg_cache       = new();
    cg_branches    = new();
    cg_axi         = new();
  endfunction

  // Sample instruction coverage
  function void sample_instruction(logic [31:0] instr);
    current_opcode = instr[6:0];
    cg_instr_types.sample();
  endfunction

  // Sample hazard coverage
  function void sample_hazards(
    logic raw, logic load_use, logic ex_fwd, logic mem_fwd
  );
    is_raw_hazard = raw;
    is_load_use   = load_use;
    is_ex_fwd     = ex_fwd;
    is_mem_fwd    = mem_fwd;
    cg_hazards.sample();
  endfunction

  // Sample cache coverage
  function void sample_cache(logic i_hit, logic d_hit, logic d_wb);
    icache_hit       = i_hit;
    dcache_hit       = d_hit;
    dcache_writeback = d_wb;
    cg_cache.sample();
  endfunction

  // Sample branch coverage
  function void sample_branch(logic taken, logic [2:0] funct3);
    branch_taken  = taken;
    branch_funct3 = funct3;
    cg_branches.sample();
  endfunction

  // AXI transaction analysis
  function void write(axi4_lite_txn t);
    cg_axi.sample(t);
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf(
      "\n========== Coverage Report ==========\n" +
      "Instruction types: %.1f%%\n" +
      "Hazards:           %.1f%%\n" +
      "Cache:             %.1f%%\n" +
      "Branches:          %.1f%%\n" +
      "AXI:               %.1f%%\n" +
      "=====================================",
      cg_instr_types.get_coverage(),
      cg_hazards.get_coverage(),
      cg_cache.get_coverage(),
      cg_branches.get_coverage(),
      cg_axi.get_coverage()), UVM_LOW)
  endfunction

endclass
