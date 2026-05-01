// =============================================================================
// AXI4-Lite UVM Driver (Slave side - memory responder)
// Responds to AXI read/write requests from the DUT master
// =============================================================================
class axi4_lite_driver extends uvm_driver #(axi4_lite_txn);
  `uvm_component_utils(axi4_lite_driver)

  virtual axi4_lite_if vif;

  // Simple memory model
  logic [31:0] memory [logic [31:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  task run_phase(uvm_phase phase);
    // Initialize
    vif.s_arready <= 1'b0;
    vif.s_rvalid  <= 1'b0;
    vif.s_rdata   <= '0;
    vif.s_rresp   <= '0;
    vif.s_awready <= 1'b0;
    vif.s_wready  <= 1'b0;
    vif.s_bvalid  <= 1'b0;
    vif.s_bresp   <= '0;

    @(posedge vif.rst_n);

    fork
      handle_reads();
      handle_writes();
    join
  endtask

  task handle_reads();
    forever begin
      @(posedge vif.clk);
      if (vif.m_arvalid) begin
        // Accept read address
        vif.s_arready <= 1'b1;
        @(posedge vif.clk);
        vif.s_arready <= 1'b0;

        // Respond with data (1-cycle latency)
        repeat ($urandom_range(0, 2)) @(posedge vif.clk);  // Random delay

        if (memory.exists(vif.m_araddr))
          vif.s_rdata <= memory[vif.m_araddr];
        else
          vif.s_rdata <= '0;

        vif.s_rresp  <= 2'b00;  // OKAY
        vif.s_rvalid <= 1'b1;

        // Wait for RREADY
        while (!vif.m_rready) @(posedge vif.clk);
        @(posedge vif.clk);
        vif.s_rvalid <= 1'b0;
      end
    end
  endtask

  task handle_writes();
    logic [31:0] wr_addr;
    forever begin
      @(posedge vif.clk);
      if (vif.m_awvalid) begin
        // Accept write address
        wr_addr = vif.m_awaddr;
        vif.s_awready <= 1'b1;
        @(posedge vif.clk);
        vif.s_awready <= 1'b0;

        // Wait for write data
        while (!vif.m_wvalid) @(posedge vif.clk);
        vif.s_wready <= 1'b1;

        // Store data
        memory[wr_addr] = vif.m_wdata;

        @(posedge vif.clk);
        vif.s_wready <= 1'b0;

        // Send write response
        repeat ($urandom_range(0, 1)) @(posedge vif.clk);
        vif.s_bresp  <= 2'b00;  // OKAY
        vif.s_bvalid <= 1'b1;

        while (!vif.m_bready) @(posedge vif.clk);
        @(posedge vif.clk);
        vif.s_bvalid <= 1'b0;
      end
    end
  endtask

  // Preload memory (for instruction loading)
  function void preload(logic [31:0] addr, logic [31:0] data);
    memory[addr] = data;
  endfunction

endclass
