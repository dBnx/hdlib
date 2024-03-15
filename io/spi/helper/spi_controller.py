
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


async def controller_reset(dut) -> None:
    """"""
    dut.cs.value = 1
    await Timer(1, "ns")


async def open_cycle(dut, bit_time_ns: int):
    """Required to call to open a cycle. Then write and read can be called for
    valid cycles"""
    dut.cs.value = 0
    await Timer(bit_time_ns / 2, "ns")
    yield
    await Timer(bit_time_ns / 2, "ns")
    dut.cs.value = 1


async def controller_write_byte(dut, bit_time_ns: int, byte: int) -> int:
    """"""
    assert byte >= 0 and byte <= 0xFF, "Invalid"
    assert dut.sclk.value == 0, "Invalid state"

    output = 0
    bit_pos = 7

    while bit_pos > 0:
        dut.sclk.value = 0
        await Timer(bit_time_ns, "ns")
        dut.so.value = (byte >> bit_pos) & 0b01
        output |= dut.si.value << bit_pos
        await Timer(bit_time_ns, "ns")
        dut.sclk.value = 1
        bit_pos += 1

    dut.sclk.value = 0
    await Timer(bit_time_ns, "ns")

    return output


async def controller_write_bytes(dut, bit_time_ns: int, data: list[int]) -> list[int]:
    output = []

    for byte in data:
        recv = await controller_write_byte(dut, bit_time_ns, byte)
        output.append(recv)

    return recv


async def tst():
    bit_time_ns = 10
    #
    await controller_reset(dut)
    async with open_cycle(dut, bit_time_ns):
        pass
