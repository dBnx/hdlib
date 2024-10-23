import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles

# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

ADDI_X0_X0_0 = 0x00000013
SW_X5_0_GP   = 0x0051a023
SW_X6_4_GP   = 0x0061a223
LW_X7_0_GP   = 0x0001a383
LW_X8_4_GP   = 0x0041a403
JAL_X0_0     = 0x0000006f
ECALL        = 0x00000073
MRET         = 0x30200073

ADDR_LUI_T0       = 0x5000_0000

LUI_T0_0X50000    = 0x500002b7
CSRRW_X0_MTVEC_T0 = 0x30529073

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


def get_registerfile(dut) -> dict[str, int]:
    # ret: dict[str,int] = {ret[f"x{i}"]: int(v) for  i, v in enumerate(dut.inst_registerfile.registerfile.value)}
    ret: dict[str, int] = {}
    for i, v in enumerate(dut.inst_registerfile.registerfile.value):
        ret[f"x{i}"] = v

    return ret


def set_registerfile(dut, values: dict[str, int]):
    for i, v in enumerate(values.values()):
        dut.inst_registerfile.registerfile[i].value = v


def get_pc(dut) -> dict[str, int]:
    return {"current": dut.pc_current.value, "next": dut.pc_next.value}


async def exec_nop(dut, count: int = 1):
    """Execute `count` nops. Also useful at the end of tests for cleaner traces"""
    dut.instr_ack.value = 1
    dut.instr_err.value = 0
    dut.instr_data_i.value = 0x00000013  # addi x0, x0, 0
    for _ in range(count):
        await RisingEdge(dut.clk)
    dut.instr_ack.value = 0


MemoryRegions: type = list[tuple[int, int]]
"""Defines R/W memory regions for a program"""
Memory: type = dict[int, int]
"""RAM mock mapping address to data"""
DefaultMemoryRegions = [(1024, 4096), ((1 << 28), (1 << 28) + 4096), ((1 << 31), (1 << 31) + 4096)]
"""Defines two regions: After INITIAL_GP and close to address zero"""

STOP_WATCHER: bool = False
"""Applies after the next rising edge"""

async def lsu_watcher(dut, memory_regions: MemoryRegions | None, memory: Memory = dict()):
    if memory_regions is None:
        await RisingEdge(dut.data_req)
        assert False, "Received data request even though nothing was specified"

    async def wait_at_least_one_cycle(dut, maximum: int = 4) -> None:
        await RisingEdge(dut.clk)
        wait_cycles = random.randrange(0, max(0, maximum))
        for _ in range(wait_cycles):
            await RisingEdge(dut.clk)

        await Timer(1, "ns")

    async def ack_and_set_data_o(dut, data: int | None = None) -> None:
        dut.data_ack.value = 1
        if data is not None:
            dut.data_data_i.value = data

        await Timer(1, "ps")
        await RisingEdge(dut.clk)
        dut.data_ack.value = 0
        await Timer(1, "ns")

        await Timer(1, "ns")
        await RisingEdge(dut.clk)
        await Timer(1, "ps")

    try:
        while True:
            while dut.data_req.value == 0:
                if STOP_WATCHER is True:
                    return memory

                await RisingEdge(dut.clk)

            await Timer(1, "ns")
            is_write = bool(dut.data_wr.value)
            addr = int(dut.data_addr.value)

            in_range: bool = False
            for start, end in memory_regions:
                if addr >= start and addr <= end:
                    in_range = True
                    break

            data = int(dut.data_data_o.value)
            is_write_str = f"W {data:=08X}" if is_write else "R"
            if in_range is False:
                await Timer(2, "ns")
                cocotb.log.error(f"Accessing memory region outside of specified regions: @ {addr:06X} {is_write_str}")
                readable_regions = " ".join(f"{start:08X}-{end:08X}" for start, end in memory_regions)
                cocotb.log.error(f"Defined regions: {readable_regions}")
                assert False, "Invalid I/O or memory access"

            cocotb.log.warning(
                f"Accessing memory region inside specified regions: @ {addr:08X} {is_write_str}"
            )  # TODO: RMME

            if is_write is True:
                # Wait some time and ack
                await wait_at_least_one_cycle(dut)
                await ack_and_set_data_o(dut)
                memory[addr] = data
            else:  # Read
                if addr not in memory.keys():
                    cocotb.log.warning(f"Reading uninitialized field @ {addr:08X}")
                    memory[addr] = 0

                data = memory[addr]
                # Wait some time
                await wait_at_least_one_cycle(dut)
                # Ack and provide
                await ack_and_set_data_o(dut, data=data)

            # readable_memory = {f"0x{addr:08X}": f"0x{v:0X}" for addr, v in memory.items()}
            # cocotb.log.error(f"{type(memory)}, {readable_memory}")
            await Timer(1, "ps")
    #except QuitMessage as _:
    #    cocotb.log.warning("Received QuitMessage")
    #    return memory
    except StopIteration:
        cocotb.log.warning("Received QuitMessage")
        cocotb.log.error(f"{type(memory)}, {memory}")
        return memory

    return memory

