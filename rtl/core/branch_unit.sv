// =============================================================================
// Branch Resolution Unit
// Evaluates branch conditions and computes targets
// Static prediction: predict not-taken
// =============================================================================
module branch_unit
  import riscv_pkg::*;
(
  input  logic [XLEN-1:0]  rs1_data,
  input  logic [XLEN-1:0]  rs2_data,
  input  logic [XLEN-1:0]  pc,
  input  logic [XLEN-1:0]  immediate,
  input  logic [2:0]        funct3,
  input  logic              is_branch,
  input  logic              is_jal,
  input  logic              is_jalr,
  output logic              branch_taken,
  output logic [XLEN-1:0]   branch_target,
  output logic              flush        // Flush IF/ID on taken branch or jump
);

  logic branch_condition;
  logic signed [XLEN-1:0] signed_rs1, signed_rs2;

  assign signed_rs1 = $signed(rs1_data);
  assign signed_rs2 = $signed(rs2_data);

  // Branch condition evaluation
  always_comb begin
    case (funct3)
      3'b000:  branch_condition = (rs1_data == rs2_data);           // BEQ
      3'b001:  branch_condition = (rs1_data != rs2_data);           // BNE
      3'b100:  branch_condition = (signed_rs1 < signed_rs2);       // BLT
      3'b101:  branch_condition = (signed_rs1 >= signed_rs2);      // BGE
      3'b110:  branch_condition = (rs1_data < rs2_data);            // BLTU
      3'b111:  branch_condition = (rs1_data >= rs2_data);           // BGEU
      default: branch_condition = 1'b0;
    endcase
  end

  // Branch/jump target computation
  always_comb begin
    if (is_jalr)
      branch_target = (rs1_data + immediate) & ~32'h1;  // Clear LSB per spec
    else
      branch_target = pc + immediate;  // JAL and branches: PC-relative
  end

  // Taken decision (static predict not-taken, so taken = mispredict)
  assign branch_taken = (is_branch && branch_condition) || is_jal || is_jalr;

  // Flush on any taken branch or jump (mispredict for branches, always for jumps)
  assign flush = branch_taken;

endmodule
