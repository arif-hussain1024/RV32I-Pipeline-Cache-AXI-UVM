// =============================================================================
// AXI4-Lite Master Interface
// Connects instruction and data caches to main memory
// Handles address decoding, arbitration, and AXI4-Lite handshakes
// Supports burst-like transfers for cache line refills/writebacks
// =============================================================================
module axi4_lite_master
  import riscv_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,

  // I-Cache read interface
  input  logic [XLEN-1:0]   icache_addr,
  input  logic               icache_req,
  output logic [XLEN-1:0]   icache_rdata,
  output logic               icache_valid,
  output logic               icache_last,

  // D-Cache read interface
  input  logic [XLEN-1:0]   dcache_rd_addr,
  input  logic               dcache_rd_req,
  output logic [XLEN-1:0]   dcache_rdata,
  output logic               dcache_rd_valid,
  output logic               dcache_rd_last,

  // D-Cache write interface
  input  logic [XLEN-1:0]   dcache_wr_addr,
  input  logic [XLEN-1:0]   dcache_wr_data,
  input  logic               dcache_wr_req,
  output logic               dcache_wr_done,

  // AXI4-Lite Master Interface
  // Write Address Channel
  output logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
  output logic                        m_axi_awvalid,
  input  logic                        m_axi_awready,
  output logic [2:0]                  m_axi_awprot,

  // Write Data Channel
  output logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
  output logic [AXI_STRB_WIDTH-1:0]  m_axi_wstrb,
  output logic                        m_axi_wvalid,
  input  logic                        m_axi_wready,

  // Write Response Channel
  input  logic [1:0]                  m_axi_bresp,
  input  logic                        m_axi_bvalid,
  output logic                        m_axi_bready,

  // Read Address Channel
  output logic [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
  output logic                        m_axi_arvalid,
  input  logic                        m_axi_arready,
  output logic [2:0]                  m_axi_arprot,

  // Read Data Channel
  input  logic [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
  input  logic [1:0]                  m_axi_rresp,
  input  logic                        m_axi_rvalid,
  output logic                        m_axi_rready
);

  // -------------------------------------------------------------------------
  // FSM States
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    AXI_IDLE,
    AXI_RD_ADDR,       // Read address phase
    AXI_RD_DATA,       // Read data phase
    AXI_WR_ADDR,       // Write address phase
    AXI_WR_DATA,       // Write data phase
    AXI_WR_RESP        // Write response phase
  } axi_state_t;

  axi_state_t state, state_next;

  // Request source tracking
  typedef enum logic [1:0] {
    SRC_NONE,
    SRC_ICACHE,
    SRC_DCACHE_RD,
    SRC_DCACHE_WR
  } req_source_t;

  req_source_t active_src, active_src_next;
  logic [XLEN-1:0] req_addr, req_addr_next;
  logic [XLEN-1:0] wr_data_reg, wr_data_next;

  // Default protection: unprivileged, non-secure, data
  assign m_axi_awprot = 3'b000;
  assign m_axi_arprot = 3'b000;

  // -------------------------------------------------------------------------
  // State machine
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= AXI_IDLE;
      active_src <= SRC_NONE;
      req_addr   <= '0;
      wr_data_reg <= '0;
    end else begin
      state      <= state_next;
      active_src <= active_src_next;
      req_addr   <= req_addr_next;
      wr_data_reg <= wr_data_next;
    end
  end

  always_comb begin
    // Defaults
    state_next      = state;
    active_src_next = active_src;
    req_addr_next   = req_addr;
    wr_data_next    = wr_data_reg;

    m_axi_araddr  = '0;
    m_axi_arvalid = 1'b0;
    m_axi_rready  = 1'b0;

    m_axi_awaddr  = '0;
    m_axi_awvalid = 1'b0;
    m_axi_wdata   = '0;
    m_axi_wstrb   = '0;
    m_axi_wvalid  = 1'b0;
    m_axi_bready  = 1'b0;

    icache_rdata    = '0;
    icache_valid    = 1'b0;
    icache_last     = 1'b0;

    dcache_rdata    = '0;
    dcache_rd_valid = 1'b0;
    dcache_rd_last  = 1'b0;
    dcache_wr_done  = 1'b0;

    case (state)
      AXI_IDLE: begin
        // Priority: D-Cache write > D-Cache read > I-Cache read
        if (dcache_wr_req) begin
          active_src_next = SRC_DCACHE_WR;
          req_addr_next   = dcache_wr_addr;
          wr_data_next    = dcache_wr_data;
          state_next      = AXI_WR_ADDR;
        end else if (dcache_rd_req) begin
          active_src_next = SRC_DCACHE_RD;
          req_addr_next   = dcache_rd_addr;
          state_next      = AXI_RD_ADDR;
        end else if (icache_req) begin
          active_src_next = SRC_ICACHE;
          req_addr_next   = icache_addr;
          state_next      = AXI_RD_ADDR;
        end
      end

      // ---- Read Transaction ----
      AXI_RD_ADDR: begin
        m_axi_araddr  = req_addr;
        m_axi_arvalid = 1'b1;
        if (m_axi_arready) begin
          state_next = AXI_RD_DATA;
        end
      end

      AXI_RD_DATA: begin
        m_axi_rready = 1'b1;
        if (m_axi_rvalid) begin
          case (active_src)
            SRC_ICACHE: begin
              icache_rdata = m_axi_rdata;
              icache_valid = 1'b1;
              icache_last  = 1'b1;  // Single beat per AXI-Lite transfer
            end
            SRC_DCACHE_RD: begin
              dcache_rdata    = m_axi_rdata;
              dcache_rd_valid = 1'b1;
              dcache_rd_last  = 1'b1;
            end
            default: ;
          endcase
          state_next      = AXI_IDLE;
          active_src_next = SRC_NONE;
        end
      end

      // ---- Write Transaction ----
      AXI_WR_ADDR: begin
        m_axi_awaddr  = req_addr;
        m_axi_awvalid = 1'b1;
        if (m_axi_awready) begin
          state_next = AXI_WR_DATA;
        end
      end

      AXI_WR_DATA: begin
        m_axi_wdata  = wr_data_reg;
        m_axi_wstrb  = 4'b1111;
        m_axi_wvalid = 1'b1;
        if (m_axi_wready) begin
          state_next = AXI_WR_RESP;
        end
      end

      AXI_WR_RESP: begin
        m_axi_bready = 1'b1;
        if (m_axi_bvalid) begin
          dcache_wr_done  = 1'b1;
          state_next      = AXI_IDLE;
          active_src_next = SRC_NONE;
        end
      end

      default: state_next = AXI_IDLE;
    endcase
  end

endmodule
