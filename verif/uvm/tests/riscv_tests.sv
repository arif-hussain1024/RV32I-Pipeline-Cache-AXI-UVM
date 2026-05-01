// =============================================================================
// UVM Test Classes
// =============================================================================

// Base test
class riscv_base_test extends uvm_test;
  `uvm_component_utils(riscv_base_test)

  riscv_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = riscv_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

endclass


// Random instruction test
class riscv_random_test extends riscv_base_test;
  `uvm_component_utils(riscv_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    riscv_random_seq seq;
    phase.raise_objection(this);

    seq = riscv_random_seq::type_id::create("seq");
    if (!seq.randomize() with { num_instructions == 200; })
      `uvm_fatal("TEST", "Sequence randomization failed")

    `uvm_info("TEST", "Starting random instruction test", UVM_LOW)
    // Instructions are loaded via preload mechanism
    // The sequence generates instruction encodings that get preloaded into memory

    #10000;  // Run simulation

    phase.drop_objection(this);
  endtask

endclass


// Hazard-focused test
class riscv_hazard_test extends riscv_base_test;
  `uvm_component_utils(riscv_hazard_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    riscv_hazard_seq seq;
    phase.raise_objection(this);

    seq = riscv_hazard_seq::type_id::create("seq");

    `uvm_info("TEST", "Starting hazard-focused test", UVM_LOW)

    #5000;

    phase.drop_objection(this);
  endtask

endclass


// Regression test with multiple seeds
class riscv_regression_test extends riscv_base_test;
  `uvm_component_utils(riscv_regression_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    riscv_random_seq seq;
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting regression test (use +ntb_random_seed for variation)", UVM_LOW)

    seq = riscv_random_seq::type_id::create("seq");
    if (!seq.randomize() with { num_instructions == 500; })
      `uvm_fatal("TEST", "Sequence randomization failed")

    #20000;

    phase.drop_objection(this);
  endtask

endclass
