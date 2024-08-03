import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass

IFORMAT: dict[str, int] = {
    "R": 0b100000,
    "I": 0b010000,
    "S": 0b001000,
    "B": 0b001100,
    "U": 0b000010,
    "J": 0b000011,
}

# module rv32_mod_instruction_decoder_func (
#     input [5:0] instruction_format,  // or opcode?
#     input [5:0] func,
#     input [0:0] is_mem_or_io,
# 
#     output logic             rf_write0_enable,
#     output logic             alu_op0_use_pc,
#     output logic             alu_op1_use_imm,
#     output logic       [4:0] alu_func,
#     output logic       [3:0] ram_req,
#     output logic             ram_wr,
#     output wb_source_t       wb_source,
# 
#     output br_condition_t br_cond,
#     output logic          br_is_cond,
#     output logic          br_jmp
# );

# @cocotb.test()
async def test_foo(dut) -> None:

    dut.instruction_format.value = IFORMAT["R"]
    await Timer(1, "ps")


    # await reset_dut(dut)

    # timing_check_h = cocotb.start_soon(vga_timing_checker_hsync(dut))
    # timing_check_v = cocotb.start_soon(vga_timing_checker_vsync(dut))

    # await First(test_time, timing_check_h, timing_check_v)


def test_runner():
    import os
    from pathlib import Path
    from cocotb.runner import get_runner

    hdl_toplevel = "rv32_mod_instruction_decoder_func"
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
