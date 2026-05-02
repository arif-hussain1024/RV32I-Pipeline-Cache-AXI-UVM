// =============================================================================
// L1 Instruction Cache
// 2-way set-associative, read-only, LRU replacement
// Configurable via riscv_pkg parameters
// =============================================================================
module icache
  import riscv_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,
 
  // CPU interface
  input  logic [XLEN-1:0]   cpu_addr,
  input  logic               cpu_req,
  output logic [XLEN-1:0]   cpu_rdata,
  output logic               cpu_ready,
 
  // Memory interface (to AXI controller)
  output logic [XLEN-1:0]   mem_addr,
  output logic               mem_req,
  input  logic               mem_valid,
  input  logic [XLEN-1:0]   mem_rdata,
 
  // Status
  output logic               cache_active
);
 
  // -------------------------------------------------------------------------
  // Address decomposition
  // -------------------------------------------------------------------------
  logic [CACHE_TAG_BITS-1:0]    addr_tag;
  logic [CACHE_INDEX_BITS-1:0]  addr_index;
  logic [CACHE_OFFSET_BITS-1:0] addr_offset;
  logic [1:0]                   word_offset;
 
  assign addr_tag    = cpu_addr[XLEN-1 -: CACHE_TAG_BITS];
  assign addr_index  = cpu_addr[CACHE_OFFSET_BITS +: CACHE_INDEX_BITS];
  assign addr_offset = cpu_addr[CACHE_OFFSET_BITS-1:0];
  assign word_offset = addr_offset[CACHE_OFFSET_BITS-1:2];  // Word select within line
 
  // -------------------------------------------------------------------------
  // Cache storage
  // -------------------------------------------------------------------------
  logic                          way_valid [CACHE_NUM_SETS][CACHE_NUM_WAYS];
  logic [CACHE_TAG_BITS-1:0]     way_tag   [CACHE_NUM_SETS][CACHE_NUM_WAYS];
  logic [XLEN-1:0]               way_data  [CACHE_NUM_SETS][CACHE_NUM_WAYS][CACHE_LINE_WORDS];
  logic                          lru       [CACHE_NUM_SETS];  // 0=way0 is LRU, 1=way1 is LRU
 
  // -------------------------------------------------------------------------
  // Hit detection
  // -------------------------------------------------------------------------
  logic hit_way0, hit_way1, cache_hit;
  logic hit_way_sel;
 
  assign hit_way0 = way_valid[addr_index][0] && (way_tag[addr_index][0] == addr_tag);
  assign hit_way1 = way_valid[addr_index][1] && (way_tag[addr_index][1] == addr_tag);
  assign cache_hit = hit_way0 || hit_way1;
  assign hit_way_sel = hit_way1;  // 0=way0 hit, 1=way1 hit
 
  // -------------------------------------------------------------------------
  // FSM
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    S_IDLE,
    S_COMPARE,
    S_REFILL
  } icache_state_t;
 
  icache_state_t state, state_next;
  logic [$clog2(CACHE_LINE_WORDS)-1:0] refill_cnt, refill_cnt_next;
  logic replace_way, replace_way_next;
  logic [XLEN-1:0] refill_addr;
 
  assign cache_active = (state != S_IDLE) || cpu_req;
 
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= S_IDLE;
      refill_cnt <= '0;
      replace_way <= '0;
    end else begin
      state      <= state_next;
      refill_cnt <= refill_cnt_next;
      replace_way <= replace_way_next;
    end
  end
 
  always_comb begin
    state_next       = state;
    refill_cnt_next  = refill_cnt;
    replace_way_next = replace_way;
    cpu_ready        = 1'b0;
    cpu_rdata        = '0;
    mem_req          = 1'b0;
    mem_addr         = '0;
 
    case (state)
      S_IDLE: begin
        if (cpu_req)
          state_next = S_COMPARE;
      end
 
      S_COMPARE: begin
        if (cache_hit) begin
          // Cache hit - return data
          cpu_rdata = way_data[addr_index][hit_way_sel][word_offset];
          cpu_ready = 1'b1;
          state_next = S_IDLE;
        end else begin
          // Cache miss - start refill
          replace_way_next = lru[addr_index];
          refill_cnt_next  = '0;
          state_next       = S_REFILL;
        end
      end
 
      S_REFILL: begin
        // Request words from memory
        mem_req  = 1'b1;
        // Aligned to cache line boundary
        mem_addr = {cpu_addr[XLEN-1:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}} +
                   {refill_cnt, 2'b00};
 
        if (mem_valid) begin
          if (refill_cnt == CACHE_LINE_WORDS[$clog2(CACHE_LINE_WORDS)-1:0] - 1) begin
            state_next = S_COMPARE;  // Re-check for hit after refill
            refill_cnt_next = '0;
          end else begin
            refill_cnt_next = refill_cnt + 1'b1;
          end
        end
      end
 
      default: state_next = S_IDLE;
    endcase
  end
 
  // -------------------------------------------------------------------------
  // Cache line fill and LRU update
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < CACHE_NUM_SETS; s++) begin
        for (int w = 0; w < CACHE_NUM_WAYS; w++) begin
          way_valid[s][w] <= 1'b0;
          way_tag[s][w]   <= '0;
        end
        lru[s] <= 1'b0;
      end
    end else begin
      // Refill: write incoming data word
      if (state == S_REFILL && mem_valid) begin
        way_data[addr_index][replace_way][refill_cnt] <= mem_rdata;
        // On last word, validate the line
        if (refill_cnt == CACHE_LINE_WORDS[$clog2(CACHE_LINE_WORDS)-1:0] - 1) begin
          way_valid[addr_index][replace_way] <= 1'b1;
          way_tag[addr_index][replace_way]   <= addr_tag;
        end
      end
      // LRU update on hit
      if (state == S_COMPARE && cache_hit) begin
        lru[addr_index] <= hit_way_sel ? 1'b0 : 1'b1;
      end
    end
  end
 
endmodule