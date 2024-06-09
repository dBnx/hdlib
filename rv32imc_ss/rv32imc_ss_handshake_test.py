import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

async def reset_dut(dut):
    dut.reset.value = 1
    dut.instr_ack.value = 0
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0
    await Timer(1, "ps")

    await RisingEdge(dut.clk)

    dut.reset.value = 0
    await Timer(1, "ps")

def get_registerfile(dut) -> dict[str, int]:
    ret: dict[str,int] = {}
    for i, v in enumerate(dut.inst_registerfile.registerfile.value):
        ret[f"x{i}"] = v
    return ret

def get_pc(dut) -> dict[str, int]:
    return {
        "current":dut.pc_current.value,
        "next"   :dut.pc_next.value
    }

@cocotb.test()
async def test_wait_for_instruction(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    await RisingEdge(dut.clk)
    initial_registers = get_pc(dut)["current"]

    await ClockCycles(dut.clk, 10)
    assert initial_registers == get_pc(dut)["current"]
    # timing_check_h = cocotb.start_soon(vga_timing_checker_hsync(dut))
    # timing_check_v = cocotb.start_soon(vga_timing_checker_vsync(dut))

    # await First(test_time, timing_check_h, timing_check_v)

@cocotb.test()
async def test_repeated_addi_nop(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")
    dut.instr_ack.value = 1
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0x0000_0013 # addi x0, x0, 0
    pc = get_pc(dut)
    rf = get_registerfile(dut)

    await ClockCycles(dut.clk, 10)

    assert pc["current"] != get_pc(dut)["current"]
    assert rf == get_registerfile(dut)

@cocotb.test()
async def test_repeated_addi_inc_x5(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")
    dut.instr_ack.value = 1
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0x00128293 # addi x5, x5, 1
    initial_pc = get_pc(dut)
    initial_rf = get_registerfile(dut)

    await ClockCycles(dut.clk, 10)

    assert initial_pc["current"] != get_pc(dut)["current"]

    rf = get_registerfile(dut)
    initial_rf_x5 = initial_rf["x5"]
    rf_x5 = rf["x5"]
    del rf["x5"]
    del initial_rf["x5"]

    assert initial_rf == rf, "Registerfile \ x5 is unchanged"
    assert rf_x5 - initial_rf_x5 == 10 - 2, "x5 changed"

@cocotb.test()
async def test_repeated_addi_negative(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    dut.instr_ack.value = 1
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0x3e800513 # addi x10, x0, 1000
    initial_pc = get_pc(dut)
    initial_rf = get_registerfile(dut)

    await RisingEdge(dut.clk)
    assert 1000 == get_registerfile(dut)["x10"]

    dut.instr_data_i.value = 0xf9c50513 # addi x10, x10, -100
    await ClockCycles(dut.clk, 15)

    assert 0 > get_registerfile(dut)["x10"]


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
