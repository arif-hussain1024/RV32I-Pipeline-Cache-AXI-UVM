// =============================================================================
// Top-Level Testbench
// Instantiates DUT, interfaces, memory model, and UVM components
// =============================================================================
module tb_top;
  import uvm_pkg::*;
  import riscv_pkg::*;

  `include "uvm_macros.svh"

  // =========================================================================
  // Clock and Reset
  // =========================================================================
  logic clk;
  logic rst_n;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100 MHz
  end

  initial begin
    rst_n = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;
  end

  // =========================================================================
  // AXI4-Lite Interface
  // =========================================================================
  axi4_lite_if axi_if (.clk(clk), .rst_n(rst_n));

  // =========================================================================
  // DUT Instantiation
  // =========================================================================
  riscv_soc_top u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .test_en       (1'b0),
    // AXI4-Lite connections
    .m_axi_awaddr  (axi_if.m_awaddr),
    .m_axi_awvalid (axi_if.m_awvalid),
    .m_axi_awready (axi_if.s_awready),
    .m_axi_awprot  (axi_if.m_awprot),
    .m_axi_wdata   (axi_if.m_wdata),
    .m_axi_wstrb   (axi_if.m_wstrb),
    .m_axi_wvalid  (axi_if.m_wvalid),
    .m_axi_wready  (axi_if.s_wready),
    .m_axi_bresp   (axi_if.s_bresp),
    .m_axi_bvalid  (axi_if.s_bvalid),
    .m_axi_bready  (axi_if.m_bready),
    .m_axi_araddr  (axi_if.m_araddr),
    .m_axi_arvalid (axi_if.m_arvalid),
    .m_axi_arready (axi_if.s_arready),
    .m_axi_arprot  (axi_if.m_arprot),
    .m_axi_rdata   (axi_if.s_rdata),
    .m_axi_rresp   (axi_if.s_rresp),
    .m_axi_rvalid  (axi_if.s_rvalid),
    .m_axi_rready  (axi_if.m_rready)
  );

  // =========================================================================
  // SVA Bind Statements
  // =========================================================================

  // Bind AXI4-Lite assertions to the AXI interface
  bind axi4_lite_if axi4_lite_sva u_axi_sva (
    .clk      (clk),
    .rst_n    (rst_n),
    .awaddr   (m_awaddr),
    .awvalid  (m_awvalid),
    .awready  (s_awready),
    .wdata    (m_wdata),
    .wstrb    (m_wstrb),
    .wvalid   (m_wvalid),
    .wready   (s_wready),
    .bresp    (s_bresp),
    .bvalid   (s_bvalid),
    .bready   (m_bready),
    .araddr   (m_araddr),
    .arvalid  (m_arvalid),
    .arready  (s_arready),
    .rdata    (s_rdata),
    .rresp    (s_rresp),
    .rvalid   (s_rvalid),
    .rready   (m_rready)
  );

  // =========================================================================
  // UVM Configuration and Run
  // =========================================================================
  initial begin
    // Register virtual interface
    uvm_config_db#(virtual axi4_lite_if)::set(null, "*", "vif", axi_if);

    // Dump waveforms
    $dumpfile("riscv_soc.vcd");
    $dumpvars(0, tb_top);

    // Run UVM test
    run_test();
  end

  // Timeout watchdog
  initial begin
    #1000000;
    `uvm_fatal("TIMEOUT", "Simulation timeout - possible deadlock")
  end

endmodule
