import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles

# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

from rv32imc_ss_handshake_program_snippets_test import get_registerfile, set_registerfile, get_pc, exec_nop, lsu_watcher, run_program, instr_list_to_program

ADDI_X0_X0_0 = 0x00000013
SW_X5_0_GP = 0x0051a023
SW_X6_1_GP = 0x0061a0a3
LW_X7_0_GP = 0x0001a383
LW_X8_1_GP = 0x0011a403

class QuitMessage(BaseException):
    """Used to gracefully close parallel running tasks"""

    pass


async def reset_dut(dut):
    dut.reset.value = 1
    dut.instr_ack.value = 0
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0
    await Timer(1, "ps")

    await RisingEdge(dut.clk)

    dut.reset.value = 0
    await Timer(1, "ps")


"""Defines R/W memory regions for a program"""
MemoryRegions: type = list[tuple[int, int]]
"""RAM mock mapping address to data"""
Memory: type = dict[int, int]
"""Defines two regions: After INITIAL_GP and close to address zero"""
DefaultMemoryRegions = [(1024, 4096), ((1 << 31), (1 << 31) + 4096)]


addi_x5_x0_5 = 0x00500293
addi_x6_x0_1 = 0x00100313
beq_x5_x0_36 = 0x02028263
addi_x7_x0_0 = 0x00000393
addi_x28_x0_0 = 0x00000e13
add_x7_x7_x6 = 0x006383b3
addi_x28_x28_1 = 0x001e0e13
bne_x28_x5_m8 = 0xfe5e1ce3
addi_x6_x7_0 = 0x00038313
addi_x5_x5_m1 = 0xfff28293
jal_x0_m32 = 0xfe1ff06f
addi_x0_x0_0 = 0x00000013


@cocotb.test()
async def test_factorial_with_soft_imul(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    program = instr_list_to_program(
        dut,
        [
            addi_x5_x0_5,
            addi_x6_x0_1,
        # factorial_loop: + 0x08
            beq_x5_x0_36, # forward to endloop
            addi_x7_x0_0,
            addi_x28_x0_0,
        # multiply: + 0x14
            add_x7_x7_x6,
            addi_x28_x28_1,
            bne_x28_x5_m8, # back to multiply
            addi_x6_x7_0,
            addi_x5_x5_m1,
            jal_x0_m32, # back to factorial_loop
        # endloop: + 0x2C
            addi_x0_x0_0,
        ],
    )

    program_runner = cocotb.start_soon(run_program(dut, program))
    timeout = ClockCycles(dut.clk, 12)
    await First(program_runner, timeout)

    await RisingEdge(dut.clk)

    x5 = get_registerfile(dut)["x5"]
    five_factorial = 120
    assert five_factorial == x5, "If not, first instruction is executed multiple times"


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32imc_ss_handshake"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / "rv32_mod_alu.sv",
        project_path / "rv32_mod_branch.sv",
        project_path / "rv32_mod_instruction_decoder.sv",
        project_path / "rv32_mod_instruction_decoder_func.sv",
        project_path / "rv32_mod_instruction_decoder_imm.sv",
        project_path / "rv32_mod_instruction_fetch.sv",
        project_path / "rv32_mod_load_store_unit.sv",
        project_path / "rv32_mod_pc.sv",
        project_path / "rv32_mod_stallington.sv",
        project_path / "rv32_mod_registerfile.sv",
        project_path / "rv32_mod_types.sv",
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
        waves=True,
    )

    test_module = os.path.basename(__file__).replace(".py", "")
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},", waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
