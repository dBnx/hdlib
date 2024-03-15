
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


def configure(dut, baud: int, freq: float, parity: bool = False) -> None:
    """Sets default values for the module"""
    raise "IMPLEMENT"
    # dut.rst.value = 0
    # dut.baud_divider.value = int(freq / baud)
    # dut.parity_en.value = 1 if parity else 0
    # dut.parity_type_odd.value = 0
    # dut.start.value = 0


async def peripheral_read(dut, bits: int | None = 8):
    """
    Reads up to `bits` bits and returns the amount of bits sampled, as well as
    the received data. If `bits` is `None`, then bits are sampled until the
    peripheral is deselected.
    """
    assert bits is None or bits > 0, "Invalid number of bits to read"

    # Wait for initiation
    if dut.cs.value == 1:
        await FallingEdge(dut.cs)

    # Sample bits
    n_bits, data = 0, 0
    while await [RisingEdge(dut.sck), RisingEdge(dut.cs)]:
        if dut.cs.value == 1:
            break

        n_bits += 1
        data = data & (dut.si.value << n_bits)

        if bits is not None and n_bits == bits:
            break

    return n_bits, data


async def peripheral_write(dut, value: int, bits: int = 8) -> int:
    """
    Returns the amount of bits not written. A 0 means therefore, that
    all bits where successfully transfered.
    """

    # Wait for initiation
    if dut.cs.value == 1:
        await FallingEdge(dut.cs)

    dut.so.value = (value >> bits) & 1
    n_bits = bits - 1
    while await [RisingEdge(dut.sck), RisingEdge(dut.cs)]:
        if dut.cs.value == 1:
            break

        dut.so.value = (value >> n_bits) & 1
        n_bits -= 1

        if n_bits == 0:
            break

    return bits - n_bits


async def peripheral_ignore_clks(dut, n_clks: int = 2) -> int:
    """
    Returns the remaining clocks, that wheren't awaited. Could be non-zero if
    controller deselects the device prematurely.
    """
    n_bits, _ = await peripheral_read(dut, n_clks)
    return n_bits

