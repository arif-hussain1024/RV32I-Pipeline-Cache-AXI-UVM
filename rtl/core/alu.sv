// =============================================================================
// Arithmetic Logic Unit (ALU)
// Supports all RV32I arithmetic and logical operations
// =============================================================================
module alu
  import riscv_pkg::*;
(
  input  logic [XLEN-1:0]  operand_a,
  input  logic [XLEN-1:0]  operand_b,
  input  alu_op_t           alu_op,
  output logic [XLEN-1:0]  result,
  output logic              zero
);

  logic signed [XLEN-1:0] signed_a;
  logic signed [XLEN-1:0] signed_b;

  assign signed_a = $signed(operand_a);
  assign signed_b = $signed(operand_b);

  always_comb begin
    case (alu_op)
      ALU_ADD:    result = operand_a + operand_b;
      ALU_SUB:    result = operand_a - operand_b;
      ALU_SLL:    result = operand_a << operand_b[4:0];
      ALU_SLT:    result = {31'b0, (signed_a < signed_b)};
      ALU_SLTU:   result = {31'b0, (operand_a < operand_b)};
      ALU_XOR:    result = operand_a ^ operand_b;
      ALU_SRL:    result = operand_a >> operand_b[4:0];
      ALU_SRA:    result = $unsigned(signed_a >>> operand_b[4:0]);
      ALU_OR:     result = operand_a | operand_b;
      ALU_AND:    result = operand_a & operand_b;
      ALU_PASS_B: result = operand_b;
      default:    result = '0;
    endcase
  end

  assign zero = (result == '0);

endmodule
