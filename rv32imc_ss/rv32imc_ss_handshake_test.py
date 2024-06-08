import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass


@cocotb.test()
async def test_foo(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    # await reset_dut(dut)

    # timing_check_h = cocotb.start_soon(vga_timing_checker_hsync(dut))
    # timing_check_v = cocotb.start_soon(vga_timing_checker_vsync(dut))

    # await First(test_time, timing_check_h, timing_check_v)


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
    )

    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{hdl_toplevel}_test,",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
