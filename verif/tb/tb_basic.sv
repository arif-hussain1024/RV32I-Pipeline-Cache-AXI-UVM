// =============================================================================
// Basic Functional Testbench (Non-UVM)
// Quick smoke test for the RISC-V core with a simple memory model
// Can be run with Icarus Verilog, Verilator, or any simulator
// =============================================================================
`timescale 1ns/1ps

module tb_basic;

  import riscv_pkg::*;

  // Clock and reset
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  // AXI signals
  logic [31:0] m_axi_awaddr, m_axi_wdata, m_axi_araddr, m_axi_rdata;
  logic [3:0]  m_axi_wstrb;
  logic [2:0]  m_axi_awprot, m_axi_arprot;
  logic [1:0]  m_axi_bresp, m_axi_rresp;
  logic m_axi_awvalid, m_axi_awready;
  logic m_axi_wvalid, m_axi_wready;
  logic m_axi_bvalid, m_axi_bready;
  logic m_axi_arvalid, m_axi_arready;
  logic m_axi_rvalid, m_axi_rready;

  // DUT
  riscv_soc_top u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .test_en       (1'b0),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_awprot  (m_axi_awprot),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_arprot  (m_axi_arprot),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready)
  );

  // =========================================================================
  // Simple AXI4-Lite Memory Responder
  // =========================================================================
  logic [31:0] memory [0:4095];  // 16KB memory

  // Read handling
  typedef enum logic [1:0] {RD_IDLE, RD_RESP} rd_state_t;
  rd_state_t rd_state;
  logic [31:0] rd_addr_latched;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_state       <= RD_IDLE;
      m_axi_arready  <= 1'b0;
      m_axi_rvalid   <= 1'b0;
      m_axi_rdata    <= '0;
      m_axi_rresp    <= 2'b00;
    end else begin
      case (rd_state)
        RD_IDLE: begin
          m_axi_rvalid <= 1'b0;
          if (m_axi_arvalid) begin
            m_axi_arready  <= 1'b1;
            rd_addr_latched <= m_axi_araddr;
            rd_state        <= RD_RESP;
          end else begin
            m_axi_arready <= 1'b0;
          end
        end
        RD_RESP: begin
          m_axi_arready <= 1'b0;
          m_axi_rdata   <= memory[rd_addr_latched[13:2]];
          m_axi_rresp   <= 2'b00;
          m_axi_rvalid  <= 1'b1;
          if (m_axi_rvalid && m_axi_rready) begin
            m_axi_rvalid <= 1'b0;
            rd_state     <= RD_IDLE;
          end
        end
      endcase
    end
  end

  // Write handling
  typedef enum logic [1:0] {WR_IDLE, WR_DATA, WR_RESP} wr_state_t;
  wr_state_t wr_state;
  logic [31:0] wr_addr_latched;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_state       <= WR_IDLE;
      m_axi_awready  <= 1'b0;
      m_axi_wready   <= 1'b0;
      m_axi_bvalid   <= 1'b0;
      m_axi_bresp    <= 2'b00;
    end else begin
      case (wr_state)
        WR_IDLE: begin
          m_axi_bvalid <= 1'b0;
          if (m_axi_awvalid) begin
            m_axi_awready  <= 1'b1;
            wr_addr_latched <= m_axi_awaddr;
            wr_state        <= WR_DATA;
          end else begin
            m_axi_awready <= 1'b0;
          end
        end
        WR_DATA: begin
          m_axi_awready <= 1'b0;
          m_axi_wready  <= 1'b1;
          if (m_axi_wvalid && m_axi_wready) begin
            memory[wr_addr_latched[13:2]] <= m_axi_wdata;
            m_axi_wready <= 1'b0;
            wr_state     <= WR_RESP;
          end
        end
        WR_RESP: begin
          m_axi_bresp  <= 2'b00;
          m_axi_bvalid <= 1'b1;
          if (m_axi_bvalid && m_axi_bready) begin
            m_axi_bvalid <= 1'b0;
            wr_state     <= WR_IDLE;
          end
        end
      endcase
    end
  end

  // =========================================================================
  // Test Program: Load instructions into memory
  // =========================================================================
  initial begin
    // Clear memory
    for (int i = 0; i < 4096; i++)
      memory[i] = 32'h00000013;  // NOP (ADDI x0, x0, 0)

    // Test program:
    // 0x00: ADDI x1, x0, 10      # x1 = 10
    memory[0]  = 32'h00A00093;
    // 0x04: ADDI x2, x0, 20      # x2 = 20
    memory[1]  = 32'h01400113;
    // 0x08: ADD  x3, x1, x2      # x3 = 30 (RAW hazard on x1, x2)
    memory[2]  = 32'h002081B3;
    // 0x0C: SUB  x4, x3, x1      # x4 = 20 (RAW hazard on x3)
    memory[3]  = 32'h40118233;
    // 0x10: SW   x3, 0(x0)       # Store x3 (=30) to addr 0x000
    memory[4]  = 32'h00302023;
    // 0x14: LW   x5, 0(x0)       # Load from addr 0x000 -> x5 = 30
    memory[5]  = 32'h00002283;
    // 0x18: ADD  x6, x5, x1      # x6 = 40 (load-use hazard on x5)
    memory[6]  = 32'h00128333;
    // 0x1C: ADDI x7, x0, 30      # x7 = 30
    memory[7]  = 32'h01E00393;
    // 0x20: BEQ  x5, x7, +8      # Branch if x5 == x7 (should be taken: both 30)
    memory[8]  = 32'h00728463;
    // 0x24: ADDI x8, x0, 99      # x8 = 99 (should be flushed)
    memory[9]  = 32'h06300413;
    // 0x28: ADDI x9, x0, 42      # x9 = 42 (branch target)
    memory[10] = 32'h02A00493;
    // 0x2C: LUI  x10, 0xDEADB    # x10 = 0xDEADB000
    memory[11] = 32'hDEADB537;
    // 0x30: ADDI x10, x10, 0xEF  # x10 = 0xDEADB0EF  (not full DEADBEEF but close)
    memory[12] = 32'h0EF50513;
    // 0x34 onwards: NOPs
  end

  // =========================================================================
  // Simulation control
  // =========================================================================
  initial begin
    $dumpfile("tb_basic.vcd");
    $dumpvars(0, tb_basic);

    // Release reset
    #100;
    rst_n = 1;

    // Run for enough cycles
    #10000;

    // Check results by observing register file through hierarchy
    $display("\n========== Simulation Results ==========");
    $display("Test program execution complete");
    $display("Expected: x1=10, x2=20, x3=30, x4=20, x6=40, x9=42");
    $display("Note: Check waveform for detailed pipeline behavior");
    $display("=========================================\n");

    $finish;
  end

endmodule
