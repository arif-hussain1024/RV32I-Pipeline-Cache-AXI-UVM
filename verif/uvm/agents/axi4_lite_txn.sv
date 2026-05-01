// =============================================================================
// AXI4-Lite UVM Transaction / Sequence Item
// =============================================================================
class axi4_lite_txn extends uvm_sequence_item;

  rand logic [31:0] addr;
  rand logic [31:0] data;
  rand logic [3:0]  strb;
  rand logic        is_write;
  logic [1:0]       resp;

  `uvm_object_utils_begin(axi4_lite_txn)
    `uvm_field_int(addr,     UVM_ALL_ON)
    `uvm_field_int(data,     UVM_ALL_ON)
    `uvm_field_int(strb,     UVM_ALL_ON)
    `uvm_field_int(is_write, UVM_ALL_ON)
    `uvm_field_int(resp,     UVM_ALL_ON)
  `uvm_object_utils_end

  constraint c_addr_aligned {
    addr[1:0] == 2'b00;  // Word-aligned
  }

  constraint c_strb_valid {
    strb inside {4'b0001, 4'b0011, 4'b1111};
  }

  function new(string name = "axi4_lite_txn");
    super.new(name);
  endfunction

endclass
