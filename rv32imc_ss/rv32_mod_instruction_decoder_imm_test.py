import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

# Instruction Type: {is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j}
ASM = {
    "ADDI x0, x0, 0": (0x00000013, 0b10000, 0), # I Type
    "JAL x0, -2": (0xfffff06f, 0b00011, 0xFFFF_FFFE), # 
    "JAL x0, -4": (0xffdff06f, 0b00011, 0xFFFF_FFFC), # 
    "JAL x0,  2": (0x0020006f, 0b00011, 0x0000_0002), # 
    "JAL x0,  4": (0x0020006f, 0b00011, 0x0000_0004), # 
}

@cocotb.test()
async def test_null(dut) -> None:
    dut.instruction.value = 0
    dut.instruction_format.value = 0
    await Timer(1, "ps")
    assert dut.immediate.value == 0, "No input should stay 0 to reduce transitions"

@cocotb.test()
async def test_examples(dut) -> None:
    for instr_asm, (instr_bin, instr_type, ref_imm) in ASM.items(): 
        dut.instruction.value = instr_bin
        dut.instruction_format.value = instr_type
        await Timer(1, "ps")
        assert dut.immediate.value == ref_imm, f"{instr_asm}"

    # module rv32_mod_instruction_decoder_imm (
    #     input [31:0] instruction,
    #     input [ 5:0] instruction_format,
    #     output [31:0] immediate
    # );

    # await reset_dut(dut)

    # timing_check_h = cocotb.start_soon(vga_timing_checker_hsync(dut))
    # timing_check_v = cocotb.start_soon(vga_timing_checker_vsync(dut))

    # await First(test_time, timing_check_h, timing_check_v)


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_instruction_decoder_imm"
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
