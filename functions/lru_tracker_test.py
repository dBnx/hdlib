import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

# module lru_tracker #(
#   parameter int N = 3
# ) (
#   // <<< System >>>
#   input  logic                    clk,
#   input  logic                    reset,
#   // <<< IO >>>
#   input  logic                    use,
#   output logic                    lru
# );


async def reset_dut(dut):
    dut.rst.value = 1
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0


@cocotb.test()
async def simple_writes(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)
    await Timer(1, 'ns')
    assert dut.lru == 1, "LRU should be active at reset"

    dut.en.value = 1
    dut.use.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, 'ns')
    assert dut.lru == 0, "LRU should be inactive after use"

    for _ in range(dut.N.value - 1):
        await RisingEdge(dut.clk)
        await Timer(1, 'ns')
        assert dut.lru == 0, "LRU should be inactive after use"

    await RisingEdge(dut.clk)
    await Timer(1, 'ns')
    assert dut.lru == 1, f"LRU should be active after {dut.N.value} non-usages"

    # Still enabled
    await RisingEdge(dut.clk)
    await Timer(1, 'ns')
    assert dut.lru == 1, "LRU should be active after N non-usages"

    await Timer(1, 'ns')


@cocotb.test()
async def test_chip_enable(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, 'ns')
    # TODO:


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "lru_tracker"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [project_path / f"{hdl_toplevel}.sv"]

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
