// =============================================================================
// L1 Data Cache
// 2-way set-associative, write-back with dirty bits, write-allocate policy
// LRU replacement, configurable via riscv_pkg parameters
// FSM states: IDLE -> COMPARE -> WRITEBACK -> ALLOCATE -> REFILL
// =============================================================================
module dcache
  import riscv_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,
 
  // CPU interface
  input  logic [XLEN-1:0]   cpu_addr,
  input  logic [XLEN-1:0]   cpu_wdata,
  input  logic               cpu_read,
  input  logic               cpu_write,
  input  logic [1:0]         cpu_width,   // byte/half/word
  output logic [XLEN-1:0]   cpu_rdata,
  output logic               cpu_ready,
 
  // Memory interface (to AXI controller)
  output logic [XLEN-1:0]   mem_addr,
  output logic [XLEN-1:0]   mem_wdata,
  output logic               mem_read_req,
  output logic               mem_write_req,
  input  logic [XLEN-1:0]   mem_rdata,
  input  logic               mem_valid,
  input  logic               mem_write_done,
 
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
  assign word_offset = addr_offset[CACHE_OFFSET_BITS-1:2];
 
  // -------------------------------------------------------------------------
  // Cache storage
  // -------------------------------------------------------------------------
  logic                          way_valid [CACHE_NUM_SETS][CACHE_NUM_WAYS];
  logic                          way_dirty [CACHE_NUM_SETS][CACHE_NUM_WAYS];
  logic [CACHE_TAG_BITS-1:0]     way_tag   [CACHE_NUM_SETS][CACHE_NUM_WAYS];
  logic [XLEN-1:0]               way_data  [CACHE_NUM_SETS][CACHE_NUM_WAYS][CACHE_LINE_WORDS];
  logic                          lru       [CACHE_NUM_SETS];
 
  // -------------------------------------------------------------------------
  // Hit detection
  // -------------------------------------------------------------------------
  logic hit_way0, hit_way1, cache_hit;
  logic hit_way_sel;
 
  assign hit_way0 = way_valid[addr_index][0] && (way_tag[addr_index][0] == addr_tag);
  assign hit_way1 = way_valid[addr_index][1] && (way_tag[addr_index][1] == addr_tag);
  assign cache_hit = hit_way0 || hit_way1;
  assign hit_way_sel = hit_way1;
 
  // -------------------------------------------------------------------------
  // Write byte-enable mask
  // -------------------------------------------------------------------------
  logic [3:0] byte_en;
  always_comb begin
    case (cpu_width)
      2'b00:   byte_en = 4'b0001 << addr_offset[1:0]; // byte
      2'b01:   byte_en = 4'b0011 << addr_offset[1:0]; // half
      default: byte_en = 4'b1111;                       // word
    endcase
  end
 
  // Merge write data into existing word
  function automatic logic [XLEN-1:0] merge_write(
    input logic [XLEN-1:0] old_data,
    input logic [XLEN-1:0] new_data,
    input logic [3:0]      be
  );
    logic [XLEN-1:0] merged;
    for (int i = 0; i < 4; i++)
      merged[i*8 +: 8] = be[i] ? new_data[i*8 +: 8] : old_data[i*8 +: 8];
    return merged;
  endfunction
 
  // -------------------------------------------------------------------------
  // FSM
  // -------------------------------------------------------------------------
  cache_state_t state, state_next;
 
  logic [$clog2(CACHE_LINE_WORDS)-1:0] transfer_cnt, transfer_cnt_next;
  logic replace_way, replace_way_next;
  logic need_writeback;
 
  // Determine if evicted line is dirty
  assign need_writeback = way_valid[addr_index][lru[addr_index]] &&
                          way_dirty[addr_index][lru[addr_index]];
 
  assign cache_active = (state != CACHE_IDLE) || cpu_read || cpu_write;
 
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= CACHE_IDLE;
      transfer_cnt <= '0;
      replace_way  <= '0;
    end else begin
      state        <= state_next;
      transfer_cnt <= transfer_cnt_next;
      replace_way  <= replace_way_next;
    end
  end
 
  // Registered address for writeback
  logic [XLEN-1:0] wb_base_addr;
  always_ff @(posedge clk) begin
    if (state == CACHE_COMPARE && !cache_hit) begin
      wb_base_addr <= {way_tag[addr_index][lru[addr_index]],
                       addr_index, {CACHE_OFFSET_BITS{1'b0}}};
    end
  end
 
  always_comb begin
    state_next        = state;
    transfer_cnt_next = transfer_cnt;
    replace_way_next  = replace_way;
    cpu_ready         = 1'b0;
    cpu_rdata         = '0;
    mem_addr          = '0;
    mem_wdata         = '0;
    mem_read_req      = 1'b0;
    mem_write_req     = 1'b0;
 
    case (state)
      CACHE_IDLE: begin
        if (cpu_read || cpu_write)
          state_next = CACHE_COMPARE;
      end
 
      CACHE_COMPARE: begin
        if (cache_hit) begin
          // --- HIT ---
          if (cpu_read) begin
            cpu_rdata = way_data[addr_index][hit_way_sel][word_offset];
          end
          cpu_ready  = 1'b1;
          state_next = CACHE_IDLE;
        end else begin
          // --- MISS ---
          replace_way_next  = lru[addr_index];
          transfer_cnt_next = '0;
          if (need_writeback)
            state_next = CACHE_WRITEBACK;
          else
            state_next = CACHE_ALLOCATE;
        end
      end
 
      CACHE_WRITEBACK: begin
        // Write dirty line back to memory
        mem_write_req = 1'b1;
        mem_addr  = wb_base_addr + {transfer_cnt, 2'b00};
        mem_wdata = way_data[addr_index][replace_way][transfer_cnt];
 
        if (mem_write_done) begin
          if (transfer_cnt == CACHE_LINE_WORDS[$clog2(CACHE_LINE_WORDS)-1:0] - 1) begin
            transfer_cnt_next = '0;
            state_next = CACHE_ALLOCATE;
          end else begin
            transfer_cnt_next = transfer_cnt + 1'b1;
          end
        end
      end
 
      CACHE_ALLOCATE: begin
        // Fetch new line from memory
        mem_read_req = 1'b1;
        mem_addr = {cpu_addr[XLEN-1:CACHE_OFFSET_BITS], {CACHE_OFFSET_BITS{1'b0}}} +
                   {transfer_cnt, 2'b00};
 
        if (mem_valid) begin
          if (transfer_cnt == CACHE_LINE_WORDS[$clog2(CACHE_LINE_WORDS)-1:0] - 1) begin
            state_next = CACHE_COMPARE;  // Re-enter compare (will now hit)
            transfer_cnt_next = '0;
          end else begin
            transfer_cnt_next = transfer_cnt + 1'b1;
          end
        end
      end
 
      CACHE_REFILL: begin
        // Unused in this implementation (ALLOCATE handles it)
        state_next = CACHE_IDLE;
      end
 
      default: state_next = CACHE_IDLE;
    endcase
  end
 
  // -------------------------------------------------------------------------
  // Cache update logic
  // -------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < CACHE_NUM_SETS; s++) begin
        for (int w = 0; w < CACHE_NUM_WAYS; w++) begin
          way_valid[s][w] <= 1'b0;
          way_dirty[s][w] <= 1'b0;
          way_tag[s][w]   <= '0;
        end
        lru[s] <= 1'b0;
      end
    end else begin
      // Allocate: write incoming data
      if (state == CACHE_ALLOCATE && mem_valid) begin
        way_data[addr_index][replace_way][transfer_cnt] <= mem_rdata;
        if (transfer_cnt == CACHE_LINE_WORDS[$clog2(CACHE_LINE_WORDS)-1:0] - 1) begin
          way_valid[addr_index][replace_way] <= 1'b1;
          way_dirty[addr_index][replace_way] <= 1'b0;
          way_tag[addr_index][replace_way]   <= addr_tag;
        end
      end
 
      // Writeback: clear dirty on completion
      if (state == CACHE_WRITEBACK && mem_write_done &&
          (transfer_cnt == CACHE_LINE_WORDS[$clog2(CACHE_LINE_WORDS)-1:0] - 1)) begin
        way_dirty[addr_index][replace_way] <= 1'b0;
      end
 
      // Write hit: update data and set dirty
      if (state == CACHE_COMPARE && cache_hit && cpu_write) begin
        way_data[addr_index][hit_way_sel][word_offset] <=
          merge_write(way_data[addr_index][hit_way_sel][word_offset],
                      cpu_wdata, byte_en);
        way_dirty[addr_index][hit_way_sel] <= 1'b1;
      end
 
      // LRU update on hit
      if (state == CACHE_COMPARE && cache_hit) begin
        lru[addr_index] <= hit_way_sel ? 1'b0 : 1'b1;
      end
    end
  end
 
endmodule