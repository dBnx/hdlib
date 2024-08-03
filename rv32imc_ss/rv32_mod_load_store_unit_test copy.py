import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

REQ_UNSIGNED = 0b0000
REQ_SIGNED   = 0b1000
REQ_WIDTH_8  = 0b0000
REQ_WIDTH_16 = 0b0001
REQ_WIDTH_32 = 0b0010

# Create memory mock

async def reset(dut) -> None:
    dut.req.value = 0
    dut.req_type.value = 0
    dut.wr.value = 0

    dut.dext_ack.value = 0
    dut.dext_err.value = 0

    dut.reset.value = 1
    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ps")

    dut.reset.value = 0
    await Timer(1, "ps")

# @cocotb.test()
async def test_idle(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    # HART Interface
    assert 0 == dut.valid.value
    assert 0 == dut.error.value
    assert 0 == dut.stall.value
    assert 0 == dut.data_o.value

    # External Interface
    assert 0 == dut.dext_req.value
    assert 0 == dut.dext_wr.value
    assert 0 == dut.dext_do.value

    for _ in range(3):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")
        
        # HART Interface
        assert 0 == dut.valid.value
        assert 0 == dut.error.value
        assert 0 == dut.stall.value
        assert 0 == dut.data_o.value

        # External Interface
        assert 0 == dut.dext_req.value
        assert 0 == dut.dext_wr.value
        assert 0 == dut.dext_do.value

async def deassert_stall_after(dut, n_cycles: int, then_error: bool = False) -> None:
    dut.stall.value = 1
    await Timer(1, "ps")

    for _ in range(n_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, "ps")

    if then_error if False:
        dut.dext_ack.value = 1
    else:
        dut.dext_error.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, "ps")

    if then_error if False:
        dut.dext_ack.value = 0
    else:
        dut.dext_error.value = 0

@cocotb.test()
async def test_write32_instant_ack(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    data_word = 0x1234
    latency = 1

    await reset(dut)

    # Issue write
    dut.req.value = 1
    dut.req_type.value = REQ_SIGNED | REQ_WIDTH_32
    dut.wr.value = 1

    dut.dext_ack.value = 0
    dut.dext_err.value = 0
    await RisingEdge(dut.clk)

    # Delay ack by `latency`
    cocotb.start_soon(deassert_stall_after(dut, latency))

    # Check if request is issued
    await Timer(1, "ps")
    assert 1 == dut.dext_req.value
    assert 1 == dut.dext_wr.value
    assert data == dut.dext_do.value

    # Wait `latency` and don't deassert
    for _ in range(latency):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")
        assert 1 == dut.dext_req.value
        assert 1 == dut.dext_wr.value
        assert data == dut.dext_do.value

    # Check if delayed ack is issued
    assert 1 == dut.dext_ack.value
    # TODO: Ack takes also 1 cycle to pass through ..

    await RisingEdge(dut.clk)
    await Timer(1, "ps")

    # TODO: Meaning it's now at the HART Interface
    # Check if again in idle
    assert 0 == dut.dext_req.value
    assert 0 == dut.dext_wr.value
    assert 0 == dut.valid.value
    assert 0 == dut.error.value
    assert 0 == dut.stall.value
    assert 0 == dut.data_o.value
    # TODO: Check stall from 0 to here

    await RisingEdge(dut.clk)
    await Timer(1, "ps")

    # TODO: And now cleared
    # External Interface

    for _ in range(3):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")

# @cocotb.test()
async def test_write_instant_ack(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    # HART Interface
    assert 0 == dut.valid.value
    assert 0 == dut.error.value
    assert 0 == dut.stall.value
    assert 0 == dut.data_o.value

    # External Interface
    assert 0 == dut.dext_req.value
    assert 0 == dut.dext_wr.value
    assert 0 == dut.dext_do.value

    for _ in range(3):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")

# @cocotb.test()
async def test_write_instant_ack(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    # HART Interface
    assert 0 == dut.valid.value
    assert 0 == dut.error.value
    assert 0 == dut.stall.value
    assert 0 == dut.data_o.value

    # External Interface
    assert 0 == dut.dext_req.value
    assert 0 == dut.dext_wr.value
    assert 0 == dut.dext_do.value

    for _ in range(3):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")

# @cocotb.test()
async def test_write_instant_ack(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)

    # HART Interface
    assert 0 == dut.valid.value
    assert 0 == dut.error.value
    assert 0 == dut.stall.value
    assert 0 == dut.data_o.value

    # External Interface
    assert 0 == dut.dext_req.value
    assert 0 == dut.dext_wr.value
    assert 0 == dut.dext_do.value

    for _ in range(3):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")

    # timing_check_h = cocotb.start_soon(vga_timing_checker_hsync(dut))
    # timing_check_v = cocotb.start_soon(vga_timing_checker_vsync(dut))

    # await First(test_time, timing_check_h, timing_check_v)

    # ///// HART Interface
    # input        req,
    # input [ 3:0] req_type, // [S,U]; Reserved; Size
    # input        wr,
    # input [31:0] address,
    # input [31:0] data_i,
    # ///// External interf
    # output        dext_req,
    # output        dext_wr,
    # input         dext_ack,
    # input         dext_err,
    # output [ 3:0] dext_be,
    # output [31:0] dext_addr,
    # output [31:0] dext_do,
    # input  [31:0] dext_di


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_load_store_unit"
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
