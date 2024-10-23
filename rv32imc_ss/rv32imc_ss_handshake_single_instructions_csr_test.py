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
    ret: dict[str,intjkk] = {}
    for i, v in enumerate(dut.inst_registerfile.registerfile.value):
        ret[f"x{i}"] = v
    return ret

def set_registerfile(dut, values: dict[str, int]):
    for i, v in enumerate(values.values()):
        dut.inst_registerfile.registerfile[i].value = v

def get_pc(dut) -> dict[str, int]:
    return {
        "current":dut.pc_current.value,
        "next"   :dut.pc_next.value
    }

async def exec_instr(dut, instruction: int, count: int = 1):
    """Execute `count` nops. Also useful at the end of tests for cleaner traces"""
    dut.instr_ack.value = 1
    dut.instr_err.value = 0
    dut.instr_data_i.value = instruction
    for _ in range(count):
        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")
    dut.instr_ack.value = 0

async def exec_nop(dut, count: int = 1):
    nop = 0x00000013 # addi x0, x0, 0
    await exec_instr(dut, instruction=nop, count=count)

@cocotb.test()
async def test_csrrw_mscratch(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    rf = get_registerfile(dut)
    rf["x5"] = 0x0000_1234 # Dst
    rf["x6"] = 0xCAFE_BABE # Src
    set_registerfile(dut, rf)

    dut.inst_csrs.csr_mscratch.value = 0xDEAD_BEEF

    # Atomic read & write
    await Timer(1, "ps")
    instr = 0x340312f3 # csrrw t0, mscratch, t1
    await exec_instr(dut, instr)
    
    await Timer(1, "ns")
    rf = get_registerfile(dut)
    assert 0xDEAD_BEEF == rf["x5"]
    assert 0xCAFE_BABE == rf["x6"] # Unchanged
    assert 0xCAFE_BABE == dut.inst_csrs.csr_mscratch.value

    # Only read
    rf = get_registerfile(dut)
    rf["x5"] = 0x0000_0001 # Dst: Reset to check
    rf["x6"] = 0x0000_0002 # Src
    set_registerfile(dut, rf)

    await Timer(1, "ps")
    instr = 0x340012f3 # csrrw t0, mscratch, zero
    await exec_instr(dut, instr)
    
    await Timer(1, "ns")
    rf = get_registerfile(dut)
    assert 0xCAFE_BABE == rf["x5"]
    assert 0x0000_0002 == rf["x6"] # Unchanged
    assert 0xCAFE_BABE == dut.inst_csrs.csr_mscratch.value # Unchanged

    # Only write
    rf = get_registerfile(dut)
    rf["x5"] = 0x0000_DEAD # Dst: Reset to check
    rf["x6"] = 0x1234_5678 # Src
    set_registerfile(dut, rf)

    await Timer(1, "ps")
    instr = 0x34031073 # csrrw zero, mscratch, t1
    await exec_instr(dut, instr)
    
    await Timer(1, "ns")
    rf = get_registerfile(dut)
    assert 0x0000_DEAD == rf["x5"]
    assert 0x1234_5678 == rf["x6"] # Unchanged
    assert 0x1234_5678 == dut.inst_csrs.csr_mscratch.value

    await exec_nop(dut)

@cocotb.test()
async def test_csrrw_mcycle(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    rf = get_registerfile(dut)
    rf["x5"] = 0
    set_registerfile(dut, rf)

    # Read only & let it increase
    await Timer(1, "ps")
    instr = 0xb00012f3 # csrrw t0, mcycle, zero
    await exec_instr(dut, instr)
    assert 0 == get_registerfile(dut)["x5"]
    await exec_instr(dut, instr)
    assert 1 == get_registerfile(dut)["x5"]
    await exec_instr(dut, instr)
    assert 2 == get_registerfile(dut)["x5"]
    await exec_instr(dut, instr)
    assert 3 == get_registerfile(dut)["x5"]

    # TODO:
    # - Write
    # - Overflow & mcycleh

    await exec_nop(dut)


# TODO: Missing instructions 
# CSRS
# CSRC
# CSRWI
# CSRSI
# CSRCI
# .. and more complex registers

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

    test_module = os.path.basename(__file__).replace(".py","")
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
