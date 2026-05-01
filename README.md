# RISC-V RV32I Processor with Cache, AXI4, and Full Verification Suite

A 5-stage pipelined RV32I processor with L1 instruction/data caches, AXI4-Lite bus interface, clock gating for low-power design, UVM-based constrained-random verification, SVA formal assertions, and dual-target synthesis (ASIC via Yosys/SKY130 and FPGA via Vivado/Zedboard).

## Architecture Overview

### Pipeline Stages

The processor implements a classic 5-stage in-order pipeline:

1. **Fetch (IF):** Reads instructions from the I-Cache using the current PC. On a cache miss, the pipeline stalls until the line is fetched from main memory via AXI4-Lite.

2. **Decode (ID):** Decodes the instruction, reads the register file (2 async read ports with write-through), generates control signals, and produces the sign-extended immediate.

3. **Execute (EX):** Performs ALU computation, resolves branches (static predict not-taken), and computes branch/jump targets. Data forwarding muxes select between register file values and forwarded results.

4. **Memory (MEM):** Accesses the D-Cache for loads and stores. The cache supports byte, halfword, and word accesses with sign/zero extension.

5. **Writeback (WB):** Writes results back to the register file. Sources: ALU result, memory data (loads), or PC+4 (JAL/JALR link address).

### Hazard Handling

The hazard unit handles three scenarios:

- **EX-to-EX forwarding:** When the EX/MEM stage writes to a register that the current EX stage reads, the result is forwarded directly (1-cycle RAW resolution).
- **MEM-to-EX forwarding:** When the MEM/WB stage writes to a register that the current EX stage reads, the result is forwarded (2-cycle RAW resolution).
- **Load-use stall:** When a load instruction is followed immediately by an instruction that uses the loaded value, a 1-cycle bubble is inserted.

Branch mispredictions (static predict not-taken) flush the IF/ID and ID/EX pipeline registers.

### Cache Subsystem

Both caches are 2-way set-associative with 64 sets and 16-byte (4-word) cache lines, giving 4KB per way (8KB total per cache).

**I-Cache:** Read-only with LRU replacement. States: IDLE, COMPARE (check hit), REFILL (fetch line from memory). On a miss, the cache fetches 4 words sequentially via AXI4-Lite.

**D-Cache:** Write-back with dirty bits and write-allocate policy. States: IDLE, COMPARE, WRITEBACK (evict dirty line), ALLOCATE (fetch new line). On a write hit, data is written into the cache and the dirty bit is set. On a miss, if the evicted line is dirty, it is written back before the new line is allocated.

### AXI4-Lite Bus Interface

The AXI master arbitrates between I-Cache and D-Cache requests with the priority: D-Cache write > D-Cache read > I-Cache read. Each cache line refill/writeback is performed as a sequence of individual AXI4-Lite word transfers. All five AXI channels (AW, W, B, AR, R) implement proper valid/ready handshakes.

### Clock Gating

Latch-based integrated clock gating (ICG) cells gate idle pipeline stages and inactive cache subsystems. Activity signals from the core and caches control the gating. A test_en input disables gating during scan testing.

## Directory Structure

```
riscv-project/
├── rtl/
│   ├── core/           # Pipeline stages and core logic
│   │   ├── riscv_pkg.sv          # Package: types, params, enums
│   │   ├── program_counter.sv    # PC with branch/stall support
│   │   ├── register_file.sv      # 32x32 regfile, 2R/1W
│   │   ├── decoder.sv            # Instruction decoder + control
│   │   ├── alu.sv                # All RV32I ALU operations
│   │   ├── branch_unit.sv        # Branch resolution, target calc
│   │   ├── hazard_unit.sv        # Forwarding + stall logic
│   │   └── riscv_core.sv         # Pipeline integration
│   ├── cache/
│   │   ├── icache.sv             # L1 I-Cache (2-way, read-only)
│   │   └── dcache.sv             # L1 D-Cache (2-way, write-back)
│   ├── bus/
│   │   └── axi4_lite_master.sv   # AXI4-Lite master with arbitration
│   ├── clock_gating/
│   │   └── clock_gating.sv       # ICG cells + controller
│   └── top/
│       └── riscv_soc_top.sv      # Top-level SoC integration
├── verif/
│   ├── uvm/
│   │   ├── agents/
│   │   │   ├── axi4_lite_if.sv       # SV interface with modports
│   │   │   ├── axi4_lite_txn.sv      # UVM sequence item (transaction)
│   │   │   ├── axi4_lite_driver.sv   # AXI slave driver (memory responder)
│   │   │   ├── axi4_lite_monitor.sv  # Passive bus observer, analysis port
│   │   │   └── axi4_lite_agent.sv    # Agent wrapper (driver+monitor+sequencer)
│   │   ├── env/
│   │   │   ├── riscv_env.sv          # Top-level UVM environment
│   │   │   └── riscv_coverage.sv     # 5 functional coverage groups
│   │   ├── sequences/
│   │   │   └── riscv_sequences.sv    # Random + hazard-directed sequences
│   │   ├── scoreboards/
│   │   │   └── riscv_scoreboard.sv   # Reference model ISS + comparator
│   │   └── tests/
│   │       └── riscv_tests.sv        # Base, random, hazard, regression tests
│   ├── sva/
│   │   └── riscv_sva.sv          # SVA: AXI protocol, pipeline, cache assertions
│   └── tb/
│       ├── tb_top.sv             # UVM testbench top
│       └── tb_basic.sv           # Non-UVM smoke test
├── syn/
│   ├── yosys/
│   │   ├── synth.ys              # Yosys synthesis script (SKY130)
│   │   └── timing.tcl            # OpenSTA timing analysis
│   └── vivado/
│       ├── constraints.xdc       # Zedboard constraints
│       └── run_vivado.tcl        # Vivado synthesis + implementation
├── scripts/
│   ├── run_sim.sh                # Simulation runner (basic, UVM, regression)
│   └── riscv_test_gen.py         # Python test generator + reference model
└── docs/
    └── README.md
```

