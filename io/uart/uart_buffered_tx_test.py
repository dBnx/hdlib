import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


async def reset_dut(dut):
    # For a nicer trace
    await RisingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


def configure(dut, baud: int, freq: float, parity: bool = False) -> None:
    """Sets default values for the module"""
    dut.rst.value = 0
    dut.we.value = 0

    dut.baud_divider.value = int(freq / baud)
    dut.parity_en.value = 1 if parity else 0
    dut.parity_type_odd.value = 0


# TODO: Copied from uart_tx.py -> Refactor
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


@cocotb.test()
async def send_bytes(dut):
    clk_freq = 50e6
    clk_cycle = int(1e9 / 50e6)
    baud = 115200
    # Below not in sync with `configure`
    bits = 8
    parity = False
    parity_odd = True

    cocotb.start_soon(Clock(dut.clk, clk_cycle, units="ns")
                      .start())

    configure(dut, baud, clk_freq)
    await reset_dut(dut)

    # TODO: Impl test

    NUM_BYTES: int = 256

    async def write_byte(v: int) -> None:
        await Timer(1, "ns")  # Wait for combinatorial of `buffer_full`
        if dut.buffer_full.value == 1:
            await FallingEdge(dut.buffer_full)
        dut.data.value = v
        dut.we.value = 1
        await RisingEdge(dut.clk)
        dut.we.value = 0

    async def write_bytes() -> list[int]:
        bytes = []
        for i in range(NUM_BYTES):
            byte = (i + 1) % 255
            await write_byte(byte)
            bytes.append(byte)

        return bytes

    async def receive_bytes() -> list[int]:
        bytes = []
        for _ in range(NUM_BYTES):
            byte = await receive_symbol(dut, baud, bits,
                                        parity, parity_odd)
            bytes.append(byte)
        return bytes

    task_r = cocotb.start_soon(receive_bytes())
    task_w = cocotb.start_soon(write_bytes())

    wrote = await task_w
    read = await task_r

    await RisingEdge(dut.clk)

    assert wrote == read


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "uart_buffered_tx"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / f"{hdl_toplevel}.sv",
        project_path / "uart_tx.sv",
        project_path / "../../memory/fifo/fifo_simple.sv",
        project_path / "../../memory/ram/ram_partial_dp_scd.sv",
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