def _dut_instruction_in_range(dut, program: dict[int, int], memory_regions: MemoryRegions, memory_regions_are_valid_instr: bool):

    instr_fetch_addr = int(dut.pc_current.value)

    if memory_regions_are_valid_instr is False and instr_fetch_addr not in program:
        # print(f"{dut.branch_taken.value=}")
        # print(f"{dut.pc_overwrite_data.value=}")
        if dut.branch_taken.value == 1 and int(dut.pc_overwrite_data.value) in program:
            cocotb.log.info("Jump at end of valid program region.")
            # print("Jump at end of valid program region.")
            pass
        else:
            cocotb.log.info(f"{hex(instr_fetch_addr)} not in program. Quitting.")
            return False

    elif memory_regions_are_valid_instr is True:
        # Just check if it's within a valid memory region
        invalid: bool = True

        branch_taken = dut.branch_taken.value == 1
        addr = instr_fetch_addr if branch_taken is False else int(dut.pc_overwrite_data.value)

        for start, end in memory_regions:
            if addr >= start and addr < end:
                invalid = False
                break
        
        if invalid is True:
            if branch_taken is True:
                cocotb.log.info(f"Jump address @ {addr:08X} not in memory regions. Quitting.")
            else:
                cocotb.log.info(f"Current instruction @ {addr:08X} not in memory regions. Quitting.")

            readable_regions = " ".join(f"{start:08X}-{end:08X}" for start, end in memory_regions)
            cocotb.log.error(f"Defined regions: {readable_regions}")
            return False

    return True

async def run_program(
    dut,
    program: dict[int, int],
    memory_regions: MemoryRegions | None = DefaultMemoryRegions,
    memory: dict[int, int] = dict(),
    memory_regions_are_valid_instr: bool = False,
    lsu_watcher_cb = lsu_watcher,
) -> dict:
    """Provides given instruction to the HART and returns if an
    unassigned address is accessed. Crashes if first instruction is not in the program"""

    if lsu_watcher_cb is not None:
        lsu_watcher_handle = cocotb.start_soon(lsu_watcher_cb(dut, memory_regions=memory_regions, memory=memory))

    dut.instr_ack.value = 1
    dut.instr_err.value = 0

    while True:
        instr_fetch_addr = int(dut.pc_current.value)
        if _dut_instruction_in_range(dut, program, memory_regions, memory_regions_are_valid_instr) is False:
            break

        if memory_regions_are_valid_instr is True:
            dut.instr_ack.value = 1
        elif instr_fetch_addr in program:
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

    # lsu_watcher_handle.throw(QuitMessage)
    global STOP_WATCHER
    STOP_WATCHER = False
    await RisingEdge(dut.clk) # TODO: Find better solution that doesn't need it
    # lsu_watcher_handle.send(QuitMessage)
    await Timer(1, "ps")
    # sleep(0.1)
    # lsu_watcher_handle.cancel()
    # lsu_watcher_handle.close()

    if lsu_watcher_cb is not None and lsu_watcher_handle.done():
        cocotb.log.error("Result")
        return lsu_watcher_handle.result()
    
    cocotb.log.error("Mem Empty ?")

    # assert memory_region is None, "LSU mock did not finish, but expected io was provided"

    return memory


