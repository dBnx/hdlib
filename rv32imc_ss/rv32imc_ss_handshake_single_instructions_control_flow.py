import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

async def reset_dut(dut):
    dut.reset.value = 1
    dut.instr_ack.value = 0
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0
    await Timer(1, "ps")

    await RisingEdge(dut.clk)

    dut.reset.value = 0
    await Timer(1, "ps")


def get_registerfile(dut) -> dict[str, int]:
    ret: dict[str,intjkk] = {}
    for i, v in enumerate(dut.inst_registerfile.registerfile.value):
        ret[f"x{i}"] = v
    return ret

def set_registerfile(dut, values: dict[str, int]):
    for i, v in enumerate(values.values()):
        dut.inst_registerfile.registerfile[i].value = v

def get_pc(dut) -> dict[str, int]:
    return {
        "current":dut.pc_current.value,
        "next"   :dut.pc_next.value
    }

async def exec_instr(dut, instruction: int, count: int = 1):
    """Execute `count` nops. Also useful at the end of tests for cleaner traces"""
    dut.instr_ack.value = 1
    dut.instr_err.value = 0
    dut.instr_data_i.value = instruction
    for _ in range(count):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")
    dut.instr_ack.value = 0

async def exec_nop(dut, count: int = 1):
    nop = 0x00000013 # addi x0, x0, 0
    await exec_instr(dut, instruction=nop, count=count)

@cocotb.test()
async def test_j_jal(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    instr = 0xfd9ff0ef # JAL x1, -40
    await exec_instr(dut, instr)

    assert (initial_pc - 40) & 0xFFFF_FFFF == get_pc(dut)["current"]
    assert initial_pc + 4 == get_registerfile(dut)["x1"]

    exec_nop(dut)

@cocotb.test()
async def test_i_jalr(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]

    rf = get_registerfile(dut)
    rf["x5"] = 100
    set_registerfile(dut, rf)

    instr = 0x002280e7 # jalr x1, 2(x5)
    await exec_instr(dut, instr)

    assert initial_pc + 4 == get_registerfile(dut)["x1"]
    assert 100 + 2 == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_beq_true(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = 100
    rf["x6"] = 100
    set_registerfile(dut, rf)
    instr = 0xfe6288e3 # beq x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc - 16) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_beq_false(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = 100
    rf["x6"] = 101
    set_registerfile(dut, rf)
    instr = 0xfe6288e3 # beq x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc + 4) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_blt_true(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = -100
    rf["x6"] = +100
    set_registerfile(dut, rf)
    instr = 0xfe62c8e3 # blt x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc - 16) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_blt_false(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = +100
    rf["x6"] = -100
    set_registerfile(dut, rf)
    instr = 0xfe62c8e3 # blt x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc + 4) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_bge_true(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = -100
    rf["x6"] = -100
    set_registerfile(dut, rf)
    instr = 0xfe62d8e3 # bge x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc - 16) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_bge_false(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = -100
    rf["x6"] = +100
    set_registerfile(dut, rf)
    instr = 0xfe62d8e3 # bge x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc + 4) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_bltu_true(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = +100
    rf["x6"] = -100
    set_registerfile(dut, rf)
    instr = 0xfe62e8e3 # bltu x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc - 16) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_bltu_false(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = -100
    rf["x6"] = +100
    set_registerfile(dut, rf)
    instr = 0xfe62e8e3 # bltu x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc + 4) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_bgeu_true(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = -100
    rf["x6"] = -100
    set_registerfile(dut, rf)
    instr = 0xfe62f8e3 # bgeu x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc - 16) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

@cocotb.test()
async def test_b_bgeu_false(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    rf = get_registerfile(dut)
    rf["x5"] = +100
    rf["x6"] = -100
    set_registerfile(dut, rf)
    instr = 0xfe62f8e3 # bgeu x5, x6, -16
    await exec_instr(dut, instr)

    assert (initial_pc + 4) & 0xFFFF_FFFF == get_pc(dut)["current"]

    exec_nop(dut)

# TODO: Missing "system" instructions 
# FENCE
# FENCE.TSO
# PAUSE
# ECALL
# BREAK

def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32imc_ss_handshake"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / "rv32_mod_alu.sv",
        project_path / "rv32_mod_branch.sv",
        project_path / "rv32_mod_instruction_decoder.sv",
        project_path / "rv32_mod_instruction_decoder_func.sv",
        project_path / "rv32_mod_instruction_decoder_imm.sv",
        project_path / "rv32_mod_instruction_fetch.sv",
        project_path / "rv32_mod_load_store_unit.sv",
        project_path / "rv32_mod_pc.sv",
        project_path / "rv32_mod_registerfile.sv",
        project_path / "rv32_mod_types.sv",
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

    test_module = os.path.basename(__file__).replace(".py","")
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
