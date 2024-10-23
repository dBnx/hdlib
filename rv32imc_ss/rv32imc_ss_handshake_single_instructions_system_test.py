import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles
# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import enum

class Exception(enum.Enum):
    ILLEGAL_INSTR = 0x02
    ECALL_FROM_M = 0x0B


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
        "current": dut.pc_current.value,
        "next"   : dut.pc_next.value
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

# @cocotb.test()
async def test_todo(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    instr = 0xfffff2b7 # LUI x5, -1
    await exec_instr(dut, instr)
    assert (-1 << 12) & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    instr = 0xffc182b7 # LUI x5, -1000
    await exec_instr(dut, instr)
    assert (-1000 << 12) & 0xFFFF_FFFF == get_registerfile(dut)["x5"]

    await exec_nop(dut)

# @cocotb.test()
async def test_foo_todo(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await Timer(1, "ps")

    initial_pc = get_pc(dut)["current"]
    instr = 0x00001297 # AUIPC x5, 1
    await exec_instr(dut, instr)

    assert initial_pc + (1 << 12) == get_registerfile(dut)["x5"]

    await exec_nop(dut)

@cocotb.test()
async def test_ecall_to_double_fault(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)
    await Timer(1, "ps")

    assert dut.inst_csrs.in_context_handler.value == 0, "After reset assume normal context"
    assert dut.inst_csrs.double_fault.value == 0, "After reset assume normal context"
    await exec_nop(dut)
    assert dut.inst_csrs.in_context_handler.value == 0
    assert dut.inst_csrs.double_fault.value == 0

    # Assume we had interrupts enabled
    dut.inst_csrs.csr_mstatus_mie.value  = 1; # Set   MIE 
    dut.inst_csrs.csr_mstatus_mpie.value = 0; # Reset MPIE 

    # Issue ECALL and check context & PC
    pc_initial = get_pc(dut)["current"]
    instr = 0x00000073 # ECALL
    await exec_instr(dut, instr)
    await Timer(5, "ps")

    assert dut.inst_csrs.in_context_handler.value == 1, "Now in a trap handler"
    assert dut.inst_csrs.double_fault.value == 0

    pc_post_ecall = get_pc(dut)["current"]
    mtvec = dut.INITIAL_MTVEC.value & ~0b11
    assert mtvec == pc_post_ecall, "Jumpt target iis the vector address"

    assert pc_initial == dut.inst_csrs.csr_mepc.value, "Old PC is stored in MEPC"

    assert dut.inst_csrs.csr_mstatus_mie.value  == 0, "MIE should now be cleared"
    assert dut.inst_csrs.csr_mstatus_mpie.value == 1, "MPIE should be the old MIE (1)"

    # Check that after a NOP it's still in a context handler 
    await exec_nop(dut)
    assert dut.inst_csrs.in_context_handler.value == 1
    assert dut.inst_csrs.double_fault.value == 0

    # Issue another ECALL from within the trap handler -> double fault
    instr = 0x00000073 # ECALL
    await exec_instr(dut, instr)
    await Timer(5, "ps")

    assert dut.inst_csrs.in_context_handler.value == 1
    assert dut.inst_csrs.double_fault.value == 1
    assert dut.instr_req.value == 0

    # Double fault persists and no new instructions are issued
    pc_double_fault = get_pc(dut)["current"]
    for _ in range(5):
        await RisingEdge(dut.clk)
        assert dut.instr_req.value == 0
        assert dut.inst_csrs.double_fault.value == 1
        assert pc_double_fault == get_pc(dut)["current"]

    await Timer(1, "ps")


@cocotb.test()
async def test_ecall_mret(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await Timer(1, "ps")

    pc_start = get_pc(dut)["current"]

    # Assume we had previously interrupts enabled
    dut.inst_csrs.csr_mstatus_mie.value  = 1; # Set   MIE 
    dut.inst_csrs.csr_mstatus_mpie.value = 0; # Reset MPIE 

    # Get into a context handler
    instr = 0x00000073 # ECALL
    await exec_instr(dut, instr)
    await Timer(5, "ps")
    assert dut.inst_csrs.csr_mcause.value == Exception.ECALL_FROM_M.value, "MCAUSE should be 0x0B (ECALL from M)"
    assert dut.inst_csrs.csr_mtval.value  == 0x00, "MTVAL must be zero"
    assert dut.inst_csrs.csr_mstatus_mie.value  == 0, "MIE should now be cleared"
    assert dut.inst_csrs.csr_mstatus_mpie.value == 1, "MPIE should be the old MIE (1)"

    # Directly return without updating MEPC
    instr = 0x30200073 # MRET
    await exec_instr(dut, instr)
    await Timer(1, "ns")
    assert dut.inst_csrs.csr_mstatus_mie.value == 1, "MIE should now be restored"

    pc_after_return = get_pc(dut)["current"]
    assert pc_start == pc_after_return

    await exec_nop(dut)

@cocotb.test()
async def test_mret_not_in_trap_handler(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await Timer(1, "ps")

    pc_start = get_pc(dut)["current"]

    # Assume we had previously interrupts enabled
    dut.inst_csrs.csr_mstatus_mie.value  = 1; # Set   MIE 
    dut.inst_csrs.csr_mstatus_mpie.value = 0; # Reset MPIE 

    # Call MRET without being in an trap handler context
    instr = 0x30200073 # MRET -> 
    await exec_instr(dut, instr)
    await Timer(1, "ns")
    assert dut.inst_csrs.csr_mstatus_mie.value == 0, "MIE should be reset"
    assert dut.inst_csrs.csr_mstatus_mpie.value == 1, "MPIE should be the old MIE (1)"
    assert dut.inst_csrs.csr_mcause.value == Exception.ILLEGAL_INSTR.value, "MCAUSE should be 0x0B (Invalid)"
    assert dut.inst_csrs.csr_mtval.value == instr, "MTVAL should have the illegal instruction"

    # pc_after_return = get_pc(dut)["current"]
    # assert pc_start == pc_after_return

    await exec_nop(dut)

# TODO: Missing "system" instructions 
# FENCE
# FENCE.TSO
# PAUSE
# ECALL
# BREAK
#
# CSR

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
        project_path / "rv32_mod_stallington.sv",
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
        waves=True,
    )

    test_module = os.path.basename(__file__).replace(".py","")
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},",
                waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