def instr_list_to_program(dut, instructions: list[str]):
    base_addr = int(dut.pc_current.value)
    return {base_addr + 4 * i: instr for i, instr in enumerate(instructions)}


@cocotb.test()
async def test_first_instruction(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    program = instr_list_to_program(
        dut,
        [
            0x00108093,  # addi x1, x1, 1
            0x00000013,  # addi x0, x0, 0
            0x00000013,  # addi x0, x0, 0
        ],
    )

    initial_x1 = get_registerfile(dut)["x1"]

    program_runner = cocotb.start_soon(run_program(dut, program))
    timeout = ClockCycles(dut.clk, 12)
    await First(program_runner, timeout)

    x1 = get_registerfile(dut)["x1"]

    n_increments = x1 - initial_x1
    assert n_increments == 1, "If not, first instruction is executed multiple times"

    # Better trace:
    await exec_nop(dut, count=2)


# @cocotb.test()
async def test_ecall_to_mret_loop(dut):
    """Checks:
    - ECALL & MRET can be executet
    - MRET jumps back to the causing instruction and not the next one
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # TODO: Remove below and fix initialization
    initial_rf = get_registerfile(dut)
    initial_rf["x3"] = 1 << 31 # Setup GP
    set_registerfile(dut, initial_rf)

    program = instr_list_to_program(
        dut,
        [
            ECALL,             # Jumpt to MTVEC via exception
            JAL_X0_0           # BARRIER
        ],
    )
    program[dut.INITIAL_MTVEC.value] = MRET # CAUSES INFINITE LOOP

    # initial_x5 = get_registerfile(dut)["x5"]
    program_runner = cocotb.start_soon(run_program(dut, program))

    timeout = ClockCycles(dut.clk, 30)
    await First(program_runner, timeout)
    await Timer(2, "ns")

    assert program_runner.done() is False, "Expected infinite loop"
    pc_at_exit = get_pc(dut)
    addr_of_jal_x0_0 = [k for k, v in program.items() if v == JAL_X0_0][0]
    assert pc_at_exit !=  addr_of_jal_x0_0, "Unreachable position reached"



@cocotb.test()
async def test_ecall_mret_loop_changed_mtvec(dut):
    """Similar to the one above, but checks if MTVEC can be varied (just before the instruction)
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # TODO: Remove below and fix initialization
    initial_rf = get_registerfile(dut)
    initial_rf["x3"] = 1 << 31 # Setup GP
    set_registerfile(dut, initial_rf)

    program = instr_list_to_program(
        dut,
        [
            LUI_T0_0X50000,    # Setup custom MTVEC (direct mode)
            CSRRW_X0_MTVEC_T0, # Update MTVEC
            ECALL,             # Jumpt to MTVEC via exception
            JAL_X0_0           # BARRIER
        ],
    )
    program[ADDR_LUI_T0] = MRET # CAUSES INFINITE LOOP

    # initial_x5 = get_registerfile(dut)["x5"]
    program_runner = cocotb.start_soon(run_program(dut, program))

    timeout = ClockCycles(dut.clk, 30)
    await First(program_runner, timeout)
    await Timer(2, "ns")

    assert program_runner.done() is False, "Expected infinite loop"

    return
    mem = program_runner.result()
    readable_memory = {f"{addr:08X}": v for addr, v in mem.items()}
    cocotb.log.error(f"{type(mem)}, {readable_memory}")
    assert len(mem.keys()) == 1, "Expect one initialized memory location"
    assert 0x123 == mem[1 << 31]

    result_x6 = get_registerfile(dut)["x6"]
    assert 0x123 == result_x6, "Read-from memory value @GP is 0x123 (291)"

    await exec_nop(dut, count=2)

# TODO: Update MTVEC and test it

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

    test_module = os.path.basename(__file__).replace(".py", "")
    runner.test(hdl_toplevel=hdl_toplevel, test_module=f"{test_module},", waves=True, extra_env={"WAVES": "1"})


if __name__ == "__main__":
    test_runner()
