import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

from numpy import uint32, int32

# Instruction Type: {is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j}
ASM = {
    "R": {
        "ADD x3, x1, x2": (0x002081b3, 0)
        #
    },
    "I": {
        "ADDI x0, x0,  0": (0x00000013,  0),
        "ADDI x4, x4,  1": (0x00120213,  1),
        "ADDI x4, x4, -1": (0xfff20213, -1),
    },
    "S": {
        "SW x4, 1(x0)": (0x004020a3, 1),
    },
    "B": {
        "BLTU x5, x6,  0": (0x0062e063,  0),
        "BLTU x5, x6, 10": (0x0062e563, 10),
    },
    "U": {
        "LUI x5, 10":   (0x0000a2b7, 10 << 12),
        "AUIPC x5, 10": (0x0000a297, 10 << 12),
    },
    "J": {
        "JAL x0,  2": (0x0020006f, 0x0000_0002),
        "JAL x0,  4": (0x0040006f, 0x0000_0004),
        "JAL x0, -2": (0xfffff06f, 0xFFFF_FFFE),
        "JAL x0, -4": (0xffdff06f, 0xFFFF_FFFC),
    },
}

# {is_r_type, is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j};
IFORMAT: dict[str,int] = {
    "R": 0b100000,
    "I": 0b010000,
    "S": 0b001000,
    "B": 0b001100,
    "U": 0b000010,
    "J": 0b000011,
}

@cocotb.test()
async def test_null(dut) -> None:
    dut.instruction.value = 0
    dut.instruction_format.value = 0
    await Timer(1, "ps")
    assert dut.immediate.value == 0, "No input should stay 0 to reduce transitions"

@cocotb.test()
async def test_type_r(dut) -> None:
    for instr_asm, (instr_bin, ref_imm) in ASM["R"].items(): 
        dut.instruction.value = instr_bin
        dut.instruction_format.value = IFORMAT["R"]
        await Timer(1, "ps")
        # assert np.array(int(dut.immediate.value)).astype(int32) == int32(ref_imm), f"{instr_asm}"
        assert int32(int(dut.immediate.value)) == int32(ref_imm), f"{instr_asm}"

@cocotb.test()
async def test_type_i(dut) -> None:
    for instr_asm, (instr_bin, ref_imm) in ASM["I"].items(): 
        dut.instruction.value = instr_bin
        dut.instruction_format.value = IFORMAT["I"]
        await Timer(1, "ps")
        assert int32(int(dut.immediate.value)) == int32(ref_imm), f"{instr_asm}"

@cocotb.test()
async def test_type_s(dut) -> None:
    for instr_asm, (instr_bin, ref_imm) in ASM["S"].items(): 
        dut.instruction.value = instr_bin
        dut.instruction_format.value = IFORMAT["S"]
        await Timer(1, "ps")
        assert int32(int(dut.immediate.value)) == int32(ref_imm), f"{instr_asm}"

@cocotb.test()
async def test_type_b(dut) -> None:
    for instr_asm, (instr_bin, ref_imm) in ASM["B"].items(): 
        dut.instruction.value = instr_bin
        dut.instruction_format.value = IFORMAT["B"]
        await Timer(1, "ps")
        assert int32(int(dut.immediate.value)) == int32(ref_imm), f"{instr_asm}"

@cocotb.test()
async def test_type_u(dut) -> None:
    for instr_asm, (instr_bin, ref_imm) in ASM["U"].items(): 
        dut.instruction.value = instr_bin
        dut.instruction_format.value = IFORMAT["U"]
        await Timer(1, "ps")
        assert int32(int(dut.immediate.value)) == int32(ref_imm), f"{instr_asm}"

@cocotb.test()
async def test_type_j(dut) -> None:
    for instr_asm, (instr_bin, ref_imm) in ASM["J"].items(): 
        dut.instruction.value = instr_bin
        dut.instruction_format.value = IFORMAT["J"]
        await Timer(1, "ps")
        assert int32(int(dut.immediate.value)) == int32(ref_imm), f"{instr_asm}"

def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_instruction_decoder_imm"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / f"{hdl_toplevel}.sv",
    ]

    build_args = ["--trace", "--trace-structs"] if sim == "verilator" else []
    runner = get_runner(sim)
    runner.build(
        verilog_sources=verilog_sources,
        vhdl_sources=[],
        hdl_toplevel=hdl_toplevel,
        always=True,
        build_args=build_args,
        build_dir=f"build/{hdl_toplevel}",
    )

    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{hdl_toplevel}_test,",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
