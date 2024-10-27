import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
from typing import Protocol
from enum import Enum

async def reset_dut(dut) -> None:
    dut.clken.value = 1
    dut.reset.value = 1
    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ns")
    dut.reset.value = 0
    
    dut.int_wr.value = 0
    dut.int_rd.value = 0
    dut.ext_ack.value = 0

# In every cycle call one of both:
# - prepare_if_int*
# - prepare_if_ext*

async def internal_issue_and_await(dut, addr: int, data_wr: int | None = None) -> None:
    pass
    # TODO
    return dut.int_data_o.value

def prepare_if_int_issue(dut, addr: int, data_wr: int | None = None):
    # assert dut.int_ack.value == 0, "USER ERROR: Can't issue new cmd yet"
    # assert dut.int_err.value == 0, "USER ERROR: Can't issue new cmd yet (ERROR)"

    dut.int_rd.value = 1 if data_wr is None else 0
    dut.int_wr.value = 0 if data_wr is None else 1
    dut.int_addr.value = addr
    dut.int_be.value = 0xF
    dut.int_data_i.value = data_wr if data_wr is not None else 0

def prepare_if_int_wait(dut):
    # assert dut.int_ack.value == 0, "USER ERROR: Can't issue new cmd yet"
    dut.int_wr.value = 0
    dut.int_rd.value = 0

def prepare_if_ext_service(dut):
    dut.ext_ack.value = 1
    dut.ext_data_i.value = dut.ext_addr.value

def prepare_if_ext_stall(dut):
    dut.ext_ack.value = 0

async def nop(dut):
    prepare_if_int_wait(dut)
    prepare_if_ext_stall(dut)
    await RisingEdge(dut.clk)

async def serve_single_word(dut, latency_max: int = 2):
    if dut.ext_rd.value == 0:
        await nop(dut)
        return

    for _ in range(2):
        await nop(dut)
    
    prepare_if_int_wait(dut)
    prepare_if_ext_service(dut)
    await RisingEdge(dut.clk)
    prepare_if_int_wait(dut)
    prepare_if_ext_stall(dut)


async def request_and_serve_assert_hit(dut, addr: int, latency_max: int = 2):
    prepare_if_int_issue(dut, addr=addr)
    prepare_if_ext_stall(dut)
    await Timer(1, "ps")
    assert True # TODO

    await RisingEdge(dut.clk)
    prepare_if_int_wait(dut)
    prepare_if_ext_stall(dut)

async def request_and_serve_assert_miss(dut, addr: int, latency_max: int = 2):
    prepare_if_int_issue(dut, addr=addr)
    prepare_if_ext_stall(dut)
    await RisingEdge(dut.clk)

    await serve_single_word(dut, latency_max)
    await serve_single_word(dut, latency_max)
    await serve_single_word(dut, latency_max)
    await serve_single_word(dut, latency_max)

@cocotb.test()
async def test_invalid_group(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    await request_and_serve_assert_miss(dut, 0x1001)
    await RisingEdge(dut.clk)

    for _ in range(5):
        await RisingEdge(dut.clk)

    await request_and_serve_assert_hit(dut, 0x1003)
    await RisingEdge(dut.clk)
    
    await nop(dut)

    await request_and_serve_assert_hit(dut, 0x1000)
    await RisingEdge(dut.clk)

    await request_and_serve_assert_hit(dut, 0x1002)
    await RisingEdge(dut.clk)

    await nop(dut)

    await request_and_serve_assert_miss(dut, 0x1004)
    await RisingEdge(dut.clk)

    for _ in range(5):
        await RisingEdge(dut.clk)

    return

    prepare_if_int_issue(dut, addr=0x1001)
    prepare_if_ext_stall(dut)
    await RisingEdge(dut.clk)

    await serve_single_word(dut, 2)
    await serve_single_word(dut, 1)
    await serve_single_word(dut, 2)
    await serve_single_word(dut, 1)

    prepare_if_int_issue(dut, addr=0x1003)
    await RisingEdge(dut.clk)
    await serve_single_word(dut, 1)

    for _ in range(3):
        await RisingEdge(dut.clk)

    return
    for _ in range(2):
        prepare_if_int_wait(dut)
        prepare_if_ext_stall(dut)
        await RisingEdge(dut.clk)
    
    prepare_if_int_wait(dut)
    prepare_if_ext_service(dut)
    await RisingEdge(dut.clk)

    for _ in range(3):
        prepare_if_int_wait(dut)
        prepare_if_ext_stall(dut)
        await RisingEdge(dut.clk)


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "icache"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / f"{hdl_toplevel}.sv",
        project_path / f"ram_dp_handshake.sv",
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
        waves=True
    )

    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{hdl_toplevel}_test,",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
