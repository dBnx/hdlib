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

async def exec_nop(dut, count: int = 1):
    """Execute `count` nops. Also useful at the end of tests for cleaner traces"""
    dut.instr_ack.value = 1
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0x00000013 # addi x0, x0, 0
    for _ in range(count):
        await RisingEdge(dut.clk)
    dut.instr_ack.value = 0

async def run_program(dut, program: dict[int, int], memory: dict[int, int] = dict()) -> dict:
    """Provides given instruction to the HART and returns if an
    unassigned address is accessed. Crashes if first instruction is not in the program"""
    # TODO: Add LSU Watcher

    dut.instr_ack.value = 1
    dut.instr_err.value = 0

    while True:
        instr_fetch_addr = int(dut.pc_current.value)
        if instr_fetch_addr not in program:
            # print(f"{dut.branch_taken.value=}")
            # print(f"{dut.pc_overwrite_data.value=}")
            if dut.branch_taken.value == 1 and int(dut.pc_overwrite_data.value) in program:
                # print("Jump at end of valid program region.")
                pass
            else:
                #             await Timer(1, "ps")print(f"{hex(instr_fetch_addr)} not in program. Quitting.")
                break

        if instr_fetch_addr in program:
            dut.instr_ack.value = 1
            dut.instr_data_i.value = program[instr_fetch_addr]
            # print(f"Prog @ {hex(instr_fetch_addr)}: {hex(program[instr_fetch_addr])}")
        else:
            dut.instr_ack.value = 0

        # Time needed for combinatorics to work, otherwise _some_ things are delayed _by the simulation_ until the
        # next clock edge ..
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps") 

    dut.instr_ack.value = 0

    return dict()

@cocotb.test()
async def test_first_instruction(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    base_addr = int(dut.pc_current.value)
    program = {
        base_addr + 0x00: 0x00108093, # addi x1, x1, 1
        base_addr + 0x04: 0x00000013, # addi x0, x0, 0
        base_addr + 0x08: 0x00000013, # addi x0, x0, 0
    }

    initial_x1 = get_registerfile(dut)["x1"]

    program_runner = cocotb.start_soon(run_program(dut, program))
    timeout = ClockCycles(dut.clk, 12)
    await First(program_runner, timeout)

    x1 = get_registerfile(dut)["x1"]

    n_increments = x1 - initial_x1
    assert n_increments == 1, "If not, first instruction is executed multiple times"

    # Better trace:
    await exec_nop(dut, count=2)

@cocotb.test()
async def test_jal_loop(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    base_addr = int(dut.pc_current.value)
    program = {
        base_addr + 0x00: 0x00000013, # addi x0, x0, 0
        base_addr + 0x04: 0x00108093, # addi x1, x1, 1
        base_addr + 0x08: 0x00108093, # addi x1, x1, 1
        base_addr + 0x0C: 0xFF9FF06F, # jal  x0, -8
        # base_addr + 0x0C: 0xFFDFF06F, # jal  x0, -4 
    }

    #for k, v in program.items():
    #    print(f"{hex(k):10}: {hex(v):10}")

    initial_x1 = get_registerfile(dut)["x1"]
    program_runner = cocotb.start_soon(run_program(dut, program))
    timeout = ClockCycles(dut.clk, 22)
    await First(program_runner, timeout)

    x1 = get_registerfile(dut)["x1"]
    n_increments = x1 - initial_x1
    assert n_increments >= 10

    # Better trace:
    await exec_nop(dut, count=2)

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

    test_module = os.path.basename(__file__).replace(".py","")
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
