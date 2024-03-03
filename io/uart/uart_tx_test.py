import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


async def reset_dut(dut):
    await FallingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0


def configure(dut, baud: int, freq: float, parity: bool = False) -> None:
    """Sets default values for the module"""
    dut.rst.value = 0
    dut.baud_divider.value = int(freq / baud)
    dut.parity_en.value = 1 if parity else 0
    dut.parity_type_odd.value = 0
    dut.start.value = 0


async def wait_until_not_busy(dut) -> None:
    """Returns immediatly if not busy and otherwise waits until it is"""
    if dut.busy.value == 1:
        await FallingEdge(dut.busy)


async def send_byte(dut, byte: int) -> None:
    """
    Assumes a configured dut. Sends one byte and returns at next posedge
    If the dut is busy, it wait's until it's free again.
    """
    assert byte <= 0xFF and byte >= 0, f"Provided byte is not valid: {byte}"

    await wait_until_not_busy(dut)
    dut.data.value = byte
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


async def receive_symbol(dut, baud: int, bits=8,
                         parity=False, parity_odd=False):

    # async def receive():
    cycle = 1. / float(baud)
    time_half_bit = Timer(int(cycle * 1e9 / 2.), 'ns')
    time_bit = Timer(int(cycle * 1e9), 'ns')

    value = 0

    # Wait for start
    await FallingEdge(dut.tx)

    # Start bit
    await time_half_bit
    assert 0 == dut.tx.value, "Start bit is invalid"

    # Data bits
    parity_bit = 0
    for i in range(bits):
        await time_bit
        data_bit = dut.tx.value & 1

        value |= data_bit << i
        parity_bit ^= data_bit

    # Parity bit
    if parity is True:
        await time_bit
        data_bit = dut.tx.value & 1

        parity_bit = ~parity_bit if parity_odd else parity_bit
        assert parity_bit == data_bit, "Parity does not match!"

    # Stop bit
    await time_bit
    assert dut.tx.value == 1, "Stop bit is invalid"

    # self.log.info("Read byte 0x%02x", b)
    return value

    # timer = Timer(period_ns + 10, 'ns')
    # return cocotb.start(receive())
    # result = await First(timer, task)


# async def send_byte(dut, byte: int) -> None:
#     dut.start.value = 1
#     dut.data.value = byte
#     assert dut.busy.value == 0, "Module is not ready"
#     await RisingEdge(dut.clk)
#     dut.start.value = 0
#     dut.rst.value = 0


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
