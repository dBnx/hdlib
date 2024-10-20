import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles

# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

from rv32imc_ss_handshake_program_snippets_test import get_registerfile, set_registerfile, get_pc, exec_nop, lsu_watcher, run_program, instr_list_to_program


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


@cocotb.test()
async def test_run_program_in_irom_utilize_iram_mmr(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    cocotb.log.warning(f"Loaded ROM: {dut.ROM_FILE.value}")
    await reset_dut(dut)

    dut.gpio_i[0].value = 0x12345678
    program_runner = cocotb.start_soon(run_program(
        dut.inst_hart, [], memory_regions_are_valid_instr=True, lsu_watcher_cb=None))
    timeout = ClockCycles(dut.clk, 30)
    await First(program_runner, timeout)
    await Timer(1, "ns")  # For better traces

    assert 0x12345678 == dut.gpio_o[0].value, "Program outputs to Gpio0 on success"

    await RisingEdge(dut.clk)

    # t1 = get_registerfile(dut)["x6"]


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32imc_ss_handshake_w_rom"
    sim = os.getenv("SIM", "verilator")
    project_path = Path(__file__).resolve().parent

    verilog_sources = [
        project_path / "rv32_mod_alu.sv",
        project_path / "rv32_mod_branch.sv",
        project_path / "rv32_mod_csrs.sv",
        project_path / "rv32_mod_instruction_decoder.sv",
        project_path / "rv32_mod_instruction_decoder_func.sv",
        project_path / "rv32_mod_instruction_decoder_imm.sv",
        project_path / "rv32_mod_instruction_fetch.sv",
        project_path / "rv32_mod_load_store_unit.sv",
        project_path / "rv32_mod_pc.sv",
        project_path / "rv32_mod_stallington.sv",
        project_path / "rv32_mod_registerfile.sv",
        project_path / "rv32_mod_types.sv",
        project_path / "rv32imc_ss_handshake.sv",
        project_path / "ram_dp_handshake.sv",
        # project_path / "kernel.test.irom.iram.mmr.mem",
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
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},", waves=True, extra_env={"WAVES": "1"}, parameters={
        # "ROM_FILE": "kernel.test.irom.iram.mmr.hex"
    })


if __name__ == "__main__":
    test_runner()
