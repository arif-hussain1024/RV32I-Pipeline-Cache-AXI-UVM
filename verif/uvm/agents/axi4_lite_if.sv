// =============================================================================
// AXI4-Lite Interface
// Used for UVM verification hookup
// =============================================================================
interface axi4_lite_if (
  input logic clk,
  input logic rst_n
);

  // Write Address Channel (Master -> Slave)
  logic [31:0] m_awaddr;
  logic        m_awvalid;
  logic [2:0]  m_awprot;

  // Write Address Channel (Slave -> Master)
  logic        s_awready;

  // Write Data Channel (Master -> Slave)
  logic [31:0] m_wdata;
  logic [3:0]  m_wstrb;
  logic        m_wvalid;

  // Write Data Channel (Slave -> Master)
  logic        s_wready;

  // Write Response Channel (Slave -> Master)
  logic [1:0]  s_bresp;
  logic        s_bvalid;

  // Write Response Channel (Master -> Slave)
  logic        m_bready;

  // Read Address Channel (Master -> Slave)
  logic [31:0] m_araddr;
  logic        m_arvalid;
  logic [2:0]  m_arprot;

  // Read Address Channel (Slave -> Master)
  logic        s_arready;

  // Read Data Channel (Slave -> Master)
  logic [31:0] s_rdata;
  logic [1:0]  s_rresp;
  logic        s_rvalid;

  // Read Data Channel (Master -> Slave)
  logic        m_rready;

  // Modports
  modport master (
    output m_awaddr, m_awvalid, m_awprot,
    input  s_awready,
    output m_wdata, m_wstrb, m_wvalid,
    input  s_wready,
    input  s_bresp, s_bvalid,
    output m_bready,
    output m_araddr, m_arvalid, m_arprot,
    input  s_arready,
    input  s_rdata, s_rresp, s_rvalid,
    output m_rready
  );

  modport slave (
    input  m_awaddr, m_awvalid, m_awprot,
    output s_awready,
    input  m_wdata, m_wstrb, m_wvalid,
    output s_wready,
    output s_bresp, s_bvalid,
    input  m_bready,
    input  m_araddr, m_arvalid, m_arprot,
    output s_arready,
    output s_rdata, s_rresp, s_rvalid,
    input  m_rready
  );

  modport monitor (
    input m_awaddr, m_awvalid, m_awprot, s_awready,
    input m_wdata, m_wstrb, m_wvalid, s_wready,
    input s_bresp, s_bvalid, m_bready,
    input m_araddr, m_arvalid, m_arprot, s_arready,
    input s_rdata, s_rresp, s_rvalid, m_rready
  );

endinterface
