// =============================================================================
// Program Counter
// Manages PC with branch/jump target selection and stall support
// =============================================================================
module program_counter
  import riscv_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              stall,         // Stall PC update
  input  logic              branch_taken,  // Branch resolved as taken
  input  logic              jump,          // JAL or JALR
  input  logic [XLEN-1:0]   branch_target, // Computed branch/jump target
  output logic [XLEN-1:0]   pc_out,
  output logic [XLEN-1:0]   pc_plus4
);

  logic [XLEN-1:0] pc_reg;
  logic [XLEN-1:0] pc_next;

  assign pc_out   = pc_reg;
  assign pc_plus4 = pc_reg + 32'd4;

  // Next PC selection
  always_comb begin
    if (branch_taken || jump)
      pc_next = branch_target;
    else
      pc_next = pc_plus4;
  end

  // PC register with synchronous reset
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_reg <= '0;
    else if (!stall)
      pc_reg <= pc_next;
  end

endmodule
