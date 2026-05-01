// =============================================================================
// AXI4-Lite UVM Monitor
// Observes AXI transactions and sends to scoreboard via analysis port
// =============================================================================
class axi4_lite_monitor extends uvm_monitor;
  `uvm_component_utils(axi4_lite_monitor)

  virtual axi4_lite_if vif;
  uvm_analysis_port #(axi4_lite_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_reads();
      monitor_writes();
    join
  endtask

  task monitor_reads();
    axi4_lite_txn txn;
    forever begin
      @(posedge vif.clk);
      if (vif.m_arvalid && vif.s_arready) begin
        txn = axi4_lite_txn::type_id::create("rd_txn");
        txn.addr     = vif.m_araddr;
        txn.is_write = 1'b0;

        // Wait for read data
        @(posedge vif.clk);
        while (!(vif.s_rvalid && vif.m_rready)) @(posedge vif.clk);
        txn.data = vif.s_rdata;
        txn.resp = vif.s_rresp;

        ap.write(txn);
        `uvm_info("AXI_MON", $sformatf("RD: addr=0x%08h data=0x%08h resp=%0d",
                  txn.addr, txn.data, txn.resp), UVM_HIGH)
      end
    end
  endtask

  task monitor_writes();
    axi4_lite_txn txn;
    forever begin
      @(posedge vif.clk);
      if (vif.m_awvalid && vif.s_awready) begin
        txn = axi4_lite_txn::type_id::create("wr_txn");
        txn.addr     = vif.m_awaddr;
        txn.is_write = 1'b1;

        // Wait for write data
        while (!(vif.m_wvalid && vif.s_wready)) @(posedge vif.clk);
        txn.data = vif.m_wdata;
        txn.strb = vif.m_wstrb;

        // Wait for response
        while (!(vif.s_bvalid && vif.m_bready)) @(posedge vif.clk);
        txn.resp = vif.s_bresp;

        ap.write(txn);
        `uvm_info("AXI_MON", $sformatf("WR: addr=0x%08h data=0x%08h strb=%04b resp=%0d",
                  txn.addr, txn.data, txn.strb, txn.resp), UVM_HIGH)
      end
    end
  endtask

endclass
