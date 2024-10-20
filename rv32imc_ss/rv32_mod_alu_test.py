import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
from typing import Protocol
from enum import Enum

# module rv32_mod_alu (
#     input  bit        force_add,
#     input  bit [ 6:0] funct7,
#     input  bit [ 2:0] funct3,
#     input  bit [31:0] read0_data,
#     input  bit [31:0] read1_data,
#     output bit [31:0] result,
#     output bit        error
# );

F7_BASE     = 0b0000000
F7_BASE_ALT = 0b0100000
F7_MULDIV   = 0b0000001

# @dataclass
# class Operation:
#     f7_funct: int
#     f3_funct: int
Operation = tuple[int, int]

Op: dict[str, Operation] = {
    "ADD" : (F7_BASE,     0b000),
    "SUB" : (F7_BASE_ALT, 0b000),
    "SRL" : (F7_BASE,     0b101),
    "SRA" : (F7_BASE_ALT, 0b101),
    "MUL" : (F7_MULDIV,   0b000),
    "MULH": (F7_MULDIV,   0b001),
}

async def op(dut, operation: Operation, read0: int, read1: int, expect_result: int, expect_error: bool = False):
    dut.funct7.value = operation[0]
    dut.funct3.value = operation[1]
    dut.read0_data.value = read0
    dut.read1_data.value = read1
    await Timer(1, "ps")

    readable_operation = f""
    if expect_error is True:
        assert dut.error.value == 1, f"{readable_operation} -> Expected error"
    else:
        assert dut.error.value == 0, f"{readable_operation} -> Expected no error"
        assert dut.result.value == expect_result, f"{readable_operation} -> Expected {expect_result}"

# @cocotb.test()
async def test_invalid_group(dut) -> None:
    # TODO: Expand to all possibilities

    await op(dut, 0b0101010, funct3=0b000, read0=0, read1=1, expect_result=0, expect_error=True)
    await op(dut, F7_MULDIV, funct3=0b111, read0=0, read1=1, expect_result=0, expect_error=True) # M not implemented -> Fail

@cocotb.test()
async def test_base(dut) -> None:

    await op(dut, Op["ADD"], read0=0, read1=0, expect_result=0)
    await op(dut, Op["ADD"], read0=0, read1=1, expect_result=1)
    await op(dut, Op["ADD"], read0=1, read1=0, expect_result=1)
    await op(dut, Op["ADD"], read0=1, read1=1, expect_result=2)

    await op(dut, Op["SRL"], read0=6, read1=1, expect_result=3)
    await op(dut, Op["SRL"], read0=0xFFFF_FFFF, read1=1, expect_result=0x7FFF_FFFF)


@cocotb.test()
async def test_base_ext(dut) -> None:

    await op(dut, Op["SUB"], read0=1, read1=0, expect_result=1)
    await op(dut, Op["SUB"], read0=3, read1=2, expect_result=1)

    await op(dut, Op["SRA"], read0=6, read1=1, expect_result=3)
    await op(dut, Op["SRA"], read0=0xFFFF_FFFF, read1=1, expect_result=0xFFFF_FFFF)

@cocotb.test()
async def test_muldiv_mul(dut) -> None:

    await op(dut, Op["MUL"], read0= 0, read1= 0, expect_result=0)
    await op(dut, Op["MUL"], read0= 1, read1= 0, expect_result=0)
    await op(dut, Op["MUL"], read0= 0, read1= 1, expect_result=0)
    await op(dut, Op["MUL"], read0= 1, read1= 1, expect_result=1)
    await op(dut, Op["MUL"], read0=-1, read1= 1, expect_result=0xFFFF_FFFF)
    await op(dut, Op["MUL"], read0= 1, read1=-1, expect_result=0xFFFF_FFFF)
    await op(dut, Op["MUL"], read0=-1, read1=-1, expect_result=1)

    await op(dut, Op["MUL"],  read0=0x0001_0000, read1=0x0001_0000, expect_result=0)
    await op(dut, Op["MULH"], read0=0x0001_0000, read1=0x0001_0000, expect_result=1)


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_alu"
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
        waves=True
    )

    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{hdl_toplevel}_test,",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
