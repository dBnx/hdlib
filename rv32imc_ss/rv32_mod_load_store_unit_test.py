import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

REQ_UNSIGNED = 0b0000
REQ_SIGNED   = 0b1000
REQ_WIDTH_8  = 0b0000
REQ_WIDTH_16 = 0b0001
REQ_WIDTH_32 = 0b0010

# TODO: Currently only 32b works / is tested

async def reset(dut) -> None:
    dut.req.value = 0
    dut.req_type.value = 0
    dut.wr.value = 0

    dut.dext_ack.value = 0
    dut.dext_err.value = 0
    dut.dext_di.value = 0

    dut.reset.value = 1
    await Timer(1, "ps")
    await RisingEdge(dut.clk)
    await Timer(1, "ps")

    dut.reset.value = 0
    await Timer(1, "ps")

@cocotb.test()
async def test_idle(dut) -> None:
    """ Reset and do not issue a request, then monitor I/O lines """
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

async def deassert_stall_after(dut, n_cycles: int, data: int|None = None, then_error: bool = False) -> None:
    """Mock external interface by:
    - Assert stall for n_cycles if non-zero
    - Then asser ack or err, depending on `then_error`
    - Deassert ack after the next pos edge
    """
    dut.stall.value = 1
    await Timer(1, "ps")

    for _ in range(n_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, "ns")

    if then_error is False:
        dut.dext_ack.value = 1
        if data is not None:
            dut.dext_di.value = data
    else:
        dut.dext_err.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, "ns")

    if then_error is False:
        dut.dext_ack.value = 0
    else:
        dut.dext_err.value = 0

    dut.dext_di.value = 0


async def latency_verification(dut, write_read: bool, data: int | None, latency: int):
    await Timer(2, "ps")

    # Check if request is issued
    assert 1 == dut.dext_req.value, "No request issued"
    assert write_read == dut.dext_wr.value, "Wrong request issued"
    if write_read is True:
        assert data is not None, "Write needs reference data"
        assert hex(data) == hex(dut.dext_do.value), "External IF has no data"

    # Wait `latency` and don't deassert
    for _ in range(latency):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk) # Wait for the mock to set signals
        # await Timer(1, "ns") 
        # await Timer(1, "ps") # Ensure they are propagated
        assert 1 == dut.dext_req.value, "No request issued"
        assert write_read == dut.dext_wr.value, "Wrong request issued"
        if write_read is True:
            assert hex(data) == hex(dut.dext_do.value), "External IF has no data or doesn't hold"

async def issue_command(dut, write_read: bool, addr: int, data: int | None = None, latency: int = 1, issue_ack: bool = True):
    assert addr > 0 and data > 0 and latency >= 0, "Invalid values"
    assert not ( write_read is True and data is None ), "Usage error: Write expects data"

    # Setup operation
    dut.req.value = 1
    dut.req_type.value = REQ_SIGNED | REQ_WIDTH_32
    dut.wr.value = 1 if write_read is True else 0
    dut.address.value = addr
    if data is not None:
        dut.data_i.value = data

    # Issue operation and start bus mock -> Delay ack by `latency`
    await RisingEdge(dut.clk)

    # Reset IF
    dut.req.value = 0
    dut.req_type.value = 0
    dut.wr.value = 0
    dut.address.value = 0
    if data is not None:
        dut.data_i.value = 0

    cocotb.start_soon(deassert_stall_after(dut, latency, data))

    # Wait for external and verify
    await latency_verification(dut, write_read, data, latency)

    await return_verification(dut, write_read, expect_ack=issue_ack, data=data)

    # Restore clean state
    dut.req.value = 0
    dut.req_type.value = 0
    dut.wr.value = 0


async def return_verification(dut, write_read: bool, expect_ack: bool, data: int | None = None):
    """Assuming the external bus (mocked) responds in this cycle:
    - Check for a termination signal on external
    - Wait one edge to pass through to the HART IF
    - Verify received signals
    """
    assert not ( write_read is True and data is None ), "Usage error: Write expects data"

    await Timer(1, "ns")

    # Check if delayed ack is issued
    if expect_ack is True:
        assert 1 == dut.dext_ack.value, "Expected external ack"
        assert 0 == dut.dext_err.value
    else:
        assert 0 == dut.dext_ack.value
        assert 1 == dut.dext_err.value

    # NOTE: Ack takes also 1 cycle to pass through ..
    await RisingEdge(dut.clk)
    await Timer(1, "ns")
    
    assert 1 if expect_ack is True else 0 == dut.valid.value, "Expected ack"
    assert 1 if expect_ack is False else 0 == dut.error.value, "Expected err"
    assert 0 == dut.stall.value
    if write_read is False and expect_ack:
        assert data == dut.data_o.value

    # NOTE: Meaning it's now at the HART Interface
    # TODO: Check if again in idle - not sure why note exists
    # assert 0 == dut.dext_req.value
    # assert 0 == dut.dext_wr.value
    # assert 0 == dut.valid.value
    # assert 0 == dut.error.value
    # assert 0 == dut.stall.value
    # assert 0 == dut.data_o.value
    # TODO: Check stall from 0 to here

@cocotb.test()
async def test_write32_single(dut) -> None:
    """ Issue writes with zero latency feedback """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)
    await Timer(1, "ps")

    latency =random.randint(1,4) 
    data = random.getrandbits(32)
    addr = random.getrandbits(32)

    await Timer(1, "ns")
    await issue_command(dut, write_read=True, addr=addr, data=data, latency=latency)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert 0 == dut.valid
    assert 0 == dut.stall

@cocotb.test()
async def test_write32_two_read_back(dut) -> None:
    """ Issue writes with zero latency feedback """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset(dut)
    await Timer(1, "ps")

    data_a = random.getrandbits(32)
    data_b = random.getrandbits(32)
    addr_a = random.getrandbits(32)
    addr_b = random.getrandbits(32)
    while addr_b == addr_a:
        addr_b = random.getrandbits(32)

    await Timer(1, "ns")
    await issue_command(dut, write_read=True,  addr=addr_a, data=data_a, latency=random.randint(1,2))
    await RisingEdge(dut.clk)
    await issue_command(dut, write_read=True,  addr=addr_b, data=data_b, latency=random.randint(1,2))
    await issue_command(dut, write_read=False, addr=addr_a, data=data_a, latency=random.randint(1,2))
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert 0 == dut.valid
    assert 0 == dut.stall

# TODO: Implement different widths: 16b, 8b
# @cocotb.test()
async def test_write_instant_ack_100(dut) -> None:
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
async def test_write_instant_ack_200(dut) -> None:
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
async def test_write_instant_ack_300(dut) -> None:
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
    )

    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{hdl_toplevel}_test,",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    random.seed()

    test_runner()
