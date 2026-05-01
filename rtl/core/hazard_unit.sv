// =============================================================================
// Hazard Detection and Forwarding Unit
// Handles:
//   - EX-to-EX forwarding (RAW hazards resolved in 1 cycle)
//   - MEM-to-EX forwarding (RAW hazards resolved in 2 cycles)
//   - Load-use stalls (1-cycle bubble for load followed by dependent op)
// =============================================================================
module hazard_unit
  import riscv_pkg::*;
(
  // ID/EX stage source registers
  input  logic [REG_ADDR_W-1:0]  id_ex_rs1_addr,
  input  logic [REG_ADDR_W-1:0]  id_ex_rs2_addr,

  // IF/ID stage source registers (for load-use detection)
  input  logic [REG_ADDR_W-1:0]  if_id_rs1_addr,
  input  logic [REG_ADDR_W-1:0]  if_id_rs2_addr,

  // EX/MEM stage destination
  input  logic [REG_ADDR_W-1:0]  ex_mem_rd_addr,
  input  logic                   ex_mem_reg_write,
  input  logic                   ex_mem_mem_read,

  // MEM/WB stage destination
  input  logic [REG_ADDR_W-1:0]  mem_wb_rd_addr,
  input  logic                   mem_wb_reg_write,

  // ID/EX stage load detection
  input  logic                   id_ex_mem_read,
  input  logic [REG_ADDR_W-1:0]  id_ex_rd_addr,

  // Forwarding outputs
  output fwd_sel_t               fwd_a,    // Forwarding mux select for operand A
  output fwd_sel_t               fwd_b,    // Forwarding mux select for operand B

  // Stall/flush outputs
  output logic                   stall_if,   // Stall IF stage
  output logic                   stall_id,   // Stall ID stage
  output logic                   bubble_ex   // Insert bubble in EX stage
);

  logic load_use_hazard;

  // -------------------------------------------------------------------------
  // Forwarding Logic
  // Priority: EX/MEM > MEM/WB (most recent write wins)
  // -------------------------------------------------------------------------

  // Forwarding for operand A (rs1)
  always_comb begin
    if (ex_mem_reg_write && (ex_mem_rd_addr != '0) &&
        (ex_mem_rd_addr == id_ex_rs1_addr))
      fwd_a = FWD_EX_MEM;
    else if (mem_wb_reg_write && (mem_wb_rd_addr != '0) &&
             (mem_wb_rd_addr == id_ex_rs1_addr))
      fwd_a = FWD_MEM_WB;
    else
      fwd_a = FWD_NONE;
  end

  // Forwarding for operand B (rs2)
  always_comb begin
    if (ex_mem_reg_write && (ex_mem_rd_addr != '0) &&
        (ex_mem_rd_addr == id_ex_rs2_addr))
      fwd_b = FWD_EX_MEM;
    else if (mem_wb_reg_write && (mem_wb_rd_addr != '0) &&
             (mem_wb_rd_addr == id_ex_rs2_addr))
      fwd_b = FWD_MEM_WB;
    else
      fwd_b = FWD_NONE;
  end

  // -------------------------------------------------------------------------
  // Load-Use Hazard Detection
  // Stall for 1 cycle when a load result is needed by the next instruction
  // -------------------------------------------------------------------------
  assign load_use_hazard = id_ex_mem_read && (id_ex_rd_addr != '0) &&
                           ((id_ex_rd_addr == if_id_rs1_addr) ||
                            (id_ex_rd_addr == if_id_rs2_addr));

  assign stall_if  = load_use_hazard;
  assign stall_id  = load_use_hazard;
  assign bubble_ex = load_use_hazard;

endmodule
