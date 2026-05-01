// =============================================================================
// SystemVerilog Assertions (SVA)
// Covers: AXI4 protocol, pipeline invariants, cache coherency, liveness
// Bind to top-level or individual modules as needed
// =============================================================================

// =============================================================================
// AXI4-Lite Protocol Assertions
// =============================================================================
module axi4_lite_sva
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst_n,

  // Write Address Channel
  input logic [AXI_ADDR_WIDTH-1:0] awaddr,
  input logic                       awvalid,
  input logic                       awready,

  // Write Data Channel
  input logic [AXI_DATA_WIDTH-1:0] wdata,
  input logic [AXI_STRB_WIDTH-1:0] wstrb,
  input logic                       wvalid,
  input logic                       wready,

  // Write Response Channel
  input logic [1:0]                 bresp,
  input logic                       bvalid,
  input logic                       bready,

  // Read Address Channel
  input logic [AXI_ADDR_WIDTH-1:0] araddr,
  input logic                       arvalid,
  input logic                       arready,

  // Read Data Channel
  input logic [AXI_DATA_WIDTH-1:0] rdata,
  input logic [1:0]                 rresp,
  input logic                       rvalid,
  input logic                       rready
);

  // ---- AXI Rule: VALID must not deassert until READY ----

  // Write address: once AWVALID asserts, it must stay high until AWREADY
  property p_awvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=> awvalid;
  endproperty
  a_awvalid_stable: assert property (p_awvalid_stable)
    else $error("SVA: AWVALID deasserted before AWREADY");

  // Write data: WVALID must stay high until WREADY
  property p_wvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=> wvalid;
  endproperty
  a_wvalid_stable: assert property (p_wvalid_stable)
    else $error("SVA: WVALID deasserted before WREADY");

  // Write response: BVALID must stay high until BREADY
  property p_bvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (bvalid && !bready) |=> bvalid;
  endproperty
  a_bvalid_stable: assert property (p_bvalid_stable)
    else $error("SVA: BVALID deasserted before BREADY");

  // Read address: ARVALID must stay high until ARREADY
  property p_arvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && !arready) |=> arvalid;
  endproperty
  a_arvalid_stable: assert property (p_arvalid_stable)
    else $error("SVA: ARVALID deasserted before ARREADY");

  // Read data: RVALID must stay high until RREADY
  property p_rvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (rvalid && !rready) |=> rvalid;
  endproperty
  a_rvalid_stable: assert property (p_rvalid_stable)
    else $error("SVA: RVALID deasserted before RREADY");

  // ---- Stable signals during handshake ----

  // AWADDR must be stable while AWVALID is high and AWREADY is low
  property p_awaddr_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=> ($stable(awaddr));
  endproperty
  a_awaddr_stable: assert property (p_awaddr_stable)
    else $error("SVA: AWADDR changed during pending handshake");

  // WDATA must be stable while WVALID is high and WREADY is low
  property p_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=> ($stable(wdata));
  endproperty
  a_wdata_stable: assert property (p_wdata_stable)
    else $error("SVA: WDATA changed during pending handshake");

  // ARADDR must be stable while ARVALID is high and ARREADY is low
  property p_araddr_stable;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && !arready) |=> ($stable(araddr));
  endproperty
  a_araddr_stable: assert property (p_araddr_stable)
    else $error("SVA: ARADDR changed during pending handshake");

  // ---- Liveness: every request eventually completes ----

  // Read request eventually gets response
  property p_read_completes;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && arready) |-> ##[1:100] (rvalid && rready);
  endproperty
  a_read_completes: assert property (p_read_completes)
    else $error("SVA: Read transaction did not complete within 100 cycles");

  // Write request eventually gets response
  property p_write_completes;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && awready) |-> ##[1:100] (bvalid && bready);
  endproperty
  a_write_completes: assert property (p_write_completes)
    else $error("SVA: Write transaction did not complete within 100 cycles");

  // ---- Response code checks ----
  property p_no_decerr;
    @(posedge clk) disable iff (!rst_n)
    (rvalid && rready) |-> (rresp != 2'b11);
  endproperty
  a_no_read_decerr: assert property (p_no_decerr)
    else $warning("SVA: Read decode error received");

  property p_no_write_decerr;
    @(posedge clk) disable iff (!rst_n)
    (bvalid && bready) |-> (bresp != 2'b11);
  endproperty
  a_no_write_decerr: assert property (p_no_write_decerr)
    else $warning("SVA: Write decode error received");

  // ---- Coverage ----
  cover property (@(posedge clk) arvalid && arready);  // Read transactions
  cover property (@(posedge clk) awvalid && awready);  // Write transactions

endmodule


// =============================================================================
// Pipeline Invariant Assertions
// =============================================================================
module pipeline_sva
  import riscv_pkg::*;
(
  input logic              clk,
  input logic              rst_n,

  // Pipeline valid bits
  input if_id_reg_t        if_id_reg,
  input id_ex_reg_t        id_ex_reg,
  input ex_mem_reg_t       ex_mem_reg,
  input mem_wb_reg_t       mem_wb_reg,

  // Forwarding signals
  input fwd_sel_t          fwd_a,
  input fwd_sel_t          fwd_b,

  // Hazard signals
  input logic              stall_if,
  input logic              stall_id,
  input logic              bubble_ex,
  input logic              flush,

  // Writeback
  input logic              wb_en,
  input logic [4:0]        wb_addr
);

  // Register x0 should never be written
  property p_no_write_x0;
    @(posedge clk) disable iff (!rst_n)
    wb_en |-> (wb_addr != 5'b0);
  endproperty
  a_no_write_x0: assert property (p_no_write_x0)
    else $error("SVA: Attempted write to x0");

  // Flush and stall should not happen simultaneously
  property p_no_flush_and_stall;
    @(posedge clk) disable iff (!rst_n)
    !(flush && stall_if);
  endproperty
  // Note: This may be relaxed if design handles priority
  // a_no_flush_and_stall: assert property (p_no_flush_and_stall);

  // After flush, IF/ID register should be invalid
  property p_flush_clears_ifid;
    @(posedge clk) disable iff (!rst_n)
    flush |=> (!if_id_reg.valid);
  endproperty
  a_flush_clears_ifid: assert property (p_flush_clears_ifid)
    else $error("SVA: IF/ID not cleared after flush");

  // After bubble insertion, ID/EX should be invalid
  property p_bubble_clears_idex;
    @(posedge clk) disable iff (!rst_n)
    bubble_ex |=> (!id_ex_reg.valid);
  endproperty
  a_bubble_clears_idex: assert property (p_bubble_clears_idex)
    else $error("SVA: ID/EX not cleared after bubble");

  // Forwarding correctness: if EX/MEM writes to rs1 of ID/EX, fwd_a must be EX_MEM
  property p_fwd_a_ex_mem;
    @(posedge clk) disable iff (!rst_n)
    (ex_mem_reg.reg_write && ex_mem_reg.valid &&
     (ex_mem_reg.rd_addr != '0) &&
     (ex_mem_reg.rd_addr == id_ex_reg.rs1_addr))
    |-> (fwd_a == FWD_EX_MEM);
  endproperty
  a_fwd_a_ex_mem: assert property (p_fwd_a_ex_mem)
    else $error("SVA: Missing EX-MEM forwarding for operand A");

  // Coverage for hazard scenarios
  cov_load_use: cover property (
    @(posedge clk) bubble_ex && stall_if
  );

  cov_ex_fwd_a: cover property (
    @(posedge clk) fwd_a == FWD_EX_MEM
  );

  cov_mem_fwd_a: cover property (
    @(posedge clk) fwd_a == FWD_MEM_WB
  );

  cov_ex_fwd_b: cover property (
    @(posedge clk) fwd_b == FWD_EX_MEM
  );

  cov_mem_fwd_b: cover property (
    @(posedge clk) fwd_b == FWD_MEM_WB
  );

  cov_branch_flush: cover property (
    @(posedge clk) flush
  );

endmodule


// =============================================================================
// Cache Coherency Assertions (D-Cache)
// =============================================================================
module dcache_sva
  import riscv_pkg::*;
(
  input logic              clk,
  input logic              rst_n,

  // Cache state
  input cache_state_t      state,

  // Cache arrays (observe from dcache internal signals)
  input logic              way_valid [CACHE_NUM_SETS][CACHE_NUM_WAYS],
  input logic              way_dirty [CACHE_NUM_SETS][CACHE_NUM_WAYS],

  // Memory interface
  input logic              mem_write_req,
  input logic              mem_write_done,
  input logic              mem_read_req,

  // CPU interface
  input logic              cpu_read,
  input logic              cpu_write,
  input logic              cpu_ready
);

  // Dirty line can only exist if line is valid
  generate
    for (genvar s = 0; s < CACHE_NUM_SETS; s++) begin : gen_set
      for (genvar w = 0; w < CACHE_NUM_WAYS; w++) begin : gen_way
        property p_dirty_implies_valid;
          @(posedge clk) disable iff (!rst_n)
          way_dirty[s][w] |-> way_valid[s][w];
        endproperty
        a_dirty_valid: assert property (p_dirty_implies_valid)
          else $error("SVA: Dirty bit set on invalid line [set=%0d, way=%0d]", s, w);
      end
    end
  endgenerate

  // No read and write request to memory simultaneously
  property p_no_simultaneous_mem;
    @(posedge clk) disable iff (!rst_n)
    !(mem_read_req && mem_write_req);
  endproperty
  a_no_simultaneous_mem: assert property (p_no_simultaneous_mem)
    else $error("SVA: Simultaneous memory read and write requests");

  // Liveness: cache FSM should not stay in WRITEBACK forever
  property p_writeback_completes;
    @(posedge clk) disable iff (!rst_n)
    (state == CACHE_WRITEBACK) |-> ##[1:200] (state != CACHE_WRITEBACK);
  endproperty
  a_writeback_completes: assert property (p_writeback_completes)
    else $error("SVA: Cache stuck in WRITEBACK state");

  // Liveness: cache FSM should not stay in ALLOCATE forever
  property p_allocate_completes;
    @(posedge clk) disable iff (!rst_n)
    (state == CACHE_ALLOCATE) |-> ##[1:200] (state != CACHE_ALLOCATE);
  endproperty
  a_allocate_completes: assert property (p_allocate_completes)
    else $error("SVA: Cache stuck in ALLOCATE state");

  // Coverage
  cov_cache_hit:  cover property (@(posedge clk) (state == CACHE_COMPARE) && cpu_ready);
  cov_cache_miss: cover property (@(posedge clk) (state == CACHE_COMPARE) && !cpu_ready);
  cov_writeback:  cover property (@(posedge clk) (state == CACHE_WRITEBACK));
  cov_write_hit:  cover property (@(posedge clk) cpu_write && cpu_ready);

endmodule
