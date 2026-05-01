// =============================================================================
// RISC-V SoC Top Level
// Integrates: RV32I Core, I-Cache, D-Cache, AXI4-Lite Master, Clock Gating
// =============================================================================
module riscv_soc_top
  import riscv_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              test_en,      // Scan test mode

  // AXI4-Lite Master Interface to external memory/peripherals
  output logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
  output logic                        m_axi_awvalid,
  input  logic                        m_axi_awready,
  output logic [2:0]                  m_axi_awprot,

  output logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
  output logic [AXI_STRB_WIDTH-1:0]  m_axi_wstrb,
  output logic                        m_axi_wvalid,
  input  logic                        m_axi_wready,

  input  logic [1:0]                  m_axi_bresp,
  input  logic                        m_axi_bvalid,
  output logic                        m_axi_bready,

  output logic [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
  output logic                        m_axi_arvalid,
  input  logic                        m_axi_arready,
  output logic [2:0]                  m_axi_arprot,

  input  logic [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
  input  logic [1:0]                  m_axi_rresp,
  input  logic                        m_axi_rvalid,
  output logic                        m_axi_rready
);

  // =========================================================================
  // Internal wires
  // =========================================================================

  // Core <-> I-Cache
  logic [XLEN-1:0] core_imem_addr;
  logic [XLEN-1:0] icache_cpu_rdata;
  logic             core_imem_req;
  logic             icache_cpu_ready;

  // Core <-> D-Cache
  logic [XLEN-1:0] core_dmem_addr;
  logic [XLEN-1:0] core_dmem_wdata;
  logic [XLEN-1:0] dcache_cpu_rdata;
  logic             core_dmem_read;
  logic             core_dmem_write;
  logic [1:0]       core_dmem_width;
  logic             dcache_cpu_ready;

  // I-Cache <-> AXI
  logic [XLEN-1:0] icache_mem_addr;
  logic             icache_mem_req;
  logic [XLEN-1:0] icache_mem_rdata;
  logic             icache_mem_valid;
  logic             icache_mem_last;

  // D-Cache <-> AXI (read)
  logic [XLEN-1:0] dcache_mem_rd_addr;
  logic             dcache_mem_rd_req;
  logic [XLEN-1:0] dcache_mem_rdata;
  logic             dcache_mem_rd_valid;
  logic             dcache_mem_rd_last;

  // D-Cache <-> AXI (write)
  logic [XLEN-1:0] dcache_mem_wr_addr;
  logic [XLEN-1:0] dcache_mem_wr_data;
  logic             dcache_mem_wr_req;
  logic             dcache_mem_wr_done;

  // Clock gating signals
  logic ex_stage_active, mem_stage_active;
  logic icache_active, dcache_active;
  logic clk_ex, clk_mem, clk_icache, clk_dcache;

  // =========================================================================
  // Clock Gating Controller
  // =========================================================================
  clock_gating_ctrl u_cg_ctrl (
    .clk              (clk),
    .rst_n            (rst_n),
    .test_en          (test_en),
    .ex_stage_active  (ex_stage_active),
    .mem_stage_active (mem_stage_active),
    .icache_active    (icache_active),
    .dcache_active    (dcache_active),
    .clk_ex           (clk_ex),
    .clk_mem          (clk_mem),
    .clk_icache       (clk_icache),
    .clk_dcache       (clk_dcache)
  );

  // =========================================================================
  // RISC-V Core (5-stage pipeline)
  // Note: Core uses ungated clk for IF/ID/WB stages; EX/MEM use gated clocks
  // For simplicity in this version, core runs on main clock; clock gating
  // is applied to cache subsystems. Pipeline-internal gating can be added
  // by splitting the core into individual stage modules.
  // =========================================================================
  riscv_core u_core (
    .clk              (clk),
    .rst_n            (rst_n),
    .imem_addr        (core_imem_addr),
    .imem_rdata       (icache_cpu_rdata),
    .imem_req         (core_imem_req),
    .imem_ready       (icache_cpu_ready),
    .dmem_addr        (core_dmem_addr),
    .dmem_wdata       (core_dmem_wdata),
    .dmem_rdata       (dcache_cpu_rdata),
    .dmem_read        (core_dmem_read),
    .dmem_write       (core_dmem_write),
    .dmem_width       (core_dmem_width),
    .dmem_ready       (dcache_cpu_ready),
    .ex_stage_active  (ex_stage_active),
    .mem_stage_active (mem_stage_active)
  );

  // =========================================================================
  // L1 Instruction Cache
  // =========================================================================
  icache u_icache (
    .clk          (clk),  // Can use clk_icache for gated version
    .rst_n        (rst_n),
    .cpu_addr     (core_imem_addr),
    .cpu_req      (core_imem_req),
    .cpu_rdata    (icache_cpu_rdata),
    .cpu_ready    (icache_cpu_ready),
    .mem_addr     (icache_mem_addr),
    .mem_req      (icache_mem_req),
    .mem_valid    (icache_mem_valid),
    .mem_rdata    (icache_mem_rdata),
    .mem_last     (icache_mem_last),
    .cache_active (icache_active)
  );

  // =========================================================================
  // L1 Data Cache
  // =========================================================================
  dcache u_dcache (
    .clk            (clk),  // Can use clk_dcache for gated version
    .rst_n          (rst_n),
    .cpu_addr       (core_dmem_addr),
    .cpu_wdata      (core_dmem_wdata),
    .cpu_read       (core_dmem_read),
    .cpu_write      (core_dmem_write),
    .cpu_width      (core_dmem_width),
    .cpu_rdata      (dcache_cpu_rdata),
    .cpu_ready      (dcache_cpu_ready),
    .mem_addr       (dcache_mem_rd_addr),  // Read and write share for now
    .mem_wdata      (dcache_mem_wr_data),
    .mem_read_req   (dcache_mem_rd_req),
    .mem_write_req  (dcache_mem_wr_req),
    .mem_rdata      (dcache_mem_rdata),
    .mem_valid      (dcache_mem_rd_valid),
    .mem_last       (dcache_mem_rd_last),
    .mem_write_done (dcache_mem_wr_done),
    .cache_active   (dcache_active)
  );

  // D-Cache address routing
  assign dcache_mem_wr_addr = dcache_mem_rd_addr;  // Same port in dcache

  // =========================================================================
  // AXI4-Lite Master
  // =========================================================================
  axi4_lite_master u_axi_master (
    .clk              (clk),
    .rst_n            (rst_n),
    // I-Cache
    .icache_addr      (icache_mem_addr),
    .icache_req       (icache_mem_req),
    .icache_rdata     (icache_mem_rdata),
    .icache_valid     (icache_mem_valid),
    .icache_last      (icache_mem_last),
    // D-Cache read
    .dcache_rd_addr   (dcache_mem_rd_addr),
    .dcache_rd_req    (dcache_mem_rd_req),
    .dcache_rdata     (dcache_mem_rdata),
    .dcache_rd_valid  (dcache_mem_rd_valid),
    .dcache_rd_last   (dcache_mem_rd_last),
    // D-Cache write
    .dcache_wr_addr   (dcache_mem_wr_addr),
    .dcache_wr_data   (dcache_mem_wr_data),
    .dcache_wr_req    (dcache_mem_wr_req),
    .dcache_wr_done   (dcache_mem_wr_done),
    // AXI4-Lite
    .m_axi_awaddr     (m_axi_awaddr),
    .m_axi_awvalid    (m_axi_awvalid),
    .m_axi_awready    (m_axi_awready),
    .m_axi_awprot     (m_axi_awprot),
    .m_axi_wdata      (m_axi_wdata),
    .m_axi_wstrb      (m_axi_wstrb),
    .m_axi_wvalid     (m_axi_wvalid),
    .m_axi_wready     (m_axi_wready),
    .m_axi_bresp      (m_axi_bresp),
    .m_axi_bvalid     (m_axi_bvalid),
    .m_axi_bready     (m_axi_bready),
    .m_axi_araddr     (m_axi_araddr),
    .m_axi_arvalid    (m_axi_arvalid),
    .m_axi_arready    (m_axi_arready),
    .m_axi_arprot     (m_axi_arprot),
    .m_axi_rdata      (m_axi_rdata),
    .m_axi_rresp      (m_axi_rresp),
    .m_axi_rvalid     (m_axi_rvalid),
    .m_axi_rready     (m_axi_rready)
  );

endmodule
