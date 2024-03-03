import cocotb
from cocotb.clock import Clock
# from cocotb.regression import TestFactory
from cocotb.triggers import RisingEdge, FallingEdge


async def configure(dut) -> None:
    """Sets default values for the module"""
    clk_freq = 50e6
    clk_cycle = int(1e9 / clk_freq)
    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    dut.we.value = 0
    dut.re.value = 0
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def write_value(dut, addr: int, value: int) -> None:
    assert dut.DEPTH.value > addr, "Test writes to invalid addr"
    assert 2**dut.DATA_WIDTH.value > value, "Test writes invalid symbol"

    dut.we.value = 1
    dut.w_data.value = value
    dut.w_addr.value = addr
    await RisingEdge(dut.clk)
    dut.we.value = 0


async def read_value(dut, addr: int) -> int:
    assert dut.DEPTH.value > addr, "Test writes to invalid addr"

    dut.re.value = 1
    dut.r_addr.value = addr
    await RisingEdge(dut.clk)
    value = dut.r_data.value
    dut.re.value = 0
    return value


async def write_read_value(dut, write_addr: int, value: int,
                           read_addr: int) -> int:
    """Write and read in the same clock cycle"""
    assert dut.DEPTH.value > read_addr, "Test writes to invalid addr"
    assert dut.DEPTH.value > write_addr, "Test writes to invalid addr"
    assert 2**dut.DATA_WIDTH.value > value, "Test writes invalid symbol"

    # Write
    dut.we.value = 1
    dut.w_addr.value = write_addr
    dut.w_data.value = value
    # Read
    dut.re.value = 1
    dut.r_addr.value = read_addr

    await RisingEdge(dut.clk)
    value = dut.r_data.value

    dut.we.value = 0
    dut.re.value = 0

    return value


@cocotb.test()
async def single_read_writes(dut):
    await configure(dut)

    # Single, seperate write and read
    for addr in range(dut.DEPTH.value):
        value = (addr+1) % 255
        await write_value(dut, addr, value)

    for addr in range(dut.DEPTH.value):
        read = await read_value(dut, addr)
        assert addr+1 == read, "Written and read value do not match"


@cocotb.test()
async def overwrite_value(dut):
    await configure(dut)

    addr = 0x03

    value = 0x55
    await write_value(dut, addr, value)
    read = await read_value(dut, addr)
    assert value == read, "Written and read value do not match"

    value = 0xCC
    await write_value(dut, addr, value)
    read = await read_value(dut, addr)
    assert value == read, "Written and read value do not match"

@cocotb.test()
async def simultanious_write_read_passthrough(dut):
    await configure(dut)

    # Test pass-through at same address
    value = 1
    addr = 2
    read = await write_read_value(dut, addr, value, addr)
    await RisingEdge(dut.clk)
    assert value == read, \
        "Write and read same address should yield written value"

    value = (addr+1) % 255
    await write_value(dut, addr, value)

    # Read again to test if it's really in memory
    read = await read_value(dut, addr)
    assert value == read, "Written and read value do not match"


@cocotb.test()
async def simultanious_write_read_different_addr(dut):
    await configure(dut)

    value_a = 0xBB
    value_b = 0x55
    addr_a = 0x03
    addr_b = 0x05

    await write_value(dut, addr_a, value_a)
    read_a = await write_read_value(dut, addr_b, value_b, addr_a)
    assert value_a == read_a, ""

    read_b = await read_value(dut, addr_b)
    assert value_b == read_b, "Written and read value do not match"


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "ram_partial_dp_scd"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / f"{hdl_toplevel}.sv"
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