## Quick Start

### 1. Generate Test Programs

```bash
cd scripts
python3 riscv_test_gen.py --test all --format hex --output-dir ../tests --verify
```

### 2. Run Basic Simulation (Non-UVM)

With VCS:
```bash
vcs -sverilog -full64 -debug_access+all \
    rtl/core/riscv_pkg.sv rtl/core/*.sv rtl/cache/*.sv \
    rtl/bus/*.sv rtl/clock_gating/*.sv rtl/top/*.sv \
    verif/tb/tb_basic.sv -o simv
./simv
```

With Icarus Verilog (limited SystemVerilog support):
```bash
iverilog -g2012 -o sim \
    rtl/core/riscv_pkg.sv rtl/core/*.sv rtl/cache/*.sv \
    rtl/bus/*.sv rtl/clock_gating/*.sv rtl/top/*.sv \
    verif/tb/tb_basic.sv
vvp sim
```

### 3. Run UVM Tests

```bash
vcs -sverilog -full64 -ntb_opts uvm \
    rtl/core/riscv_pkg.sv rtl/**/*.sv \
    verif/uvm/**/*.sv verif/sva/*.sv verif/tb/tb_top.sv \
    +UVM_TESTNAME=riscv_random_test -o simv
./simv +UVM_TESTNAME=riscv_random_test +ntb_random_seed=12345
```

### 4. Run Regression

```bash
for seed in 12345 67890 11111 22222 33333; do
    ./simv +UVM_TESTNAME=riscv_regression_test +ntb_random_seed=$seed
done
```

### 5. ASIC Synthesis (Yosys + OpenSTA)

```bash
cd syn/yosys
yosys -s synth.ys
sta timing.tcl
```

### 6. FPGA Synthesis (Vivado)

```bash
cd syn/vivado
vivado -mode batch -source run_vivado.tcl
```

## Verification Coverage

### SVA Assertions

| Category             | Assertions                                             |
|----------------------|--------------------------------------------------------|
| AXI4 Protocol        | VALID stability, signal stability during handshake     |
| AXI4 Liveness        | Read/write complete within 100 cycles                  |
| Pipeline Invariants  | No x0 writes, flush clears IF/ID, bubble clears ID/EX |
| Forwarding           | EX-MEM forwarding fires when expected                  |
| Cache Coherency      | Dirty implies valid, no simultaneous R/W to memory     |
| Cache Liveness       | WRITEBACK/ALLOCATE states complete within 200 cycles   |

### Functional Coverage Groups

| Group             | Bins                                                        |
|-------------------|-------------------------------------------------------------|
| Instruction Types | R-type, I-type, Load, Store, Branch, JAL, JALR, LUI, AUIPC |
| Hazards           | RAW, load-use, EX forwarding, MEM forwarding (cross)       |
| Cache             | I-Cache hit/miss, D-Cache hit/miss, writeback               |
| Branches          | Taken/not-taken x {BEQ, BNE, BLT, BGE, BLTU, BGEU}        |
| AXI               | Read/Write x Response codes                                 |

## Clock Gating Power Analysis

To measure power savings from clock gating:

1. Synthesize with clock gating enabled (default)
2. Record power from `report_power` (Vivado) or OpenSTA
3. Modify `riscv_soc_top.sv` to bypass `clock_gating_ctrl` (connect `clk` directly)
4. Re-synthesize and compare power reports
5. Document the delta in dynamic power consumption

## Tools Required

| Tool             | Purpose                          | Version Tested |
|------------------|----------------------------------|----------------|
| SystemVerilog    | RTL design and testbenches       | IEEE 1800-2017 |
| VCS or Xcelium   | UVM simulation                  | 2023.x+        |
| Vivado           | FPGA synthesis (Zedboard)       | 2023.x+        |
| Yosys            | ASIC synthesis                   | 0.30+          |
| OpenSTA          | Static timing analysis           | 2.5+           |
| Python 3         | Test generation and analysis     | 3.8+           |

## Resume Keywords

Microarchitecture, RTL design, cache hierarchy, AXI4 bus protocol, low-power design,
clock gating, UVM, constrained-random verification, functional coverage, SVA,
formal assertions, ASIC synthesis, static timing analysis, timing closure, FPGA prototyping
