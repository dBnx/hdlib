from cocotb.triggers import Timer


async def send_symbol(dut, baud: int, value: int, bits: int = 8,
                      parity=False, parity_odd=False):
    assert value <= 0xFF and value >= 0, f"Provided byte is not valid: {value}"
    assert bits == 8

    cycle = 1. / float(baud)
    time_bit = Timer(int(cycle * 1e9), 'ns')

    # Start bit
    dut.rx.value = 0
    await time_bit

    # Data bits
    parity = 0
    for i in range(bits):
        bit = (value >> i) & 1
        dut.rx.value = bit
        parity = parity ^ bit
        await time_bit

    # Parity bit
    if parity is True:
        assert parity >= 0 and parity <= 1
        dut.rx.value = 1 ^ parity if parity_odd else parity
        await time_bit

    # Stop bit
    dut.rx.value = 1
    await time_bit
