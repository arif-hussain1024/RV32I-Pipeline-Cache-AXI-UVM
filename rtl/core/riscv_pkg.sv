// =============================================================================
// RISC-V RV32I Processor Package
// Shared types, parameters, and definitions
// =============================================================================
package riscv_pkg;

  // -------------------------------------------------------------------------
  // Global Parameters
  // -------------------------------------------------------------------------
  parameter int XLEN       = 32;
  parameter int ADDR_WIDTH = 32;
  parameter int DATA_WIDTH = 32;
  parameter int REG_COUNT  = 32;
  parameter int REG_ADDR_W = 5;

  // -------------------------------------------------------------------------
  // Opcode Definitions (RV32I)
  // -------------------------------------------------------------------------
  typedef enum logic [6:0] {
    OP_LUI      = 7'b0110111,
    OP_AUIPC    = 7'b0010111,
    OP_JAL      = 7'b1101111,
    OP_JALR     = 7'b1100111,
    OP_BRANCH   = 7'b1100011,
    OP_LOAD     = 7'b0000011,
    OP_STORE    = 7'b0100011,
    OP_IMM      = 7'b0010011,
    OP_REG      = 7'b0110011,
    OP_FENCE    = 7'b0001111,
    OP_SYSTEM   = 7'b1110011
  } opcode_t;

  // -------------------------------------------------------------------------
  // ALU Operation Codes
  // -------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b0001,
    ALU_SLL  = 4'b0010,
    ALU_SLT  = 4'b0011,
    ALU_SLTU = 4'b0100,
    ALU_XOR  = 4'b0101,
    ALU_SRL  = 4'b0110,
    ALU_SRA  = 4'b0111,
    ALU_OR   = 4'b1000,
    ALU_AND  = 4'b1001,
    ALU_PASS_B = 4'b1010  // Pass operand B (for LUI)
  } alu_op_t;

  // -------------------------------------------------------------------------
  // Branch Function Codes
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    BR_BEQ  = 3'b000,
    BR_BNE  = 3'b001,
    BR_BLT  = 3'b100,
    BR_BGE  = 3'b101,
    BR_BLTU = 3'b110,
    BR_BGEU = 3'b111
  } branch_func_t;

  // -------------------------------------------------------------------------
  // Immediate Type
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    IMM_I = 3'b000,
    IMM_S = 3'b001,
    IMM_B = 3'b010,
    IMM_U = 3'b011,
    IMM_J = 3'b100
  } imm_type_t;

  // -------------------------------------------------------------------------
  // Forwarding Mux Select
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FWD_NONE   = 2'b00,  // No forwarding, use register file
    FWD_EX_MEM = 2'b01,  // Forward from EX/MEM pipeline register
    FWD_MEM_WB = 2'b10   // Forward from MEM/WB pipeline register
  } fwd_sel_t;

  // -------------------------------------------------------------------------
  // Memory Access Width
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    MEM_BYTE = 2'b00,
    MEM_HALF = 2'b01,
    MEM_WORD = 2'b10
  } mem_width_t;

  // -------------------------------------------------------------------------
  // Pipeline Control Signals Bundle
  // -------------------------------------------------------------------------
  typedef struct packed {
    // Execute stage controls
    alu_op_t    alu_op;
    logic       alu_src;       // 0 = rs2, 1 = immediate
    // Memory stage controls
    logic       mem_read;
    logic       mem_write;
    mem_width_t mem_width;
    logic       mem_unsigned;  // Unsigned load
    // Writeback stage controls
    logic       reg_write;
    logic       mem_to_reg;    // 0 = ALU result, 1 = memory data
    // Branch/Jump controls
    logic       is_branch;
    logic       is_jal;
    logic       is_jalr;
    logic       is_lui;
    logic       is_auipc;
  } ctrl_signals_t;

  // -------------------------------------------------------------------------
  // Pipeline Register Structures
  // -------------------------------------------------------------------------

  // IF/ID Pipeline Register
  typedef struct packed {
    logic [XLEN-1:0]      pc;
    logic [XLEN-1:0]      instruction;
    logic [XLEN-1:0]      pc_plus4;
    logic                  valid;
  } if_id_reg_t;

  // ID/EX Pipeline Register
  typedef struct packed {
    logic [XLEN-1:0]      pc;
    logic [XLEN-1:0]      pc_plus4;
    logic [XLEN-1:0]      rs1_data;
    logic [XLEN-1:0]      rs2_data;
    logic [XLEN-1:0]      immediate;
    logic [REG_ADDR_W-1:0] rs1_addr;
    logic [REG_ADDR_W-1:0] rs2_addr;
    logic [REG_ADDR_W-1:0] rd_addr;
    logic [2:0]            funct3;
    ctrl_signals_t         ctrl;
    logic                  valid;
  } id_ex_reg_t;

  // EX/MEM Pipeline Register
  typedef struct packed {
    logic [XLEN-1:0]      pc_plus4;
    logic [XLEN-1:0]      alu_result;
    logic [XLEN-1:0]      rs2_data;      // Store data
    logic [REG_ADDR_W-1:0] rd_addr;
    logic [2:0]            funct3;
    logic                  mem_read;
    logic                  mem_write;
    mem_width_t            mem_width;
    logic                  mem_unsigned;
    logic                  reg_write;
    logic                  mem_to_reg;
    logic                  is_jal;
    logic                  is_jalr;
    logic                  valid;
  } ex_mem_reg_t;

  // MEM/WB Pipeline Register
  typedef struct packed {
    logic [XLEN-1:0]      pc_plus4;
    logic [XLEN-1:0]      alu_result;
    logic [XLEN-1:0]      mem_data;
    logic [REG_ADDR_W-1:0] rd_addr;
    logic                  reg_write;
    logic                  mem_to_reg;
    logic                  is_jal;
    logic                  is_jalr;
    logic                  valid;
  } mem_wb_reg_t;

  // -------------------------------------------------------------------------
  // Cache Parameters
  // -------------------------------------------------------------------------
  parameter int CACHE_LINE_BYTES  = 16;    // 16 bytes per line (4 words)
  parameter int CACHE_LINE_WORDS  = CACHE_LINE_BYTES / 4;
  parameter int CACHE_NUM_SETS    = 64;    // 64 sets
  parameter int CACHE_NUM_WAYS    = 2;     // 2-way set associative

  parameter int CACHE_OFFSET_BITS = $clog2(CACHE_LINE_BYTES); // 4
  parameter int CACHE_INDEX_BITS  = $clog2(CACHE_NUM_SETS);   // 6
  parameter int CACHE_TAG_BITS    = ADDR_WIDTH - CACHE_OFFSET_BITS - CACHE_INDEX_BITS; // 22

  // Cache line structure
  typedef struct packed {
    logic                          valid;
    logic                          dirty;
    logic [CACHE_TAG_BITS-1:0]     tag;
    logic [CACHE_LINE_BYTES*8-1:0] data;  // Full cache line data
  } cache_line_t;

  // Cache FSM states
  typedef enum logic [2:0] {
    CACHE_IDLE       = 3'b000,
    CACHE_COMPARE    = 3'b001,
    CACHE_WRITEBACK  = 3'b010,
    CACHE_ALLOCATE   = 3'b011,
    CACHE_REFILL     = 3'b100
  } cache_state_t;

  // -------------------------------------------------------------------------
  // AXI4-Lite Interface Widths
  // -------------------------------------------------------------------------
  parameter int AXI_ADDR_WIDTH = 32;
  parameter int AXI_DATA_WIDTH = 32;
  parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

  // AXI Response codes
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_t;

  // -------------------------------------------------------------------------
  // Helper Functions
  // -------------------------------------------------------------------------

  // Sign extension
  function automatic logic [XLEN-1:0] sign_extend(
    input logic [XLEN-1:0] data,
    input mem_width_t width,
    input logic unsigned_load
  );
    case (width)
      MEM_BYTE: begin
        if (unsigned_load) return {24'b0, data[7:0]};
        else               return {{24{data[7]}}, data[7:0]};
      end
      MEM_HALF: begin
        if (unsigned_load) return {16'b0, data[15:0]};
        else               return {{16{data[15]}}, data[15:0]};
      end
      default: return data;
    endcase
  endfunction

endpackage
