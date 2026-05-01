// =============================================================================
// Clock Gating Cell (ICG - Integrated Clock Gating)
// Latch-based implementation for glitch-free gated clock
// =============================================================================
module clock_gate_cell (
  input  logic clk,
  input  logic enable,
  input  logic test_en,    // Scan test override (disable gating during scan)
  output logic gated_clk
);

  logic latch_out;

  // Negative-edge latch to hold enable during high phase
  // This prevents glitches on the gated clock
  always_latch begin
    if (!clk)
      latch_out = enable | test_en;
  end

  assign gated_clk = clk & latch_out;

endmodule

// =============================================================================
// Clock Gating Controller
// Generates enable signals for gating idle pipeline stages and cache
// =============================================================================
module clock_gating_ctrl
  import riscv_pkg::*;
(
  input  logic clk,
  input  logic rst_n,
  input  logic test_en,

  // Pipeline activity signals
  input  logic ex_stage_active,
  input  logic mem_stage_active,

  // Cache activity signals
  input  logic icache_active,
  input  logic dcache_active,

  // Gated clocks
  output logic clk_ex,       // Execute stage gated clock
  output logic clk_mem,      // Memory stage gated clock
  output logic clk_icache,   // I-Cache gated clock
  output logic clk_dcache    // D-Cache gated clock
);

  // Execute stage: gate when no valid instruction in EX
  clock_gate_cell u_cg_ex (
    .clk       (clk),
    .enable    (ex_stage_active),
    .test_en   (test_en),
    .gated_clk (clk_ex)
  );

  // Memory stage: gate when no memory operation
  clock_gate_cell u_cg_mem (
    .clk       (clk),
    .enable    (mem_stage_active),
    .test_en   (test_en),
    .gated_clk (clk_mem)
  );

  // I-Cache: gate when no active request or refill
  clock_gate_cell u_cg_icache (
    .clk       (clk),
    .enable    (icache_active),
    .test_en   (test_en),
    .gated_clk (clk_icache)
  );

  // D-Cache: gate when no active request, writeback, or refill
  clock_gate_cell u_cg_dcache (
    .clk       (clk),
    .enable    (dcache_active),
    .test_en   (test_en),
    .gated_clk (clk_dcache)
  );

endmodule
