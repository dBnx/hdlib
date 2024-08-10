import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

# TODO: Implement

# module rv32_mod_pc #(
#     parameter logic [31:0] INITIAL_GP = 32'h10000000
# ) (
#     input        clk,
#     input        reset,
# 
#     input         stall,
#     input         is_compressed,
#     output logic [31:0] pc_current,
#     output logic [31:0] pc_next,
# 
#     input  [31:0] pc_overwrite_data,
#     input         pc_overwrite_enable
# );

### Test functions ###

@cocotb.test()
async def test_normal_operation(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())

    await reset_dut(dut)

    assert dut.INITIAL_GP.value ==  dut.pc_current.value, "Initial value not correct after reset"

    for _ in range(8):
        is_compressed = random.getrandbits(1)
        dut.is_compressed.value = is_compressed
        await Timer(1, "ps")
        last_next = dut.pc_next.value.integer

        await RisingEdge(dut.clk)
        await Timer(1, "ps")

        step = dut.pc_next.value - dut.pc_current.value
        assert step == (4 if is_compressed == 0 else 2), f"PC wants to step by {step}. {is_compressed=}"
        assert dut.pc_current.value.integer == last_next


    # timing_check_h = cocotb.start_soon(vga_timing_checker_hsync(dut))
    # timing_check_v = cocotb.start_soon(vga_timing_checker_vsync(dut))

    # await First(test_time, timing_check_h, timing_check_v)

### Helper functions ###

async def reset_dut(dut):
    dut.reset.value = 1
    dut.stall.value = 0
    dut.is_compressed.value = 0
    dut.pc_overwrite_data.value = 0
    dut.pc_overwrite_enable.value = 0

    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0
    await Timer(1, "ps")

### Runner ###

def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_pc"
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
    random.seed()

    test_runner()
