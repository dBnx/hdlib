import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

# TODO: Implement

# module rv32_mod_branch (
#     input  [31:0] rf_read0,
#     input  [31:0] rf_read1,
#     input  [ 2:0] cond,
#     input         is_cond,
#     input         is_jmp,
#     output        branch_taken
# );

### Test functions ###

@cocotb.test()
async def test_jump_always_taken(dut) -> None:
    for _ in range(16):
        take_branch = random.getrandbits(1)

        dut.is_jmp.value = take_branch
        dut.is_cond.value = random.getrandbits(1) if take_branch == 1 else 0
        dut.cond.value = random.getrandbits(2)
        dut.rf_read0.value = random.getrandbits(32)
        dut.rf_read1.value = random.getrandbits(32)

        await Timer(1, "ps")

        if take_branch != dut.branch_taken.value:
            base = "Branch not taken, even tough it should" if take_branch == 1 else \
                            "Branch taken, even tough it shouldn't "
            rf0 = f"{int(dut.rf_read0.value):4X}"
            rf1 = f"{int(dut.rf_read1.value):4X}"
            details = f"is_jmp={dut.is_jmp.value} is_cond={dut.is_cond.value} cond={dut.cond.value} rf0={rf0} rf1={rf1}"
            
            assert dut.branch_taken.value == take_branch, f"{base}: {details}"

        await Timer(1, "ps")

### Helper functions ###

### Runner ###

def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_branch"
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
        waves=True,
    )

    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{hdl_toplevel}_test,",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    random.seed()

    test_runner()
