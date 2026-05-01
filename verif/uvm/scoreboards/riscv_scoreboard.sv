// =============================================================================
// RISC-V Reference Model Scoreboard
// Software ISS that executes instructions and compares against RTL
// =============================================================================
class riscv_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(riscv_scoreboard)

  // Analysis exports
  uvm_analysis_imp #(axi4_lite_txn, riscv_scoreboard) axi_export;

  // Reference model state
  logic [31:0] ref_regs [32];      // Register file
  logic [31:0] ref_pc;             // Program counter
  logic [31:0] ref_memory [logic [31:0]];  // Memory model

  // Statistics
  int unsigned instr_count;
  int unsigned mismatch_count;
  int unsigned axi_rd_count;
  int unsigned axi_wr_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_export = new("axi_export", this);
    reset_model();
  endfunction

  function void reset_model();
    for (int i = 0; i < 32; i++)
      ref_regs[i] = '0;
    ref_pc = '0;
    instr_count = 0;
    mismatch_count = 0;
    axi_rd_count = 0;
    axi_wr_count = 0;
  endfunction

  // Execute a single instruction in the reference model
  function void execute_instruction(logic [31:0] instr);
    logic [6:0]  opcode = instr[6:0];
    logic [4:0]  rd     = instr[11:7];
    logic [2:0]  funct3 = instr[14:12];
    logic [4:0]  rs1    = instr[19:15];
    logic [4:0]  rs2    = instr[24:20];
    logic [6:0]  funct7 = instr[31:25];
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] rs1_val, rs2_val, result;
    logic [31:0] next_pc;
    logic signed [31:0] signed_rs1, signed_rs2;

    // Immediate generation
    imm_i = {{20{instr[31]}}, instr[31:20]};
    imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    imm_u = {instr[31:12], 12'b0};
    imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    rs1_val = ref_regs[rs1];
    rs2_val = ref_regs[rs2];
    signed_rs1 = $signed(rs1_val);
    signed_rs2 = $signed(rs2_val);
    next_pc = ref_pc + 4;

    case (opcode)
      7'b0110011: begin  // R-type
        case ({funct7, funct3})
          10'b0000000_000: result = rs1_val + rs2_val;        // ADD
          10'b0100000_000: result = rs1_val - rs2_val;        // SUB
          10'b0000000_001: result = rs1_val << rs2_val[4:0];  // SLL
          10'b0000000_010: result = {31'b0, signed_rs1 < signed_rs2}; // SLT
          10'b0000000_011: result = {31'b0, rs1_val < rs2_val};       // SLTU
          10'b0000000_100: result = rs1_val ^ rs2_val;        // XOR
          10'b0000000_101: result = rs1_val >> rs2_val[4:0];  // SRL
          10'b0100000_101: result = $unsigned(signed_rs1 >>> rs2_val[4:0]); // SRA
          10'b0000000_110: result = rs1_val | rs2_val;        // OR
          10'b0000000_111: result = rs1_val & rs2_val;        // AND
          default: result = '0;
        endcase
        if (rd != 0) ref_regs[rd] = result;
      end

      7'b0010011: begin  // I-type ALU
        case (funct3)
          3'b000: result = rs1_val + imm_i;                       // ADDI
          3'b010: result = {31'b0, signed_rs1 < $signed(imm_i)};  // SLTI
          3'b011: result = {31'b0, rs1_val < imm_i};              // SLTIU
          3'b100: result = rs1_val ^ imm_i;                       // XORI
          3'b110: result = rs1_val | imm_i;                       // ORI
          3'b111: result = rs1_val & imm_i;                       // ANDI
          3'b001: result = rs1_val << imm_i[4:0];                 // SLLI
          3'b101: begin
            if (funct7[5]) result = $unsigned(signed_rs1 >>> imm_i[4:0]); // SRAI
            else           result = rs1_val >> imm_i[4:0];                // SRLI
          end
        endcase
        if (rd != 0) ref_regs[rd] = result;
      end

      7'b0110111: begin  // LUI
        if (rd != 0) ref_regs[rd] = imm_u;
      end

      7'b0010111: begin  // AUIPC
        if (rd != 0) ref_regs[rd] = ref_pc + imm_u;
      end

      7'b0000011: begin  // LOAD
        logic [31:0] addr = rs1_val + imm_i;
        logic [31:0] mem_val = ref_memory.exists(addr & ~32'h3) ?
                               ref_memory[addr & ~32'h3] : '0;
        case (funct3)
          3'b000: result = {{24{mem_val[7]}}, mem_val[7:0]};     // LB
          3'b001: result = {{16{mem_val[15]}}, mem_val[15:0]};   // LH
          3'b010: result = mem_val;                                // LW
          3'b100: result = {24'b0, mem_val[7:0]};                 // LBU
          3'b101: result = {16'b0, mem_val[15:0]};                // LHU
          default: result = '0;
        endcase
        if (rd != 0) ref_regs[rd] = result;
      end

      7'b0100011: begin  // STORE
        logic [31:0] addr = rs1_val + imm_s;
        ref_memory[addr & ~32'h3] = rs2_val;  // Simplified: full word store
      end

      7'b1100011: begin  // BRANCH
        logic taken;
        case (funct3)
          3'b000: taken = (rs1_val == rs2_val);           // BEQ
          3'b001: taken = (rs1_val != rs2_val);           // BNE
          3'b100: taken = (signed_rs1 < signed_rs2);      // BLT
          3'b101: taken = (signed_rs1 >= signed_rs2);     // BGE
          3'b110: taken = (rs1_val < rs2_val);            // BLTU
          3'b111: taken = (rs1_val >= rs2_val);           // BGEU
          default: taken = 0;
        endcase
        if (taken) next_pc = ref_pc + imm_b;
      end

      7'b1101111: begin  // JAL
        if (rd != 0) ref_regs[rd] = ref_pc + 4;
        next_pc = ref_pc + imm_j;
      end

      7'b1100111: begin  // JALR
        if (rd != 0) ref_regs[rd] = ref_pc + 4;
        next_pc = (rs1_val + imm_i) & ~32'h1;
      end

      default: begin
        // NOP or unimplemented
      end
    endcase

    ref_pc = next_pc;
    ref_regs[0] = '0;  // Ensure x0 stays zero
    instr_count++;
  endfunction

  // Compare register state with RTL
  function void compare_state(logic [31:0] rtl_regs [32], logic [31:0] rtl_pc);
    for (int i = 0; i < 32; i++) begin
      if (ref_regs[i] !== rtl_regs[i]) begin
        `uvm_error("SCBD", $sformatf(
          "Register x%0d mismatch: ref=0x%08h rtl=0x%08h (instr #%0d)",
          i, ref_regs[i], rtl_regs[i], instr_count))
        mismatch_count++;
      end
    end
    if (ref_pc !== rtl_pc) begin
      `uvm_error("SCBD", $sformatf(
        "PC mismatch: ref=0x%08h rtl=0x%08h", ref_pc, rtl_pc))
      mismatch_count++;
    end
  endfunction

  // AXI transaction analysis
  function void write(axi4_lite_txn txn);
    if (txn.is_write) begin
      axi_wr_count++;
      `uvm_info("SCBD", $sformatf("AXI WR observed: addr=0x%08h data=0x%08h",
                txn.addr, txn.data), UVM_HIGH)
    end else begin
      axi_rd_count++;
      `uvm_info("SCBD", $sformatf("AXI RD observed: addr=0x%08h data=0x%08h",
                txn.addr, txn.data), UVM_HIGH)
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCBD", $sformatf(
      "\n========== Scoreboard Report ==========\n" +
      "Instructions executed: %0d\n" +
      "Mismatches:           %0d\n" +
      "AXI Read transactions:  %0d\n" +
      "AXI Write transactions: %0d\n" +
      "=======================================",
      instr_count, mismatch_count, axi_rd_count, axi_wr_count), UVM_LOW)
    if (mismatch_count > 0)
      `uvm_error("SCBD", "TEST FAILED - mismatches detected")
    else
      `uvm_info("SCBD", "TEST PASSED", UVM_LOW)
  endfunction

endclass
