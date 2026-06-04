// =============================================================================
// UVM Test Classes
// Tests preload instruction programs into the AXI driver's memory
// so the processor can fetch and execute them.
// =============================================================================

// Base test with helper functions
class riscv_base_test extends uvm_test;
  `uvm_component_utils(riscv_base_test)

  riscv_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = riscv_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  // Helper: preload a single instruction into driver memory
  function void preload_instr(int addr, logic [31:0] instr);
    env.axi_agent.drv.preload(addr, instr);
    // Also preload into scoreboard reference memory
    env.scoreboard.ref_memory[addr] = instr;
  endfunction

  // Helper: preload a program array starting at address 0
  function void preload_program(logic [31:0] program_mem[$]);
    for (int i = 0; i < program_mem.size(); i++) begin
      preload_instr(i * 4, program_mem[i]);
    end
    `uvm_info("TEST", $sformatf("Preloaded %0d instructions into memory", program_mem.size()), UVM_LOW)
  endfunction

  // Helper: generate the basic test program (same as tb_basic)
  function void gen_basic_program(ref logic [31:0] prog[$]);
    prog.push_back(32'h00A00093);  // ADDI x1, x0, 10       -> x1 = 10
    prog.push_back(32'h01400113);  // ADDI x2, x0, 20       -> x2 = 20
    prog.push_back(32'h002081B3);  // ADD  x3, x1, x2       -> x3 = 30
    prog.push_back(32'h40118233);  // SUB  x4, x3, x1       -> x4 = 20
    prog.push_back(32'h00302023);  // SW   x3, 0(x0)        -> MEM[0] = 30
    prog.push_back(32'h00002283);  // LW   x5, 0(x0)        -> x5 = 30
    prog.push_back(32'h00128333);  // ADD  x6, x5, x1       -> x6 = 40
    prog.push_back(32'h01E00393);  // ADDI x7, x0, 30       -> x7 = 30
    prog.push_back(32'h00728463);  // BEQ  x5, x7, +8       -> taken
    prog.push_back(32'h06300413);  // ADDI x8, x0, 99       -> flushed
    prog.push_back(32'h02A00493);  // ADDI x9, x0, 42       -> x9 = 42
    prog.push_back(32'hDEADB537);  // LUI  x10, 0xDEADB     -> x10 = 0xDEADB000
    prog.push_back(32'h0EF50513);  // ADDI x10, x10, 0xEF   -> x10 = 0xDEADB0EF
  endfunction

  // Helper: generate random ALU and memory instructions
  function void gen_random_program(ref logic [31:0] prog[$], input int count);
    logic [31:0] instr;
    logic [4:0] rd, rs1, rs2;
    logic [11:0] imm;

    // Initialize registers with useful values first
    prog.push_back({20'h00001, 5'd8, 7'b0110111});    // LUI x8, 0x1000 (base addr)
    for (int i = 1; i <= 7; i++) begin
      imm = $urandom_range(1, 100);
      prog.push_back({imm, 5'd0, 3'b000, i[4:0], 7'b0010011});  // ADDI xi, x0, imm
    end

    // Random instructions
    for (int i = 0; i < count; i++) begin
      int itype;
      rd  = $urandom_range(1, 15);
      rs1 = $urandom_range(1, 7);   // Bias to low regs for hazards
      rs2 = $urandom_range(1, 7);
      imm = $urandom_range(0, 63);

      itype = $urandom_range(0, 9);
      case (itype)
        0, 1, 2: begin  // R-type ALU (30%)
          logic [2:0] f3 = $urandom_range(0, 7);
          logic [6:0] f7 = (f3 == 0 || f3 == 5) ? ($urandom_range(0,1) ? 7'h20 : 7'h00) : 7'h00;
          prog.push_back({f7, rs2, rs1, f3, rd, 7'b0110011});
        end
        3, 4: begin  // I-type ALU (20%)
          logic [2:0] f3 = $urandom_range(0, 7);
          if (f3 == 1 || f3 == 5) imm = $urandom_range(0, 31);
          prog.push_back({imm, rs1, f3, rd, 7'b0010011});
        end
        5: begin  // LW (10%) - word-aligned address from base register x8
          logic [11:0] offset = {$urandom_range(0, 15), 2'b00};
          prog.push_back({offset, 5'd8, 3'b010, rd, 7'b0000011});
        end
        6: begin  // SW (10%) - word-aligned address from base register x8
          logic [11:0] offset = {$urandom_range(0, 15), 2'b00};
          prog.push_back({offset[11:5], rs2, 5'd8, 3'b010, offset[4:0], 7'b0100011});
        end
        7: begin  // BEQ (10%) - small forward branch
          prog.push_back({7'b0000000, rs2, rs1, 3'b000, 5'b01000, 7'b1100011});  // BEQ +8
        end
        8: begin  // ADDI (10%) - guaranteed simple
          prog.push_back({imm, rs1, 3'b000, rd, 7'b0010011});
        end
        default: begin  // NOP (10%)
          prog.push_back(32'h00000013);
        end
      endcase
    end

    // NOP sled to drain pipeline
    for (int i = 0; i < 20; i++)
      prog.push_back(32'h00000013);
  endfunction

endclass


// Random instruction test
class riscv_random_test extends riscv_base_test;
  `uvm_component_utils(riscv_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    logic [31:0] prog[$];
    phase.raise_objection(this);

    // Generate and preload random program
    gen_random_program(prog, 100);
    preload_program(prog);

    `uvm_info("TEST", "Starting random instruction test", UVM_LOW)

    // Wait long enough for the processor to execute all instructions
    // Each instruction takes ~4-8 cycles due to cache miss latency
    #100000;

    phase.drop_objection(this);
  endtask

endclass


// Hazard-focused test
class riscv_hazard_test extends riscv_base_test;
  `uvm_component_utils(riscv_hazard_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    logic [31:0] prog[$];
    phase.raise_objection(this);

    // Use the basic test program which has hazards, branches, loads
    gen_basic_program(prog);

    // Add more NOP padding
    for (int i = 0; i < 20; i++)
      prog.push_back(32'h00000013);

    preload_program(prog);

    `uvm_info("TEST", "Starting hazard-focused test", UVM_LOW)

    #50000;

    phase.drop_objection(this);
  endtask

endclass


// Regression test with multiple seeds
class riscv_regression_test extends riscv_base_test;
  `uvm_component_utils(riscv_regression_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    logic [31:0] prog[$];
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting regression test (use +ntb_random_seed for variation)", UVM_LOW)

    // Generate larger random program
    gen_random_program(prog, 200);
    preload_program(prog);

    #200000;

    phase.drop_objection(this);
  endtask

endclass