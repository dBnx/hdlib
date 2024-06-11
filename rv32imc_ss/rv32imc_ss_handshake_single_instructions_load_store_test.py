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
async def test_s_sb(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x5"] = -2
    rf["x6"] = 0x100
    set_registerfile(dut, rf)

    instr = 0x005300a3 # SB x5, 1(x6)
    dut.data_ack.value = 1
    dut.data_data_i.value = 0x1234
    await exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 1 == dut.data_wr.value
    assert 0b0010 == dut.data_be.value
    assert 0x100 + 0 == dut.data_addr.value
    # assert 0x1234 == get_registerfile(dut)["x5"]

    exec_nop(dut)

# @cocotb.test()
async def test_s_sh(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x5"] = -2
    rf["x6"] = 0x100
    set_registerfile(dut, rf)

    instr = 0x00531323 # SH x5, 6(x6)
    await exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 1 == dut.data_wr.value
    assert 0b1100 == dut.data_be.value
    assert 0x100 + 4 == dut.data_addr.value

    # Check that it's waiting
    initial_pc = get_pc(dut)["current"]
    for i in range(10):
        await RisingEdge(dut.clk)
    await Timer(1, "ps")

    assert initial_pc == get_pc(dut)["current"], "HART pauses during LSU stall"

    dut.data_ack.value = 1
    dut.data_data_i.value = 0x1234
    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ps")
    dut.data_ack.value = 0

    # assert 0x1234 == get_registerfile(dut)["x5"]

    exec_nop(dut)

# @cocotb.test()
async def test_s_sw(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x5"] = -2
    rf["x6"] = 0x100
    set_registerfile(dut, rf)

    instr = 0x00532223 # SW x5, 4(x6)
    await exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 1 == dut.data_wr.value
    assert 0xF == dut.data_be.value
    assert 0x100 + 4 == dut.data_addr.value

    exec_nop(dut)

# @cocotb.test()
async def test_s_lb(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x6"] = 0x100
    set_registerfile(dut, rf)

    instr = 0x00130283 # lb x5, 1(x6)
    await exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0b0010 == dut.data_be.value
    assert 0x100 + 1 == dut.data_addr.value
    assert -2 & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    exec_nop(dut)

# TODO: Acknoweldge the stores
# TODO: Acknoweldge the loads
# LB
# LH
# LW
# LBU
# LHU

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
