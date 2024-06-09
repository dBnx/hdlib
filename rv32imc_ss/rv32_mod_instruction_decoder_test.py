import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

#    input  [31:0] instruction,
#
#    output [ 4:0] rf_read0_index,
#    output [ 4:0] rf_read1_index,
#    output [ 4:0] rf_write0_index,
#
#    output [ 5:0] instruction_format,
#    output [ 5:0] func,
#    output        is_compressed

# {is_r_type, is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j};
IFORMAT: dict[str,int] = {
    "R": 0b100000,
    "I": 0b010000,
    "S": 0b001000,
    "B": 0b001100,
    "U": 0b000010,
    "J": 0b000011,
}

@cocotb.test()
async def test_type_r(dut) -> None:
    dut.instruction.value = 0x003100b3 # add x1, x2, x3
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 2 == dut.rf_read0_index.value
    assert 3 == dut.rf_read1_index.value
    assert 1 == dut.rf_write0_index.value
    assert IFORMAT["R"] == dut.instruction_format.value

    dut.instruction.value = 0x0062f233 # and x4, x5, x6
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 5 == dut.rf_read0_index.value
    assert 6 == dut.rf_read1_index.value
    assert 4 == dut.rf_write0_index.value
    assert IFORMAT["R"] == dut.instruction_format.value

@cocotb.test()
async def test_type_i(dut) -> None:
    dut.instruction.value = 0x00000013 # addi x0, x0, 0
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 0 == dut.rf_read0_index.value
    assert 0 == dut.rf_write0_index.value
    assert IFORMAT["I"] == dut.instruction_format.value

    dut.instruction.value = 0x00128293 # addi x5, x5, 1
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 5 == dut.rf_read0_index.value
    assert 5 == dut.rf_write0_index.value
    assert IFORMAT["I"] == dut.instruction_format.value

    dut.instruction.value = 0x008300e7 # jalr x1, 8(x6)
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 6 == dut.rf_read0_index.value
    assert 1 == dut.rf_write0_index.value
    assert IFORMAT["I"] == dut.instruction_format.value

@cocotb.test()
async def test_type_s(dut) -> None:
    dut.instruction.value = 0x00852023 # sw x8, 0(x10)
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 10 == dut.rf_read0_index.value
    assert 8 == dut.rf_read1_index.value
    assert IFORMAT["S"] == dut.instruction_format.value

    dut.instruction.value = 0x008500a3 # sb x8, 1(x10)
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 10 == dut.rf_read0_index.value
    assert 8 == dut.rf_read1_index.value
    assert IFORMAT["S"] == dut.instruction_format.value

@cocotb.test()
async def test_type_b(dut) -> None:
    dut.instruction.value = 0x0083c263 # blt x7, x8, 4
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 7 == dut.rf_read0_index.value
    assert 8 == dut.rf_read1_index.value
    assert IFORMAT["B"] == dut.instruction_format.value

    
    dut.instruction.value = 0x00b50063 # beq x10, x11, 0
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 10 == dut.rf_read0_index.value
    assert 11 == dut.rf_read1_index.value
    assert IFORMAT["B"] == dut.instruction_format.value

@cocotb.test()
async def test_type_u(dut) -> None:
    dut.instruction.value = 0x0007b337 # lui x6, 123
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 6 == dut.rf_write0_index.value
    assert IFORMAT["U"] == dut.instruction_format.value

    dut.instruction.value = 0xfffb0f17 # auipc x30, -80
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 30 == dut.rf_write0_index.value
    assert IFORMAT["U"] == dut.instruction_format.value

@cocotb.test()
async def test_type_j(dut) -> None:
    dut.instruction.value = 0x008000ef # jal x1, 8
    await Timer(1, "ps")
    assert 0 == dut.is_compressed.value
    assert 0 == dut.rf_read0_index.value
    assert 1 == dut.rf_write0_index.value
    assert IFORMAT["J"] == dut.instruction_format.value


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_instruction_decoder"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / f"{hdl_toplevel}.sv",
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
