
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

from cohelper import rv32imc

async def reset_dut(dut):
    dut.reset.value = 1

    dut.instr_ack.value = 0
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0

    dut.data_ack.value = 0
    dut.data_err.value = 0
    dut.data_data_i.value = 0
    await Timer(1, "ps")

    await RisingEdge(dut.clk)

    dut.reset.value = 0
    await Timer(1, "ps")

# TODO: Comment in other tests.
#       Currently verilator has a bug and doesn't export traces. Because of that icarus is used.
#       Icarus doesn't implement switch cases with bitmasks, so only 32b I/O operations ccan be tested.

# TODO: - Hart should wait until store / load is resolved
#       - Model should not ACK data after reset
#       - Extend tests to check for ACK
#       - Set ACK in model after N? cycles
#         - Check that PC doesn't increase
#         - Also set if_valid to true to check lsu_stalling instead of if_stalling

async def ack_after(dut, n_cycles: int = 1):
    """Sets data_ack after `n_cycles` cycles for one cycle, resets.and
    awaits the LSU cycle."""
    await RisingEdge(dut.clk) 
    for _ in range(3):
        await RisingEdge(dut.clk) 
        assert 0 == dut.data_req.value

    await Timer(1, "ns")
    dut.data_ack.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, "ns")

    dut.data_ack.value = 0

    await Timer(1, "ns")
    await RisingEdge(dut.clk)
    await Timer(1, "ns")

@cocotb.test()
async def test_s_sb(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)
    await Timer(1, "ps")

    rf = rv32imc.get_registerfile(dut)
    rf["x5"] = -2
    rf["x6"] = 0x100
    rv32imc.set_registerfile(dut, rf)

    instr = 0x005300a3 # SB x5, 1(x6)
    # Instant ackowledge write
    dut.data_data_i.value = 0x1234
    await rv32imc.exec_instr(dut, instr)
    await Timer(1, "ns")

    assert 1 == dut.data_req.value
    assert 1 == dut.data_wr.value
    assert 0b0010 == dut.data_be.value
    assert 0x100 + 0 == dut.data_addr.value

    await ack_after(dut, 4)
    # await RisingEdge(dut.clk)
    # await Timer(1, "ns")
    # dut.data_ack.value = 1
    
    # await RisingEdge(dut.clk)
    # await Timer(1, "ns")

    # dut.data_ack.value = 0

    # await Timer(1, "ns")
    # await RisingEdge(dut.clk)
    # await Timer(1, "ns")

    assert 0 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0 == dut.data_addr.value

    await rv32imc.exec_nop(dut)

@cocotb.test()
async def test_s_sh(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)
    await Timer(1, "ps")

    rf = rv32imc.get_registerfile(dut)
    rf["x5"] = -2
    rf["x6"] = 0x100
    rv32imc.set_registerfile(dut, rf)

    instr = 0x00531323 # SH x5, 6(x6)
    await rv32imc.exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 1 == dut.data_wr.value
    assert 0b1100 == dut.data_be.value
    assert 0x100 + 4 == dut.data_addr.value # FIXME: Check address offset and bitmask

    # Check that it's waiting
    initial_pc = rv32imc.get_pc(dut)["current"]

    await ack_after(dut, 2)

    assert initial_pc == rv32imc.get_pc(dut)["current"], "HART pauses during LSU stall"

    # Finally acknowledge
    # dut.data_ack.value = 1
    # await Timer(1, "ps")
    # await RisingEdge(dut.clk)
    # await Timer(1, "ps")
    # dut.data_ack.value = 0
    # await Timer(1, "ps")

    assert 0 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0 == dut.data_addr.value

    await rv32imc.exec_nop(dut)

@cocotb.test()
async def test_s_sw(dut) -> None:
    """Store word (32b)"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)
    await Timer(1, "ps")

    rf = rv32imc.get_registerfile(dut)
    rf["x5"] = -2 # Data
    rf["x6"] = 0x100  # Address
    rv32imc.set_registerfile(dut, rf)

    instr = 0x00532223 # SW x5, 4(x6)
    await rv32imc.exec_instr(dut, instr)
    await Timer(1, "ns")

    assert 1 == dut.data_req.value
    assert 1 == dut.data_wr.value
    assert 0xF == dut.data_be.value
    assert 0x100 + 4 == dut.data_addr.value

    # Stall for multiple cycles
    await ack_after(dut, 4)


    assert 0 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0 == dut.data_addr.value

    await rv32imc.exec_nop(dut)

# @cocotb.test()
async def test_s_lb(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = rv32imc.get_registerfile(dut)
    rf["x6"] = 0x100
    rv32imc.set_registerfile(dut, rf)

    instr = 0x00130283 # lb x5, 1(x6)
    await rv32imc.exec_instr(dut, instr)
    await FallingEdge(dut.clk)

    assert 1 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0b0010 == dut.data_be.value
    assert 0x100 + 0 == dut.data_addr.value, "offset of one is within a data word"
    assert -2 & 0xFFFF_FFFF == rv32imc.get_registerfile(dut)["x5"]

    await rv32imc.exec_nop(dut)

# @cocotb.test()
async def test_s_lh(dut) -> None:
    # TODO: Copy & Paste
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = rv32imc.get_registerfile(dut)
    rf["x6"] = 0x100
    rv32imc.set_registerfile(dut, rf)

    instr = 0x00231283 # lh x5, 2(x6)
    await rv32imc.exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0b0010 == dut.data_be.value
    assert 0x100 + 1 == dut.data_addr.value
    assert -2 & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    # Check that it's waiting
    initial_pc = rv32imc.get_pc(dut)["current"]
    for i in range(10):
        await RisingEdge(dut.clk)
    await Timer(1, "ps")

    assert initial_pc == rv32imc.get_pc(dut)["current"], "HART pauses during LSU stall"

    dut.data_ack.value = 1
    dut.data_data_i.value = 0x1234
    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ps")
    dut.data_ack.value = 0

    # assert 0x1234 == get_registerfile(dut)["x5"]

    await rv32imc.exec_nop(dut)

# @cocotb.test()
async def test_s_lw(dut) -> None:
    # TODO: Copy & Paste
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x6"] = 0x100
    set_registerfile(dut, rf)

    instr = 0x00432283 # lw x5, 4(x6)
    await rv32imc.exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0b1111 == dut.data_be.value
    assert 0x100 + 1 == dut.data_addr.value
    assert -2 & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    await rv32imc.exec_nop(dut)

# @cocotb.test()
async def test_s_lbu(dut) -> None:
    # TODO: Copy & Paste
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x6"] = 0x100
    set_registerfile(dut, rf)

    instr = 0x00234283 # lbu x5, 2(x6)
    await rv32imc.exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0b0100 == dut.data_be.value
    assert 0x100 + 1 == dut.data_addr.value
    assert -2 & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    await rv32imc.exec_nop(dut)

# @cocotb.test()
async def test_s_lhu(dut) -> None:
    # TODO: Copy & Paste
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    rf = get_registerfile(dut)
    rf["x6"] = 0x100
    set_registerfile(dut, rf)

    instr = 0x00435283 # lhu x5, 4(x6)
    await rv32imc.exec_instr(dut, instr)

    assert 1 == dut.data_req.value
    assert 0 == dut.data_wr.value
    assert 0b0010 == dut.data_be.value
    assert 0x100 + 1 == dut.data_addr.value
    assert -2 & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    await rv32imc.exec_nop(dut)

# TODO: Acknoweldge the stores
# TODO: Acknoweldge the loads

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
        waves=True,
    )

    test_module = os.path.basename(__file__).replace(".py","")
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
