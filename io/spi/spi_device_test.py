import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

# Clock polarity: 
# - CPOL = 0 Arctive high -> Sample at rising and by default is 0
# - CPOL = 1 Arctive high -> Sample at rising and by default is 0
# Clock phase
# - CPHA = 0 Sample at first clock edge
# - CPHA = 1 Sample at second clock edge
# SPI Mode: {CPOL, CPHA} = 0 .. 3 with 0 being the most common.
# To support daisy chaining:
# - Pass trhough as long as CS is low (high) and only evaluate data when
# - CS is inative / high (low)

async def reset_dut(dut):
    await FallingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0


def configure(dut, baud: int, freq: float, parity: bool = False) -> None:
    """Sets default values for the module"""
    raise "IMPLEMENT"
    # dut.rst.value = 0
    # dut.baud_divider.value = int(freq / baud)
    # dut.parity_en.value = 1 if parity else 0
    # dut.parity_type_odd.value = 0
    # dut.start.value = 0


@cocotb.test()
async def test_async_routines(dut):
    from dataclasses import dataclass

    @dataclass
    class mock_interface:
        pass

    mock = mock_interface()
    mock.cs = mock_interface()
    mock.cs.value = 1
    mock.sck = mock_interface()
    mock.sck.value = 0
    mock.so = mock_interface()
    mock.so.value = 0
    mock.si = mock_interface()
    mock.si.value = 0

    cocotb.start_soon()

    n, cmd = await peripheral_read(mock, bits=8)
    assert n == 0, "Not all required bits read"
    n = await peripheral_write(mock, cmd)
    assert n == 0, "Not all required bits written"

    await RisingEdge(mock.cs)
    await Timer(2, "ns")


@cocotb.test()
async def simple_writes(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / 50e6)
    baud = 115200
    # uart_sink = UartSink(dut.tx, baud=baud, bits=8)
    # Below not in sync with `configure`
    bits = 8
    parity = False
    parity_odd = True

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    configure(dut, baud, clk_freq)
    await reset_dut(dut)

    async def send_and_expect(dut, data_tx: int) -> None:
        rx_task = cocotb.start_soon(
            receive_symbol(dut, baud, bits, parity, parity_odd)
        )

        await send_byte(dut, data_tx)

        data_rx = await rx_task

        assert data_tx == data_rx, "Sent data does not match received data"

    for v in range(256):
        await send_byte(dut, v)

    # For nicer traces:
    await Timer(int(1./float(baud) * 4 * 1e9), 'ns')


@cocotb.test()
async def expect_wrong_baud_fails(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / 50e6)
    baud = 115200
    # uart_sink = UartSink(dut.tx, baud=baud, bits=8)
    # Below not in sync with `configure`
    bits = 8
    parity = False
    parity_odd = True

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns").start())

    configure(dut, baud, clk_freq)
    await reset_dut(dut)

    data_tx = 0x05
    try:
        rx_task = cocotb.start_soon(
            receive_symbol(dut, baud >> 1, bits, parity, parity_odd)
        )

        await send_byte(dut, data_tx)

        data_rx = await rx_task

        # await Timer(int(1./float(baud) * 12 * 1e9), 'ns')
        # data_rx = await uart_sink.read(count=1)
        assert data_tx == data_rx, "Sent data does not match received data"
    except AssertionError as e:
        if "Sent data does not match received data" not in e.__str__():
            raise e
    else:
        assert False, "Wrong baud works"


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "uart_tx"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [project_path / "uart_tx.sv"]

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
