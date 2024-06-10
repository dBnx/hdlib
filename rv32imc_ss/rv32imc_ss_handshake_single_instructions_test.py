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
async def test_r_add(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    rf = get_registerfile(dut)
    rf["x5"] = 0b0000_0110
    rf["x6"] = 0b0000_0101
    set_registerfile(dut, rf)

    instr = 0x006283B3 # ADD x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0xB == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_sub(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # 5 | 9 = D
    rf = get_registerfile(dut)
    rf["x5"] = 0b0000_0110
    rf["x6"] = 0b0000_0101
    set_registerfile(dut, rf)

    instr = 0x406283b3 # SUB x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 1 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_and(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # 5 | 9 = D
    rf = get_registerfile(dut)
    rf["x5"] = 0b0101_0101
    rf["x6"] = 0b1001_1001
    set_registerfile(dut, rf)

    instr = 0x0062f3b3 # AND x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0b0001_0001 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_or(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # 5 | 9 = D
    rf = get_registerfile(dut)
    rf["x5"] = 0b0101_0101
    rf["x6"] = 0b1001_1001
    set_registerfile(dut, rf)

    instr = 0x0062e3b3 # OR x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0b1101_1101 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_xor(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # 5 | 9 = D
    rf = get_registerfile(dut)
    rf["x5"] = 0b0101_0101
    rf["x6"] = 0b1001_1001
    set_registerfile(dut, rf)

    instr = 0x0062c3b3 # XOR x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0b1100_1100 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_sll(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # 5 | 9 = D
    rf = get_registerfile(dut)
    rf["x5"] = 0b0000_0011
    rf["x6"] = 0b0000_0011
    set_registerfile(dut, rf)

    instr = 0x006293B3 # SLL x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0x18 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_srl(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # 5 | 9 = D
    rf = get_registerfile(dut)
    rf["x5"] = 0xFFFF_FFFF
    rf["x6"] = 4
    set_registerfile(dut, rf)

    instr = 0x0062D3B3 # SRL x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0x0FFF_FFFF == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_sra(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    rf = get_registerfile(dut)
    rf["x5"] = 0xFFFF_FFFF
    rf["x6"] = 4
    set_registerfile(dut, rf)

    instr = 0x4062D3B3 # SRA x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0xFFFF_FFFF == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_slt_true(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    rf = get_registerfile(dut)
    rf["x5"] = -4
    rf["x6"] = +3
    set_registerfile(dut, rf)

    instr = 0x0062a3b3 # SLT x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 1 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_slt_false(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    rf = get_registerfile(dut)
    rf["x5"] = +3
    rf["x6"] = -4
    set_registerfile(dut, rf)

    instr = 0x0062a3b3 # SLT x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_sltu_true(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x5"] = 4
    rf["x6"] = 6
    set_registerfile(dut, rf)

    instr = 0x0062b3b3 # SLTU x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 1 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_r_sltu_false(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x5"] = 6
    rf["x6"] = 4
    set_registerfile(dut, rf)

    instr = 0x0062b3b3 # SLTU x7, x5, x6
    await exec_instr(dut, instr)

    rf = get_registerfile(dut)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert 0 == rf["x7"]

    exec_nop(dut)

@cocotb.test()
async def test_u_lui(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    instr = 0xfffff2b7 # LUI x5, -1
    await exec_instr(dut, instr)
    assert (-1 << 12) & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    instr = 0xffc182b7 # LUI x5, -1000
    await exec_instr(dut, instr)
    assert (-1000 << 12) & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    exec_nop(dut)

@cocotb.test()
async def test_u_auipc(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    instr = 0x00001297 # AUIPC x5, 1
    await exec_instr(dut, instr)

    assert initial_pc + 1 << 12 == get_registerfile(dut)["x5"]

    exec_nop(dut)

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
