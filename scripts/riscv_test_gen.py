#!/usr/bin/env python3
"""
RISC-V RV32I Test Generator and Analysis Tools
Generates instruction memory hex files and analyzes simulation results.
"""

import random
import struct
import argparse
import json
from dataclasses import dataclass, field
from typing import List, Optional
from pathlib import Path


# =============================================================================
# RV32I Instruction Encoders
# =============================================================================

def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int = 0x33) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def i_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int = 0x13) -> int:
    imm = imm & 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def s_type(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    imm = imm & 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | 0x23

def b_type(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    imm = imm & 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | \
           (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63

def u_type(imm: int, rd: int, opcode: int) -> int:
    return (imm << 12) | (rd << 7) | opcode

def j_type(imm: int, rd: int) -> int:
    imm = imm & 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
           (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F

# Convenience
def nop() -> int:
    return i_type(0, 0, 0, 0)  # ADDI x0, x0, 0

def addi(rd, rs1, imm):
    return i_type(imm, rs1, 0, rd)

def add(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 0, rd)

def sub(rd, rs1, rs2):
    return r_type(0x20, rs2, rs1, 0, rd)

def lw(rd, rs1, imm):
    return i_type(imm, rs1, 2, rd, 0x03)

def sw(rs2, rs1, imm):
    return s_type(imm, rs2, rs1, 2)

def beq(rs1, rs2, imm):
    return b_type(imm, rs2, rs1, 0)

def bne(rs1, rs2, imm):
    return b_type(imm, rs2, rs1, 1)

def lui(rd, imm):
    return u_type(imm, rd, 0x37)

def jal(rd, imm):
    return j_type(imm, rd)


# =============================================================================
# Test Generators
# =============================================================================

@dataclass
class TestProgram:
    name: str
    instructions: List[int] = field(default_factory=list)
    description: str = ""
    expected_regs: dict = field(default_factory=dict)

    def add(self, instr: int):
        self.instructions.append(instr)
        return self

    def pad_nops(self, count: int = 10):
        for _ in range(count):
            self.instructions.append(nop())
        return self


def gen_alu_test() -> TestProgram:
    """Test all ALU operations."""
    t = TestProgram("alu_test", description="Tests all RV32I ALU operations")
    t.add(addi(1, 0, 10))       # x1 = 10
    t.add(addi(2, 0, 20))       # x2 = 20
    t.add(add(3, 1, 2))         # x3 = 30
    t.add(sub(4, 2, 1))         # x4 = 10
    t.add(r_type(0, 2, 1, 4, 5))  # XOR x5 = x1 ^ x2
    t.add(r_type(0, 2, 1, 6, 6))  # OR  x6 = x1 | x2
    t.add(r_type(0, 2, 1, 7, 7))  # AND x7 = x1 & x2
    t.add(r_type(0, 1, 2, 2, 8))  # SLT x8 = (x2 < x1) ? -> 0
    t.add(i_type(3, 1, 1, 9))     # SLLI x9 = x1 << 3 = 80
    t.add(i_type(2, 9, 5, 10))    # SRLI x10 = x9 >> 2 = 20
    t.expected_regs = {1: 10, 2: 20, 3: 30, 4: 10, 9: 80, 10: 20}
    t.pad_nops()
    return t


def gen_hazard_test() -> TestProgram:
    """Test data hazards and forwarding."""
    t = TestProgram("hazard_test", description="RAW hazards, load-use stalls, forwarding")
    # RAW: back-to-back dependency
    t.add(addi(1, 0, 5))        # x1 = 5
    t.add(addi(2, 1, 10))       # x2 = x1 + 10 = 15 (EX-EX forwarding)
    t.add(addi(3, 1, 20))       # x3 = x1 + 20 = 25 (MEM-EX forwarding)

    # Load-use
    t.add(sw(1, 0, 0))          # MEM[0] = x1 = 5
    t.add(lw(4, 0, 0))          # x4 = MEM[0] = 5
    t.add(add(5, 4, 1))         # x5 = x4 + x1 = 10 (load-use stall)

    # Triple dependency chain
    t.add(addi(6, 0, 1))        # x6 = 1
    t.add(add(6, 6, 6))         # x6 = 2
    t.add(add(6, 6, 6))         # x6 = 4
    t.add(add(6, 6, 6))         # x6 = 8

    t.expected_regs = {1: 5, 2: 15, 3: 25, 4: 5, 5: 10, 6: 8}
    t.pad_nops()
    return t


def gen_branch_test() -> TestProgram:
    """Test branch instructions and flush logic."""
    t = TestProgram("branch_test", description="Branch taken/not-taken and flush")
    t.add(addi(1, 0, 10))       # x1 = 10
    t.add(addi(2, 0, 10))       # x2 = 10
    t.add(addi(3, 0, 20))       # x3 = 20

    # BEQ taken (x1 == x2, skip next instruction)
    t.add(beq(1, 2, 8))         # if x1==x2, jump +8 (skip next)
    t.add(addi(4, 0, 99))       # x4 = 99 (should be flushed)
    t.add(addi(5, 0, 42))       # x5 = 42 (branch target)

    # BNE not taken (x1 == x2)
    t.add(bne(1, 2, 8))         # if x1!=x2, jump +8 (should NOT be taken)
    t.add(addi(6, 0, 77))       # x6 = 77 (should execute)

    # BNE taken (x1 != x3)
    t.add(bne(1, 3, 8))         # if x1!=x3, jump +8 (should be taken)
    t.add(addi(7, 0, 99))       # x7 = 99 (should be flushed)
    t.add(addi(8, 0, 55))       # x8 = 55 (branch target)

    t.expected_regs = {1: 10, 2: 10, 3: 20, 4: 0, 5: 42, 6: 77, 7: 0, 8: 55}
    t.pad_nops()
    return t


def gen_memory_test() -> TestProgram:
    """Test load/store operations through cache."""
    t = TestProgram("memory_test", description="Load/store with cache exercises")
    base = 0x100  # Use an address offset

    # Store sequential values
    for i in range(8):
        t.add(addi(1, 0, (i + 1) * 10))   # x1 = 10, 20, ..., 80
        t.add(lui(2, base >> 12))           # x2 = base (upper)
        t.add(sw(1, 2, i * 4))             # MEM[base + i*4] = x1

    # Load back and accumulate
    t.add(lui(2, base >> 12))
    t.add(addi(10, 0, 0))                  # x10 = accumulator
    for i in range(8):
        t.add(lw(3, 2, i * 4))             # x3 = MEM[base + i*4]
        t.add(add(10, 10, 3))              # x10 += x3

    t.expected_regs = {10: 360}  # 10+20+30+40+50+60+70+80
    t.pad_nops()
    return t


def gen_random_test(num_instrs: int = 100, seed: int = None) -> TestProgram:
    """Generate constrained-random instruction sequence."""
    if seed is not None:
        random.seed(seed)

    t = TestProgram("random_test", description=f"Random {num_instrs} instructions, seed={seed}")

    # Initialize some registers
    for i in range(1, 8):
        t.add(addi(i, 0, random.randint(1, 100)))

    # Initialize a base address for loads/stores
    t.add(lui(8, 1))  # x8 = 0x1000

    for _ in range(num_instrs):
        rd = random.randint(1, 15)
        rs1 = random.randint(1, 7)
        rs2 = random.randint(1, 7)
        imm = random.randint(-50, 50)
        choice = random.choices(
            ['alu_r', 'alu_i', 'load', 'store', 'branch'],
            weights=[30, 25, 15, 10, 10]
        )[0]

        if choice == 'alu_r':
            funct3 = random.randint(0, 7)
            funct7 = 0x20 if (funct3 in [0, 5] and random.random() > 0.5) else 0
            t.add(r_type(funct7, rs2, rs1, funct3, rd))
        elif choice == 'alu_i':
            funct3 = random.randint(0, 7)
            if funct3 in [1, 5]:
                imm = random.randint(0, 31)
            t.add(i_type(imm & 0xFFF, rs1, funct3, rd))
        elif choice == 'load':
            offset = random.choice([0, 4, 8, 12])
            t.add(lw(rd, 8, offset))
        elif choice == 'store':
            offset = random.choice([0, 4, 8, 12])
            t.add(sw(rs2, 8, offset))
        elif choice == 'branch':
            # Small forward branches only (to avoid infinite loops)
            t.add(beq(rs1, rs2, 8))

    t.pad_nops(20)
    return t


# =============================================================================
# Output Generators
# =============================================================================

def to_hex_file(program: TestProgram, filepath: str):
    """Write instructions as hex file (one word per line)."""
    with open(filepath, 'w') as f:
        f.write(f"// {program.name}: {program.description}\n")
        for i, instr in enumerate(program.instructions):
            f.write(f"{instr:08X}  // PC=0x{i*4:04X}\n")
    print(f"Generated {filepath} ({len(program.instructions)} instructions)")


def to_memh_file(program: TestProgram, filepath: str):
    """Write as $readmemh compatible file."""
    with open(filepath, 'w') as f:
        for instr in program.instructions:
            f.write(f"{instr:08X}\n")
    print(f"Generated {filepath}")


def to_sv_array(program: TestProgram, filepath: str):
    """Write as SystemVerilog initial block for memory preload."""
    with open(filepath, 'w') as f:
        f.write(f"// {program.name}: {program.description}\n")
        f.write(f"// Auto-generated by riscv_test_gen.py\n\n")
        f.write("initial begin\n")
        for i, instr in enumerate(program.instructions):
            f.write(f"  memory[{i}] = 32'h{instr:08X};\n")
        f.write("end\n")
    print(f"Generated {filepath}")


# =============================================================================
# Reference Model (Golden Model)
# =============================================================================

class RV32ISim:
    """Simple RV32I instruction set simulator for result checking."""

    def __init__(self):
        self.regs = [0] * 32
        self.pc = 0
        self.memory = {}

    def step(self, instr: int) -> bool:
        """Execute one instruction. Returns False to halt."""
        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F

        # Decode immediates
        imm_i = self._sign_ext((instr >> 20), 12)
        imm_s = self._sign_ext(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12)
        imm_b = self._sign_ext(
            (((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11) |
            (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1), 13)
        imm_u = instr & 0xFFFFF000
        imm_j = self._sign_ext(
            (((instr >> 31) & 1) << 20) | (((instr >> 21) & 0x3FF) << 1) |
            (((instr >> 20) & 1) << 11) | (((instr >> 12) & 0xFF) << 12), 21)

        next_pc = self.pc + 4
        rs1_val = self.regs[rs1]
        rs2_val = self.regs[rs2]

        if opcode == 0x33:  # R-type
            result = self._alu_r(rs1_val, rs2_val, funct3, funct7)
            if rd: self.regs[rd] = result & 0xFFFFFFFF
        elif opcode == 0x13:  # I-type ALU
            result = self._alu_i(rs1_val, imm_i, funct3, funct7)
            if rd: self.regs[rd] = result & 0xFFFFFFFF
        elif opcode == 0x37:  # LUI
            if rd: self.regs[rd] = imm_u & 0xFFFFFFFF
        elif opcode == 0x17:  # AUIPC
            if rd: self.regs[rd] = (self.pc + imm_u) & 0xFFFFFFFF
        elif opcode == 0x03:  # LOAD
            addr = (rs1_val + imm_i) & 0xFFFFFFFF
            val = self.memory.get(addr & ~3, 0)
            if rd: self.regs[rd] = val & 0xFFFFFFFF
        elif opcode == 0x23:  # STORE
            addr = (rs1_val + imm_s) & 0xFFFFFFFF
            self.memory[addr & ~3] = rs2_val & 0xFFFFFFFF
        elif opcode == 0x63:  # BRANCH
            taken = self._branch(rs1_val, rs2_val, funct3)
            if taken:
                next_pc = self.pc + imm_b
        elif opcode == 0x6F:  # JAL
            if rd: self.regs[rd] = (self.pc + 4) & 0xFFFFFFFF
            next_pc = self.pc + imm_j
        elif opcode == 0x67:  # JALR
            if rd: self.regs[rd] = (self.pc + 4) & 0xFFFFFFFF
            next_pc = (rs1_val + imm_i) & ~1

        self.pc = next_pc & 0xFFFFFFFF
        return True

    def run(self, instructions: List[int], max_steps: int = 10000):
        """Run a list of instructions."""
        for i, instr in enumerate(instructions):
            self.memory[i * 4] = instr  # Also load into memory for self-modifying reference

        step_count = 0
        while self.pc // 4 < len(instructions) and step_count < max_steps:
            idx = self.pc // 4
            if idx >= len(instructions):
                break
            self.step(instructions[idx])
            step_count += 1

        return self.regs

    def _sign_ext(self, val, bits):
        if val & (1 << (bits - 1)):
            val -= (1 << bits)
        return val

    def _to_signed(self, val):
        if val & 0x80000000:
            return val - 0x100000000
        return val

    def _alu_r(self, a, b, f3, f7):
        a_s, b_s = self._to_signed(a), self._to_signed(b)
        ops = {
            (0, 0x00): a + b,
            (0, 0x20): a - b,
            (1, 0x00): a << (b & 0x1F),
            (2, 0x00): int(a_s < b_s),
            (3, 0x00): int((a & 0xFFFFFFFF) < (b & 0xFFFFFFFF)),
            (4, 0x00): a ^ b,
            (5, 0x00): (a & 0xFFFFFFFF) >> (b & 0x1F),
            (5, 0x20): (a_s >> (b & 0x1F)) & 0xFFFFFFFF,
            (6, 0x00): a | b,
            (7, 0x00): a & b,
        }
        return ops.get((f3, f7), 0)

    def _alu_i(self, a, imm, f3, f7):
        a_s = self._to_signed(a)
        imm_s = imm  # Already sign-extended
        if f3 == 0: return a + imm
        elif f3 == 2: return int(a_s < imm_s)
        elif f3 == 3: return int((a & 0xFFFFFFFF) < (imm & 0xFFFFFFFF))
        elif f3 == 4: return a ^ imm
        elif f3 == 6: return a | imm
        elif f3 == 7: return a & imm
        elif f3 == 1: return a << (imm & 0x1F)
        elif f3 == 5:
            shamt = imm & 0x1F
            if f7 & 0x20:
                return (a_s >> shamt) & 0xFFFFFFFF
            else:
                return (a & 0xFFFFFFFF) >> shamt
        return 0

    def _branch(self, a, b, f3):
        a_s, b_s = self._to_signed(a), self._to_signed(b)
        if f3 == 0: return a == b
        elif f3 == 1: return a != b
        elif f3 == 4: return a_s < b_s
        elif f3 == 5: return a_s >= b_s
        elif f3 == 6: return (a & 0xFFFFFFFF) < (b & 0xFFFFFFFF)
        elif f3 == 7: return (a & 0xFFFFFFFF) >= (b & 0xFFFFFFFF)
        return False


# =============================================================================
# Result Analysis
# =============================================================================

def verify_test(program: TestProgram):
    """Run test through reference model and check expected registers."""
    sim = RV32ISim()
    final_regs = sim.run(program.instructions)

    print(f"\n=== Verifying: {program.name} ===")
    all_pass = True
    for reg, expected in program.expected_regs.items():
        actual = final_regs[reg] & 0xFFFFFFFF
        expected = expected & 0xFFFFFFFF
        status = "PASS" if actual == expected else "FAIL"
        if status == "FAIL":
            all_pass = False
        print(f"  x{reg}: expected=0x{expected:08X}, got=0x{actual:08X} [{status}]")

    print(f"  Result: {'ALL PASSED' if all_pass else 'FAILURES DETECTED'}")
    return all_pass


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="RISC-V RV32I Test Generator")
    parser.add_argument("--test", choices=["alu", "hazard", "branch", "memory", "random", "all"],
                        default="all", help="Test to generate")
    parser.add_argument("--num-instrs", type=int, default=100, help="Number of random instructions")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--output-dir", type=str, default=".", help="Output directory")
    parser.add_argument("--format", choices=["hex", "memh", "sv"], default="hex", help="Output format")
    parser.add_argument("--verify", action="store_true", help="Run reference model verification")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    generators = {
        "alu": gen_alu_test,
        "hazard": gen_hazard_test,
        "branch": gen_branch_test,
        "memory": gen_memory_test,
        "random": lambda: gen_random_test(args.num_instrs, args.seed),
    }

    tests = generators.keys() if args.test == "all" else [args.test]
    writer = {"hex": to_hex_file, "memh": to_memh_file, "sv": to_sv_array}[args.format]

    for test_name in tests:
        program = generators[test_name]()
        filepath = str(out_dir / f"{program.name}.{args.format}")
        writer(program, filepath)

        if args.verify:
            verify_test(program)


if __name__ == "__main__":
    main()
