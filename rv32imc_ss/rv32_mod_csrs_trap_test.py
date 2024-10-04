import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

from rv32_mod_csrs_basics_test import reset, csrrw

MSCRATCH: int = 0x340


# TODO: Mini
# - Exception: illegal_instruction
# - Exception: timer
# - Exception: ecall_from_m_mode
# - Exception: load_access_fault
# - Interrupt: external

@cocotb.test()
async def test_trap_exception_illegal_instruction(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)
    
    dut.current_pc.value = 0x0123
    dut.faulting_address.value = 0x0234
    dut.faulting_instruction.value = 0x0456

    dut.exception_illegal_instruction.value = 1
    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ps")
    dut.exception_illegal_instruction.value = 0
    await Timer(1, "ps")

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    
    

    # assert 0x0000_0000 == await csrrw(dut, addr=MSCRATCH, din=0x1234_5678)
    # assert 0x1234_5678 == await csrrw(dut, addr=MSCRATCH, din=0x5678_9ABC)
    # assert 0x5678_9ABC == await csrrw(dut, addr=MSCRATCH, din=None)


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_csrs"
    subclass: str = "_trap"
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
