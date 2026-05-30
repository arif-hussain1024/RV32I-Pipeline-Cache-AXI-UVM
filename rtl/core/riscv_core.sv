// =============================================================================
// RISC-V RV32I 5-Stage Pipelined Core
// Integrates: PC, Register File, Decoder, ALU, Branch Unit, Hazard Unit
// Pipeline stages: IF -> ID -> EX -> MEM -> WB
// =============================================================================
module riscv_core
  import riscv_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,

  // Instruction memory interface (to I-Cache)
  output logic [XLEN-1:0]   imem_addr,
  input  logic [XLEN-1:0]   imem_rdata,
  output logic               imem_req,
  input  logic               imem_ready,

  // Data memory interface (to D-Cache)
  output logic [XLEN-1:0]   dmem_addr,
  output logic [XLEN-1:0]   dmem_wdata,
  input  logic [XLEN-1:0]   dmem_rdata,
  output logic               dmem_read,
  output logic               dmem_write,
  output logic [1:0]         dmem_width,
  input  logic               dmem_ready,

  // Pipeline activity signals (for clock gating)
  output logic               ex_stage_active,
  output logic               mem_stage_active
);

  // =========================================================================
  // Signal Declarations
  // =========================================================================

  // PC signals
  logic [XLEN-1:0] pc, pc_plus4;

  // Pipeline registers
  if_id_reg_t  if_id_reg, if_id_next;
  id_ex_reg_t  id_ex_reg, id_ex_next;
  ex_mem_reg_t ex_mem_reg, ex_mem_next;
  mem_wb_reg_t mem_wb_reg, mem_wb_next;

  // Decoder outputs
  ctrl_signals_t          dec_ctrl;
  logic [REG_ADDR_W-1:0]  dec_rs1_addr, dec_rs2_addr, dec_rd_addr;
  logic [XLEN-1:0]        dec_immediate;
  logic [2:0]             dec_funct3;
  logic                   dec_illegal;

  // Register file outputs
  logic [XLEN-1:0] rf_rs1_data, rf_rs2_data;

  // Hazard unit outputs
  fwd_sel_t fwd_a, fwd_b;
  logic     stall_if, stall_id, bubble_ex;

  // Branch unit outputs
  logic              branch_taken;
  logic [XLEN-1:0]   branch_target;
  logic              flush;

  // Forwarded operands
  logic [XLEN-1:0] fwd_rs1_data, fwd_rs2_data;

  // ALU signals
  logic [XLEN-1:0] alu_operand_a, alu_operand_b, alu_result;
  logic            alu_zero;

  // Writeback signals
  logic [XLEN-1:0]        wb_data;
  logic                   wb_en;
  logic [REG_ADDR_W-1:0]  wb_addr;

  // Memory stall
  logic mem_stall;
  assign mem_stall = (ex_mem_reg.mem_read || ex_mem_reg.mem_write) && !dmem_ready;

  // =========================================================================
  // STAGE 1: INSTRUCTION FETCH (IF)
  // =========================================================================

  program_counter u_pc (
    .clk           (clk),
    .rst_n         (rst_n),
    .stall         (stall_if || mem_stall || !imem_ready),
    .branch_taken  (branch_taken),
    .jump          (1'b0),  // Handled via branch_taken
    .branch_target (branch_target),
    .pc_out        (pc),
    .pc_plus4      (pc_plus4)
  );

  assign imem_addr = pc;
  assign imem_req  = !stall_if && !mem_stall;

  // IF/ID Pipeline Register
  always_comb begin
    if_id_next.pc          = pc;
    if_id_next.instruction = imem_rdata;
    if_id_next.pc_plus4    = pc_plus4;
    if_id_next.valid       = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      if_id_reg <= '0;
    else if (flush)
      if_id_reg <= '0;  // Flush: insert bubble
    else if (!stall_id && !mem_stall && imem_ready)
      if_id_reg <= if_id_next;
  end

  // =========================================================================
  // STAGE 2: INSTRUCTION DECODE (ID)
  // =========================================================================

  decoder u_decoder (
    .instruction   (if_id_reg.instruction),
    .ctrl          (dec_ctrl),
    .rs1_addr      (dec_rs1_addr),
    .rs2_addr      (dec_rs2_addr),
    .rd_addr       (dec_rd_addr),
    .immediate     (dec_immediate),
    .funct3        (dec_funct3),
    .illegal_instr (dec_illegal)
  );

  register_file u_regfile (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (dec_rs1_addr),
    .rs2_addr (dec_rs2_addr),
    .rs1_data (rf_rs1_data),
    .rs2_data (rf_rs2_data),
    .wr_en    (wb_en),
    .rd_addr  (wb_addr),
    .rd_data  (wb_data)
  );

  // ID/EX Pipeline Register
  always_comb begin
    id_ex_next.pc        = if_id_reg.pc;
    id_ex_next.pc_plus4  = if_id_reg.pc_plus4;
    id_ex_next.rs1_data  = rf_rs1_data;
    id_ex_next.rs2_data  = rf_rs2_data;
    id_ex_next.immediate = dec_immediate;
    id_ex_next.rs1_addr  = dec_rs1_addr;
    id_ex_next.rs2_addr  = dec_rs2_addr;
    id_ex_next.rd_addr   = dec_rd_addr;
    id_ex_next.funct3    = dec_funct3;
    id_ex_next.ctrl      = dec_ctrl;
    id_ex_next.valid     = if_id_reg.valid;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      id_ex_reg <= '0;
    else if ((flush && !mem_stall) || bubble_ex)
      id_ex_reg <= '0;  // Flush or insert bubble (but not during mem_stall
                         // so JAL/JALR can propagate to EX/MEM for link write)
    else if (!mem_stall)
      id_ex_reg <= id_ex_next;
  end

  // =========================================================================
  // STAGE 3: EXECUTE (EX)
  // =========================================================================

  // Forwarding muxes
  always_comb begin
    case (fwd_a)
      FWD_EX_MEM: fwd_rs1_data = ex_mem_reg.alu_result;
      FWD_MEM_WB: fwd_rs1_data = wb_data;
      default:    fwd_rs1_data = id_ex_reg.rs1_data;
    endcase

    case (fwd_b)
      FWD_EX_MEM: fwd_rs2_data = ex_mem_reg.alu_result;
      FWD_MEM_WB: fwd_rs2_data = wb_data;
      default:    fwd_rs2_data = id_ex_reg.rs2_data;
    endcase
  end

  // ALU operand selection
  assign alu_operand_a = (id_ex_reg.ctrl.is_auipc) ? id_ex_reg.pc : fwd_rs1_data;
  assign alu_operand_b = (id_ex_reg.ctrl.alu_src)  ? id_ex_reg.immediate : fwd_rs2_data;

  alu u_alu (
    .operand_a (alu_operand_a),
    .operand_b (alu_operand_b),
    .alu_op    (id_ex_reg.ctrl.alu_op),
    .result    (alu_result),
    .zero      (alu_zero)
  );

  // Branch resolution (resolved in EX stage)
  branch_unit u_branch (
    .rs1_data      (fwd_rs1_data),
    .rs2_data      (fwd_rs2_data),
    .pc            (id_ex_reg.pc),
    .immediate     (id_ex_reg.immediate),
    .funct3        (id_ex_reg.funct3),
    .is_branch     (id_ex_reg.ctrl.is_branch && id_ex_reg.valid),
    .is_jal        (id_ex_reg.ctrl.is_jal && id_ex_reg.valid),
    .is_jalr       (id_ex_reg.ctrl.is_jalr && id_ex_reg.valid),
    .branch_taken  (branch_taken),
    .branch_target (branch_target),
    .flush         (flush)
  );

  // EX/MEM Pipeline Register
  always_comb begin
    ex_mem_next.pc_plus4     = id_ex_reg.pc_plus4;
    ex_mem_next.alu_result   = alu_result;
    ex_mem_next.rs2_data     = fwd_rs2_data;
    ex_mem_next.rd_addr      = id_ex_reg.rd_addr;
    ex_mem_next.funct3       = id_ex_reg.funct3;
    ex_mem_next.mem_read     = id_ex_reg.ctrl.mem_read;
    ex_mem_next.mem_write    = id_ex_reg.ctrl.mem_write;
    ex_mem_next.mem_width    = id_ex_reg.ctrl.mem_width;
    ex_mem_next.mem_unsigned = id_ex_reg.ctrl.mem_unsigned;
    ex_mem_next.reg_write    = id_ex_reg.ctrl.reg_write;
    ex_mem_next.mem_to_reg   = id_ex_reg.ctrl.mem_to_reg;
    ex_mem_next.is_jal       = id_ex_reg.ctrl.is_jal;
    ex_mem_next.is_jalr      = id_ex_reg.ctrl.is_jalr;
    ex_mem_next.valid        = id_ex_reg.valid;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      ex_mem_reg <= '0;
    else if (!mem_stall)
      ex_mem_reg <= ex_mem_next;
  end

  // =========================================================================
  // STAGE 4: MEMORY ACCESS (MEM)
  // =========================================================================

  assign dmem_addr  = ex_mem_reg.alu_result;
  assign dmem_wdata = ex_mem_reg.rs2_data;
  assign dmem_read  = ex_mem_reg.mem_read && ex_mem_reg.valid;
  assign dmem_write = ex_mem_reg.mem_write && ex_mem_reg.valid;
  assign dmem_width = ex_mem_reg.mem_width;

  // Load data with sign/zero extension
  logic [XLEN-1:0] load_data;
  assign load_data = sign_extend(dmem_rdata, ex_mem_reg.mem_width,
                                 ex_mem_reg.mem_unsigned,
                                 ex_mem_reg.alu_result[1:0]);

  // MEM/WB Pipeline Register
  always_comb begin
    mem_wb_next.pc_plus4   = ex_mem_reg.pc_plus4;
    mem_wb_next.alu_result = ex_mem_reg.alu_result;
    mem_wb_next.mem_data   = load_data;
    mem_wb_next.rd_addr    = ex_mem_reg.rd_addr;
    mem_wb_next.reg_write  = ex_mem_reg.reg_write;
    mem_wb_next.mem_to_reg = ex_mem_reg.mem_to_reg;
    mem_wb_next.is_jal     = ex_mem_reg.is_jal;
    mem_wb_next.is_jalr    = ex_mem_reg.is_jalr;
    mem_wb_next.valid      = ex_mem_reg.valid;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      mem_wb_reg <= '0;
    else if (!mem_stall)
      mem_wb_reg <= mem_wb_next;
  end

  // =========================================================================
  // STAGE 5: WRITE BACK (WB)
  // =========================================================================

  always_comb begin
    if (mem_wb_reg.is_jal || mem_wb_reg.is_jalr)
      wb_data = mem_wb_reg.pc_plus4;           // JAL/JALR: link address
    else if (mem_wb_reg.mem_to_reg)
      wb_data = mem_wb_reg.mem_data;           // Load: memory data
    else
      wb_data = mem_wb_reg.alu_result;         // ALU result
  end

  assign wb_en   = mem_wb_reg.reg_write && mem_wb_reg.valid;
  assign wb_addr = mem_wb_reg.rd_addr;

  // =========================================================================
  // HAZARD DETECTION AND FORWARDING UNIT
  // =========================================================================

  hazard_unit u_hazard (
    .id_ex_rs1_addr   (id_ex_reg.rs1_addr),
    .id_ex_rs2_addr   (id_ex_reg.rs2_addr),
    .if_id_rs1_addr   (dec_rs1_addr),
    .if_id_rs2_addr   (dec_rs2_addr),
    .ex_mem_rd_addr   (ex_mem_reg.rd_addr),
    .ex_mem_reg_write (ex_mem_reg.reg_write && ex_mem_reg.valid),
    .ex_mem_mem_read  (ex_mem_reg.mem_read),
    .mem_wb_rd_addr   (mem_wb_reg.rd_addr),
    .mem_wb_reg_write (mem_wb_reg.reg_write && mem_wb_reg.valid),
    .id_ex_mem_read   (id_ex_reg.ctrl.mem_read),
    .id_ex_rd_addr    (id_ex_reg.rd_addr),
    .fwd_a            (fwd_a),
    .fwd_b            (fwd_b),
    .stall_if         (stall_if),
    .stall_id         (stall_id),
    .bubble_ex        (bubble_ex)
  );

  // =========================================================================
  // Pipeline Activity (for clock gating)
  // =========================================================================
  assign ex_stage_active  = id_ex_reg.valid;
  assign mem_stage_active = ex_mem_reg.valid &&
                            (ex_mem_reg.mem_read || ex_mem_reg.mem_write);

endmodule
