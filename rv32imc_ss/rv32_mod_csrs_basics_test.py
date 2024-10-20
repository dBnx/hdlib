import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

# TODO:
# - [ ] CSR Swap csrrw x0, MSCRATCH, x0
# - [ ] Vendor, HART ID, impl, ..


MSCRATCH: int = 0x340
MCYCLE: int = 0xB00
MCYCLEH: int = 0xB02
MTIME: int = 0x701
MTIMEH: int = 0x702

async def reset(dut) -> None:
    dut.rst.value = 1

    dut.priviledge.value = 0b11
    dut.wr.value = 0
    dut.rd.value = 0
    dut.addr.value = 0
    dut.data_i.value = 0

    dut.interrupts.value = 0

    dut.exception_instr_addr_misaligned.value = 0
    dut.exception_instr_access_fault.value = 0
    dut.exception_illegal_instruction.value = 0
    dut.exception_breakpoint.value = 0
    dut.exception_load_addr_misaligned.value = 0
    dut.exception_load_access_fault.value = 0
    dut.exception_store_addr_misaligned.value = 0
    dut.exception_store_access_fault.value = 0
    dut.exception_ecall_from_u_mode.value = 0
    dut.exception_ecall_from_s_mode.value = 0
    dut.exception_ecall_from_m_mode.value = 0
    dut.exception_instr_page_fault.value = 0
    dut.exception_load_page_fault.value = 0
    dut.exception_store_page_fault.value = 0

    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ps")
    dut.rst.value = 0
    await Timer(1, "ps")

@cocotb.test()
async def test_reset(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    # HART Interface
    assert 0 == dut.error.value
    assert 0 == dut.data_o.value

    assert 0 == dut.serve_trap.value

    assert dut.INITIAL_MSTATUS.value == dut.mstatus.value
    assert dut.INITIAL_MTVEC.value == dut.mtvec.value
    assert 0 == dut.mepc.value
    assert 0 == dut.mtval.value
    assert 0 == dut.mip.value
    assert 0 == dut.mie.value

    assert 0 == dut.csr_mcycle.value
    assert 0 == dut.csr_mtime.value

async def csrrw(dut, addr: int, din : int|None, priviledge: int = 0b11, perform_no_read: bool = False) -> int: 
    """If `din` is None, then no write to the CSR is perfomed. This equates to issuing the `csrrw` instruction with x0.
    As there are no side-effects for reads in the current implementation, a read is always performed.
    """
    assert priviledge is None or priviledge in [0b00, 0b01, 0b11]

    # await Timer(1, "ps")
    dut.addr.value = addr
    dut.rd.value = 1 if perform_no_read is False else 0
    dut.wr.value = 1 if din is not None else 0
    dut.data_i.value = din if din is not None else 0
    if priviledge is not None:
        dut.priviledge.value = priviledge

    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ps")

    dut.rd.value = 0
    dut.wr.value = 0
    dut.addr.value = 0

    return dut.data_o.value

@cocotb.test()
async def test_mscratch_rw_and_ro(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    assert 0x0000_0000 == await csrrw(dut, addr=MSCRATCH, din=0x1234_5678)
    assert 0x1234_5678 == await csrrw(dut, addr=MSCRATCH, din=0x5678_9ABC)
    assert 0x5678_9ABC == await csrrw(dut, addr=MSCRATCH, din=None)
    assert 0x5678_9ABC == await csrrw(dut, addr=MSCRATCH, din=None)

    # Even after we wait, data is persistant and unchanged from reads
    for _ in range(3):
        await RisingEdge(dut.clk)

    assert 0x5678_9ABC == await csrrw(dut, addr=MSCRATCH, din=None)
    assert 0x5678_9ABC == await csrrw(dut, addr=MSCRATCH, din=None)

@cocotb.test()
async def test_mcycle_read(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    # Continuously increases and is single cycle:
    mcycle_start = await csrrw(dut, addr=MCYCLE, din=None)
    assert mcycle_start + 1 == await csrrw(dut, addr=MCYCLE, din=None)
    assert mcycle_start + 2 == await csrrw(dut, addr=MCYCLE, din=None)

    # Also if nobody is lookin
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert mcycle_start + 6 == await csrrw(dut, addr=MCYCLE, din=None)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_mcycle_read_high(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    dut.csr_mcycle.value = 0xFFFFFFFF
    await Timer(1, "ps")

    mcycle_high_old = await csrrw(dut, addr=MCYCLEH, din=None)
    mcycle_low = await csrrw(dut, addr=MCYCLE, din=None)
    mcycle_high_new = await csrrw(dut, addr=MCYCLEH, din=None)

    assert mcycle_high_new != mcycle_high_old

    await RisingEdge(dut.clk)

def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_csrs"
    subclass: str = "_basics"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / f"{hdl_toplevel}.sv",
    ]

    # "-O3"
    build_args = ["--trace", "--trace-structs", "--trace-params"] if sim == "verilator" else []
    runner = get_runner(sim)
    runner.build(
        verilog_sources=verilog_sources,
        vhdl_sources=[],
        hdl_toplevel=hdl_toplevel,
        # always=True,
        build_args=build_args,
        build_dir=f"build/{hdl_toplevel}",
        waves=True,
    )

    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{hdl_toplevel}{subclass}_test,",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    random.seed()

    test_runner()
