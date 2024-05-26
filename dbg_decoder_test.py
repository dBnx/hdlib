import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from helper import uart


async def reset_dut(dut):
    dut.recv_data.value = 0
    dut.recv_data_valid.value = 0
    dut.recv_busy.value = 0
    dut.recv_error_detected.value = 0
    await FallingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0


@cocotb.test()
async def send_bytes(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / 50e6)

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    await reset_dut(dut)

    async def send_and_expect(dut, data_tx: int) -> None:
        task = cocotb.start_soon(
            uart.send_symbol(dut, baud, data_tx, bits, parity, parity_odd)
        )

        data_rx = await receive_valid_byte(dut)
        await task
        # TODO: Should not be necessary, but STOP bit is not fully respected

        assert data_tx == data_rx, "Sent data does not match received data"

    # TODO: Set 256
    # for v in range(256):
    for v in range(256):
        await send_and_expect(dut, v)

    # For nicer traces:
    await Timer(int(1./float(baud) * 4 * 1e9), 'ns')


@cocotb.test()
async def invalid_transaction(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / 50e6)
    baud = 115200
    bits = 8
    parity = False
    parity_odd = True

    bit_time_ns = 1./float(baud) * 1e9

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    async def stay_low_for(time: float):
        configure(dut, baud, clk_freq)
        await reset_dut(dut)

        await FallingEdge(dut.clk)
        await FallingEdge(dut.clk)

        assert 0 == dut.error_detected.value, "Reset state is valid"

        dut.rx.value = 0

        await Timer(int(time), 'ns')

    # Invalid start bit
    cocotb.start_soon(stay_low_for(0.2 * bit_time_ns))
    # TODO: Timeout with error "Invalid start bit should cause error"
    await RisingEdge(dut.error_detected)
    await Timer(int(2 * bit_time_ns), 'ns')
    assert 1 == dut.error_detected.value, "Error persistent while rx reset"
    dut.rx.value = 1
    await FallingEdge(dut.error_detected)

    # Invalid stop bit / disconnected
    cocotb.start_soon(stay_low_for(15. * bit_time_ns))
    # TODO: Timeout with error "Invalid stop bit should cause error"
    await RisingEdge(dut.error_detected)
    dut.rx.value = 1
    await FallingEdge(dut.error_detected)

    # For nicer traces:
    await Timer(int(1./float(baud) * 4 * 1e9), 'ns')


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "uart_rx"
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


