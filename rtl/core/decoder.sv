// =============================================================================
// Instruction Decoder / Control Unit
// Decodes RV32I instructions and generates pipeline control signals
// =============================================================================
module decoder
  import riscv_pkg::*;
(
  input  logic [XLEN-1:0]        instruction,
  output ctrl_signals_t           ctrl,
  output logic [REG_ADDR_W-1:0]   rs1_addr,
  output logic [REG_ADDR_W-1:0]   rs2_addr,
  output logic [REG_ADDR_W-1:0]   rd_addr,
  output logic [XLEN-1:0]         immediate,
  output logic [2:0]              funct3,
  output logic                    illegal_instr
);

  logic [6:0] opcode;
  logic [6:0] funct7;

  assign opcode   = instruction[6:0];
  assign rd_addr  = instruction[11:7];
  assign funct3   = instruction[14:12];
  assign rs1_addr = instruction[19:15];
  assign rs2_addr = instruction[24:20];
  assign funct7   = instruction[31:25];

  // -------------------------------------------------------------------------
  // Immediate Generation
  // -------------------------------------------------------------------------
  always_comb begin
    case (opcode)
      OP_IMM, OP_LOAD, OP_JALR:  // I-type
        immediate = {{20{instruction[31]}}, instruction[31:20]};

      OP_STORE:  // S-type
        immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};

      OP_BRANCH:  // B-type
        immediate = {{19{instruction[31]}}, instruction[31], instruction[7],
                     instruction[30:25], instruction[11:8], 1'b0};

      OP_LUI, OP_AUIPC:  // U-type
        immediate = {instruction[31:12], 12'b0};

      OP_JAL:  // J-type
        immediate = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                     instruction[20], instruction[30:21], 1'b0};

      default:
        immediate = '0;
    endcase
  end

  // -------------------------------------------------------------------------
  // Control Signal Generation
  // -------------------------------------------------------------------------
  always_comb begin
    // Defaults
    ctrl           = '0;
    illegal_instr  = 1'b0;

    case (opcode)
      OP_REG: begin  // R-type arithmetic
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b0;  // rs2
        case (funct3)
          3'b000: ctrl.alu_op = (funct7[5]) ? ALU_SUB : ALU_ADD;
          3'b001: ctrl.alu_op = ALU_SLL;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b101: ctrl.alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
        endcase
      end

      OP_IMM: begin  // I-type arithmetic
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b1;  // immediate
        case (funct3)
          3'b000: ctrl.alu_op = ALU_ADD;
          3'b001: ctrl.alu_op = ALU_SLL;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b101: ctrl.alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
        endcase
      end

      OP_LUI: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b1;
        ctrl.alu_op    = ALU_PASS_B;
        ctrl.is_lui    = 1'b1;
      end

      OP_AUIPC: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b1;
        ctrl.alu_op    = ALU_ADD;
        ctrl.is_auipc  = 1'b1;
      end

      OP_LOAD: begin
        ctrl.reg_write   = 1'b1;
        ctrl.alu_src     = 1'b1;
        ctrl.alu_op      = ALU_ADD;
        ctrl.mem_read    = 1'b1;
        ctrl.mem_to_reg  = 1'b1;
        ctrl.mem_width   = mem_width_t'(funct3[1:0]);
        ctrl.mem_unsigned = funct3[2];
      end

      OP_STORE: begin
        ctrl.alu_src   = 1'b1;
        ctrl.alu_op    = ALU_ADD;
        ctrl.mem_write = 1'b1;
        ctrl.mem_width = mem_width_t'(funct3[1:0]);
      end

      OP_BRANCH: begin
        ctrl.is_branch = 1'b1;
        ctrl.alu_op    = ALU_SUB;  // For comparison
      end

      OP_JAL: begin
        ctrl.reg_write = 1'b1;
        ctrl.is_jal    = 1'b1;
      end

      OP_JALR: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b1;
        ctrl.alu_op    = ALU_ADD;
        ctrl.is_jalr   = 1'b1;
      end

      OP_FENCE: begin
        // NOP for now (single-core, in-order)
      end

      OP_SYSTEM: begin
        // ECALL/EBREAK - NOP for now
      end

      default: begin
        illegal_instr = 1'b1;
      end
    endcase
  end

endmodule
