import cocotb
from cocotb.clock import Clock
# from cocotb.regression import TestFactory
from cocotb.triggers import RisingEdge, FallingEdge, Timer

# TODO:
# - Read @ empty
# - Write @ full

# module fifo_simple #(
#   parameter int DEPTH = 64,
#   parameter int DATA_WIDTH = 8
# ) (
#     input logic                   clk,
#     input logic                   rst,
#     // <<<< Write Port >>>>
#     input logic                   we,
#     input logic  [DATA_WIDTH-1:0] din,
#     // <<<< Read Port >>>>
#     input logic                   re,
#     output logic [DATA_WIDTH-1:0] dout,
#     // <<<< Status >>>>
#     output logic                  full,
#     output logic                  empty
# );


async def reset_dut(dut):
    await FallingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0


def configure(dut) -> None:
    """Sets default values for the module"""
    dut.rst.value = 0
    dut.we.value = 0
    dut.re.value = 0


async def write_value(dut, value: int) -> None:
    dut.we.value = 1
    dut.din.value = value
    await RisingEdge(dut.clk)
    dut.we.value = 0
    await Timer(1, "ns")
    assert 0 == dut.empty.value, "After write empty is false"


async def read_value(dut) -> int:
    dut.re.value = 1
    await RisingEdge(dut.clk)
    value = dut.dout.value
    dut.re.value = 0
    await Timer(1, "ns")
    return value


async def write_read_value(dut, value: int) -> int:
    dut.re.value = 1
    dut.we.value = 1
    dut.din.value = value
    await RisingEdge(dut.clk)
    value = dut.dout.value
    dut.we.value = 0
    dut.re.value = 0
    await Timer(1, "ns")
    return value


@cocotb.test()
async def single_read_writes(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / clk_freq)

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    configure(dut)
    await reset_dut(dut)

    assert 1 == dut.empty.value, "Fifo after reset is empty"
    assert 0 == dut.full.value, "Fifo after reset is not full"
    assert 0 == dut.dout, "Value when empty is zero"

    # Single, seperate write and read
    value = 0x55

    await write_value(dut, value)
    assert 0 == dut.empty.value, ""
    assert 0 == dut.full.value, ""

    read = await read_value(dut)
    assert value == read, ""
    # await FallingEdge(dut.clk)
    assert 1 == dut.empty.value, ""
    assert 0 == dut.full.value, ""

    # Fill FIFO up
    for i in range(dut.DEPTH.value - 1):
        assert 0 == dut.full.value, ""
        await write_value(dut, i)
        assert 0 == dut.empty.value, ""

    assert 1 == dut.full.value, ""


@cocotb.test()
async def simultanious_write_read_when_empty(dut):
    # TODO: Ceck when empty and not empty
    clk_freq = 50e6
    clk_cycle = int(1e9 / clk_freq)

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    configure(dut)
    await reset_dut(dut)
    assert 1 == dut.empty.value, "Fifo after reset is empty"
    assert 0 == dut.dout.value, "Value when empty is zero"

    value = 0xBB

    read = await write_read_value(dut, value)
    assert value == read, ""
    assert 1 == dut.empty.value, ""
    assert 0 == dut.full.value, ""


@cocotb.test()
async def simultanious_write_read_not_empty(dut):
    # TODO: Ceck when empty and not empty
    clk_freq = 50e6
    clk_cycle = int(1e9 / clk_freq)

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    configure(dut)
    await reset_dut(dut)
    assert 1 == dut.empty.value, "Fifo after reset is empty"
    assert 0 == dut.dout.value, "Value when empty is zero"

    # Write A
    value_a = 0x55
    await write_value(dut, value_a)
    assert 0 == dut.empty.value, ""
    assert 0 == dut.full.value, ""

    # Write B; Read A
    value_b = 0xBB
    read_a = await write_read_value(dut, value_b)
    assert value_a == read_a, ""
    assert 0 == dut.empty.value, ""
    assert 0 == dut.full.value, ""

    # Read B
    read_b = await read_value(dut)
    assert value_b == read_b, ""
    assert 1 == dut.empty.value, ""
    assert 0 == dut.full.value, ""


@cocotb.test()
async def overflow(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / clk_freq)

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    depth = dut.DEPTH.value
    for i in range(depth):
        await write_value(dut, i)
        assert 0 == dut.empty.value, "Not empty after write w/o read"

    value = dut.dout.value
    for i in range(10):
        assert 1 == dut.full.value, "After full stays full"
        assert 0 == dut.empty.value, "When full it's not empty"
        assert depth-1 == dut.entries.value, "Number of entries is stable"
        assert value == dut.dout.value, "Output value is stable"
        await write_value(dut, i % 3)


@cocotb.test()
async def underflow(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / clk_freq)

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    for _ in range(dut.DEPTH.value):
        await read_value(dut)
        assert 0 == dut.full.value, "Not full after read w/o write"

    for _ in range(10):
        assert 1 == dut.empty.value, "After empty stays empty"
        assert 0 == dut.full.value, "When empty it's not full"
        assert 0 == dut.entries.value, "Number of entries is stable"
        await read_value(dut)


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "fifo_simple"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / "fifo_simple.sv",
        project_path / "../ram/ram_partial_dp_scd.sv"
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


