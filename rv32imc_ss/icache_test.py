import cocotb
import random
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

async def internal_issue_and_await(dut, addr: int, data_wr: int | None = None, ext_latency_max: int = 3) -> tuple[int, int] | None:
    """
    At least a cycle between calls to this function is needed.

    Returns
     - tuple[int, int]: Tuple of the return value and the amount of cycles for the request
    """
    assert dut.int_ack.value == 0 and dut.int_error.value == 0 and dut.int_hit == 0 and dut.int_miss == 0,\
        "USER ERROR: Please await at least one cycle before calling this function again"
    await Timer(1, "ns")

    # Issue internal
    dut.int_rd.value = 1 if data_wr is None else 0
    dut.int_wr.value = 0 if data_wr is None else 1
    dut.int_addr.value = addr
    dut.int_be.value = 0xF
    dut.int_data_i.value = data_wr if data_wr is not None else 0

    await Timer(1, "ns")

    # Check HIT / MISS
    hit = dut.int_hit.value
    miss = dut.int_miss.value 
    assert hit == 1 or miss == 1, "Neither HIT nor MISS was issued"

    if hit == 1 and dut.int_ack.value == 1:
        data_o = dut.int_data_o.value
        await Timer(1, "ns")
        dut.int_rd.value = 0
        dut.int_wr.value = 0
        # Accessing currently active cache line
        return data_o, 0

    # Wait for the response:
    cycles = 0
    TIMEOUT: int = 4 * 3 * max(1, ext_latency_max)
    for _ in range(TIMEOUT):
        if dut.int_ack.value == 1:
            break
        elif dut.int_error.value == 1:
            return None

        await RisingEdge(dut.clk)
        cycles += 1
        dut.int_rd.value = 0
        dut.int_wr.value = 0
    else:
        cocotb.log.error("Timeout for internal request expired ..")
        return None
    
    # If we get here, then we ack was asserted and we may read the data
    dut.int_rd.value = 0
    dut.int_wr.value = 0
    await Timer(1, "ns")
    return dut.int_data_o.value, cycles

async def external_service_requests(dut, max_latency: int = 3, timeout: int = 50) -> None:
    dut.ext_ack.value = 0
    dut.ext_error.value = 0
    for _ in range(timeout):
        if dut.ext_rd.value == 1:
            # READ
            latency = random.randint(1, max(1, max_latency))

            addr = dut.ext_addr.value
            cocotb.log.warning(f"EXT: READ from {int(addr):08x} with latency={latency}")
            for _ in range(latency):
                await RisingEdge(dut.clk)
                assert dut.ext_rd.value == 0 and dut.ext_wr.value == 0, "Request was issued too early"

            assert addr == dut.ext_addr.value, "Ext IF: Address must be stable"
            dut.ext_data_i.value = addr
            dut.ext_ack.value = 1
            await RisingEdge(dut.clk)

        elif dut.ext_wr.value == 1:
            cocotb.log.error("EXTERNAL INTERFACE: WRITE")
            # WRITE
            raise NotimplementedError("Writes are not implemented in mock")

        else:
            # IDLE
            dut.ext_data_i.value = dut.ext_addr.value
            dut.ext_ack.value = 0
            await RisingEdge(dut.clk)

    else:
        pass

@cocotb.test()
async def test_within_cache_line(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    external = cocotb.start_soon(external_service_requests(dut, max_latency=1))

    await RisingEdge(dut.clk) # RMME


    data_o, cycles = await internal_issue_and_await(dut, addr=0x1000)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1000
    assert cycles > 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x1002)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1002
    assert cycles == 0
    
    data_o, cycles = await internal_issue_and_await(dut, addr=0x1001)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1001
    assert cycles == 0

    data_o, cycles = await internal_issue_and_await(dut, addr=0x1003)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1003
    assert cycles == 0

    await RisingEdge(dut.clk)

@cocotb.test()
async def test_different_cache_lines(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    external = cocotb.start_soon(external_service_requests(dut, max_latency=1))

    await RisingEdge(dut.clk) # RMME


    data_o, cycles = await internal_issue_and_await(dut, addr=0x1000)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1000
    assert cycles > 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x1004)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1004
    assert cycles > 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x1008)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1008
    assert cycles > 5
    

@cocotb.test()
async def test_cache_line_eviction(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    external = cocotb.start_soon(external_service_requests(dut, max_latency=1))

    await RisingEdge(dut.clk) # RMME


    data_o, cycles = await internal_issue_and_await(dut, addr=0x1001)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x1001
    assert cycles > 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x5001)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x5001
    assert cycles > 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x9001)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x9001
    assert cycles > 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x9001)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x9001
    assert cycles == 0

@cocotb.test()
async def test_cach_line_alternate_access(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    external = cocotb.start_soon(external_service_requests(dut, max_latency=1))

    await RisingEdge(dut.clk) # RMME


    # Initial requests
    data_o, cycles = await internal_issue_and_await(dut, addr=0x2001)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x2001
    assert cycles > 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x8001 + 8)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x8001 + 8
    assert cycles > 5

    # Every other request must be cached
    data_o, cycles = await internal_issue_and_await(dut, addr=0x2002)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x2002
    assert cycles > 0 and cycles < 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x8003 + 8)
    await RisingEdge(dut.clk)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x8003 + 8
    assert cycles > 0 and cycles < 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x2000)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x2000
    assert cycles > 0 and cycles < 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x8000 + 8)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x8000 + 8
    assert cycles > 0 and cycles < 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x2003)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x2003
    assert cycles > 0 and cycles < 5

    data_o, cycles = await internal_issue_and_await(dut, addr=0x8002 + 8)
    cocotb.log.warning(f"Request took {cycles} cycles")
    assert data_o == 0x8002 + 8
    assert cycles > 0 and cycles < 5


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
