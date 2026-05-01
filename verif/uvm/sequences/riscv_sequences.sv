// =============================================================================
// RISC-V Constrained-Random Instruction Sequences
// Generates random RV32I instruction programs with coverage-targeted patterns
// =============================================================================

// Base sequence item representing one instruction
class riscv_instr_item extends uvm_sequence_item;
  `uvm_object_utils(riscv_instr_item)

  rand logic [31:0] instruction;
  rand logic [6:0]  opcode;
  rand logic [4:0]  rd, rs1, rs2;
  rand logic [2:0]  funct3;
  rand logic [6:0]  funct7;
  rand logic [11:0] imm_i;
  rand logic [19:0] imm_u;

  // Weight distribution for instruction types
  typedef enum {
    INSTR_ALU_REG,    // R-type
    INSTR_ALU_IMM,    // I-type ALU
    INSTR_LOAD,
    INSTR_STORE,
    INSTR_BRANCH,
    INSTR_JAL,
    INSTR_JALR,
    INSTR_LUI,
    INSTR_AUIPC
  } instr_type_t;

  rand instr_type_t instr_type;

  constraint c_instr_dist {
    instr_type dist {
      INSTR_ALU_REG  := 30,
      INSTR_ALU_IMM  := 25,
      INSTR_LOAD     := 15,
      INSTR_STORE    := 10,
      INSTR_BRANCH   := 10,
      INSTR_JAL      := 3,
      INSTR_JALR     := 2,
      INSTR_LUI      := 3,
      INSTR_AUIPC    := 2
    };
  }

  // Prefer lower registers to increase data hazard probability
  constraint c_reg_hazard_bias {
    rd  dist {[0:7] := 70, [8:15] := 20, [16:31] := 10};
    rs1 dist {[0:7] := 70, [8:15] := 20, [16:31] := 10};
    rs2 dist {[0:7] := 70, [8:15] := 20, [16:31] := 10};
  }

  // Valid funct3/funct7 combinations
  constraint c_r_type {
    if (instr_type == INSTR_ALU_REG) {
      opcode == 7'b0110011;
      funct3 inside {[0:7]};
      if (funct3 == 3'b000 || funct3 == 3'b101)
        funct7 inside {7'b0000000, 7'b0100000};
      else
        funct7 == 7'b0000000;
    }
  }

  constraint c_i_type {
    if (instr_type == INSTR_ALU_IMM) {
      opcode == 7'b0010011;
      funct3 inside {[0:7]};
    }
  }

  constraint c_load {
    if (instr_type == INSTR_LOAD) {
      opcode == 7'b0000011;
      funct3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101};
      imm_i[11:0] inside {[0:252]};  // Keep addresses in range
    }
  }

  constraint c_store {
    if (instr_type == INSTR_STORE) {
      opcode == 7'b0100011;
      funct3 inside {3'b000, 3'b001, 3'b010};
    }
  }

  constraint c_branch {
    if (instr_type == INSTR_BRANCH) {
      opcode == 7'b1100011;
      funct3 inside {3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111};
    }
  }

  // Assemble instruction from fields
  function void post_randomize();
    case (instr_type)
      INSTR_ALU_REG:
        instruction = {funct7, rs2, rs1, funct3, rd, opcode};
      INSTR_ALU_IMM:
        instruction = {imm_i, rs1, funct3, rd, opcode};
      INSTR_LOAD:
        instruction = {imm_i, rs1, funct3, rd, 7'b0000011};
      INSTR_STORE:
        instruction = {imm_i[11:5], rs2, rs1, funct3, imm_i[4:0], 7'b0100011};
      INSTR_BRANCH:
        instruction = {imm_i[11], imm_i[9:4], rs2, rs1, funct3,
                       imm_i[3:0], imm_i[10], 7'b1100011};
      INSTR_LUI:
        instruction = {imm_u, rd, 7'b0110111};
      INSTR_AUIPC:
        instruction = {imm_u, rd, 7'b0010111};
      INSTR_JAL: begin
        // Small forward jump to avoid going out of range
        instruction = {1'b0, 10'd4, 1'b0, 8'd0, rd, 7'b1101111};
      end
      INSTR_JALR:
        instruction = {12'd8, rs1, 3'b000, rd, 7'b1100111};
    endcase
  endfunction

  function new(string name = "riscv_instr_item");
    super.new(name);
  endfunction

endclass


// =============================================================================
// Random Instruction Sequence
// =============================================================================
class riscv_random_seq extends uvm_sequence #(riscv_instr_item);
  `uvm_object_utils(riscv_random_seq)

  rand int unsigned num_instructions;

  constraint c_num_instr {
    num_instructions inside {[50:500]};
  }

  function new(string name = "riscv_random_seq");
    super.new(name);
  endfunction

  task body();
    riscv_instr_item instr;

    // Initialize registers with useful values first
    // LUI x1, 0x00001  (x1 = 0x1000, base address for loads/stores)
    instr = riscv_instr_item::type_id::create("init_lui");
    instr.instruction = {20'h00001, 5'd1, 7'b0110111};
    start_item(instr);
    finish_item(instr);

    // ADDI x2, x0, 100
    instr = riscv_instr_item::type_id::create("init_addi");
    instr.instruction = {12'd100, 5'd0, 3'b000, 5'd2, 7'b0010011};
    start_item(instr);
    finish_item(instr);

    // Random instructions
    for (int i = 0; i < num_instructions; i++) begin
      instr = riscv_instr_item::type_id::create($sformatf("instr_%0d", i));
      if (!instr.randomize())
        `uvm_fatal("SEQ", "Randomization failed")
      start_item(instr);
      finish_item(instr);
    end

    // Terminate with NOP sled
    for (int i = 0; i < 10; i++) begin
      instr = riscv_instr_item::type_id::create("nop");
      instr.instruction = 32'h00000013;  // ADDI x0, x0, 0 (NOP)
      start_item(instr);
      finish_item(instr);
    end
  endtask

endclass


// =============================================================================
// Hazard-Focused Sequence (RAW, Load-Use)
// =============================================================================
class riscv_hazard_seq extends uvm_sequence #(riscv_instr_item);
  `uvm_object_utils(riscv_hazard_seq)

  function new(string name = "riscv_hazard_seq");
    super.new(name);
  endfunction

  task body();
    riscv_instr_item instr;

    // --- RAW Hazard: back-to-back register dependency ---
    // ADD x1, x0, x0    (x1 = 0)
    // ADDI x1, x1, 5    (x1 = 5, depends on previous x1)
    // ADD x2, x1, x1    (x2 = 10, depends on x1)
    send_instr({7'b0000000, 5'd0, 5'd0, 3'b000, 5'd1, 7'b0110011});
    send_instr({12'd5,      5'd1, 3'b000, 5'd1, 7'b0010011});
    send_instr({7'b0000000, 5'd1, 5'd1, 3'b000, 5'd2, 7'b0110011});

    // --- Load-Use Hazard ---
    // SW x2, 0(x0)      Store x2 to address 0
    // LW x3, 0(x0)      Load from address 0 -> x3
    // ADD x4, x3, x3    (Load-use: depends on x3 from load)
    send_instr({7'b0000000, 5'd2, 5'd0, 3'b010, 5'd0, 7'b0100011});  // SW
    send_instr({12'd0,      5'd0, 3'b010, 5'd3, 7'b0000011});         // LW
    send_instr({7'b0000000, 5'd3, 5'd3, 3'b000, 5'd4, 7'b0110011});  // ADD

    // --- Double RAW ---
    // ADDI x5, x0, 10
    // ADDI x6, x5, 20   (EX-to-EX forwarding)
    // ADDI x7, x5, 30   (MEM-to-EX forwarding)
    send_instr({12'd10, 5'd0, 3'b000, 5'd5, 7'b0010011});
    send_instr({12'd20, 5'd5, 3'b000, 5'd6, 7'b0010011});
    send_instr({12'd30, 5'd5, 3'b000, 5'd7, 7'b0010011});

    // --- Branch after ALU ---
    // ADDI x8, x0, 1
    // BEQ x8, x8, +8    (should be taken, x8==x8)
    // ADDI x9, x0, 99   (should be flushed)
    // ADDI x10, x0, 42  (branch target)
    send_instr({12'd1, 5'd0, 3'b000, 5'd8, 7'b0010011});
    send_instr({7'b0000000, 5'd8, 5'd8, 3'b000, 5'b01000, 7'b1100011}); // BEQ +8
    send_instr({12'd99, 5'd0, 3'b000, 5'd9, 7'b0010011});
    send_instr({12'd42, 5'd0, 3'b000, 5'd10, 7'b0010011});

    // NOP sled to flush pipeline
    repeat(10) send_instr(32'h00000013);
  endtask

  task send_instr(logic [31:0] encoding);
    riscv_instr_item instr = riscv_instr_item::type_id::create("instr");
    instr.instruction = encoding;
    start_item(instr);
    finish_item(instr);
  endtask

endclass
