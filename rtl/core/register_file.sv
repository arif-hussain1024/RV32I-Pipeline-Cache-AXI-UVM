// =============================================================================
// Register File
// 32 x 32-bit registers, 2 async read ports, 1 sync write port
// x0 hardwired to zero
// =============================================================================
module register_file
  import riscv_pkg::*;
(
  input  logic                   clk,
  input  logic                   rst_n,
  // Read ports
  input  logic [REG_ADDR_W-1:0]  rs1_addr,
  input  logic [REG_ADDR_W-1:0]  rs2_addr,
  output logic [XLEN-1:0]        rs1_data,
  output logic [XLEN-1:0]        rs2_data,
  // Write port
  input  logic                   wr_en,
  input  logic [REG_ADDR_W-1:0]  rd_addr,
  input  logic [XLEN-1:0]        rd_data
);

  logic [XLEN-1:0] registers [REG_COUNT];

  // Async read with write-through (read-after-write in same cycle)
  always_comb begin
    // RS1
    if (rs1_addr == '0)
      rs1_data = '0;
    else if (wr_en && (rd_addr == rs1_addr))
      rs1_data = rd_data;
    else
      rs1_data = registers[rs1_addr];

    // RS2
    if (rs2_addr == '0)
      rs2_data = '0;
    else if (wr_en && (rd_addr == rs2_addr))
      rs2_data = rd_data;
    else
      rs2_data = registers[rs2_addr];
  end

  // Sync write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < REG_COUNT; i++)
        registers[i] <= '0;
    end else if (wr_en && (rd_addr != '0)) begin
      registers[rd_addr] <= rd_data;
    end
  end

endmodule
