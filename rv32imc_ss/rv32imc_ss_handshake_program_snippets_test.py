import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First, ClockCycles

# from cocotb.handle import Freeze, Release
from dataclasses import dataclass
import random

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
DefaultMemoryRegions = [(1024, 4096), ((1 << 31), (1 << 31) + 4096)]
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


async def run_program(
    dut,
    program: dict[int, int],
    memory_regions: MemoryRegions | None = DefaultMemoryRegions,
    memory: dict[int, int] = dict(),
) -> dict:
    """Provides given instruction to the HART and returns if an
    unassigned address is accessed. Crashes if first instruction is not in the program"""

    lsu_watcher_handle = cocotb.start_soon(lsu_watcher(dut, memory_regions=memory_regions, memory=memory))

    dut.instr_ack.value = 1
    dut.instr_err.value = 0

    while True:
        instr_fetch_addr = int(dut.pc_current.value)
        if instr_fetch_addr not in program:
            # print(f"{dut.branch_taken.value=}")
            # print(f"{dut.pc_overwrite_data.value=}")
            if dut.branch_taken.value == 1 and int(dut.pc_overwrite_data.value) in program:
                cocotb.log.info("Jump at end of valid program region.")
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

    # lsu_watcher_handle.throw(QuitMessage)
    global STOP_WATCHER
    STOP_WATCHER = False
    await RisingEdge(dut.clk) # TODO: Find better solution that doesn't need it
    # lsu_watcher_handle.send(QuitMessage)
    await Timer(1, "ps")
    # sleep(0.1)
    # lsu_watcher_handle.cancel()
    # lsu_watcher_handle.close()

    if lsu_watcher_handle.done():
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


@cocotb.test()
async def test_jal_loop(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    program = instr_list_to_program(
        dut,
        [
            0x00000013,  # addi x0, x0, 0
            0x00108093,  # addi x1, x1, 1
            0x00108093,  # addi x1, x1, 1
            0xFF9FF06F,  # jal  x0, -8
            # 0xFFDFF06F, # jal  x0, -4
        ],
    )

    initial_x1 = get_registerfile(dut)["x1"]
    program_runner = cocotb.start_soon(run_program(dut, program))
    cycles = 22
    timeout = ClockCycles(dut.clk, cycles)
    await First(program_runner, timeout)

    x1 = get_registerfile(dut)["x1"]
    n_increments = x1 - initial_x1
    exp_incs = (cycles - 1) // 3 * 2
    cocotb.log.info(f"Number of increments in loop: {n_increments}, expected {exp_incs}")
    assert n_increments == exp_incs


    # Better trace:
    await exec_nop(dut, count=2)

SW_X5_0_GP = 0x0051A023
ADDI_X5_X0_0x123 = 0x12300293
LW_X6_0_GP = 0x0001A303

@cocotb.test()
async def test_store_load_interleaved_nop(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # TODO: Remove below and fix initialization
    initial_rf = get_registerfile(dut)
    initial_rf["x3"] = 1 << 31 # Setup GP
    set_registerfile(dut, initial_rf)

    program = instr_list_to_program(
        dut,
        [
            ADDI_X5_X0_0x123,
            SW_X5_0_GP,
            ADDI_X0_X0_0, # Interleaved NOP
            LW_X6_0_GP,
            ADDI_X0_X0_0, # TODO: Remove me
        ],
    )

    # initial_x5 = get_registerfile(dut)["x5"]
    program_runner = cocotb.start_soon(run_program(dut, program))

    timeout = ClockCycles(dut.clk, 30)
    await First(program_runner, timeout)
    await Timer(2, "ns")

    assert program_runner.done() is True, "Timeout before program could finish"

    mem = program_runner.result()
    readable_memory = {f"{addr:08X}": v for addr, v in mem.items()}
    cocotb.log.error(f"{type(mem)}, {readable_memory}")
    assert len(mem.keys()) == 1, "Expect one initialized memory location"
    assert 0x123 == mem[1 << 31]

    result_x6 = get_registerfile(dut)["x6"]
    assert 0x123 == result_x6, "Read-from memory value @GP is 0x123 (291)"

    await exec_nop(dut, count=2)

@cocotb.test()
async def test_store_load(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # TODO: Remove below and fix initialization
    initial_rf = get_registerfile(dut)
    initial_rf["x3"] = 1 << 31
    set_registerfile(dut, initial_rf)

    program = instr_list_to_program(
        dut,
        [
            ADDI_X5_X0_0x123,
            SW_X5_0_GP,
            LW_X6_0_GP,
            ADDI_X0_X0_0, # TODO: Remove me
        ],
    )

    # initial_x5 = get_registerfile(dut)["x5"]
    program_runner = cocotb.start_soon(run_program(dut, program))

    timeout = ClockCycles(dut.clk, 30)
    await First(program_runner, timeout)
    await Timer(2, "ns")

    assert program_runner.done() is True, "Timeout before program could finish"

    mem = program_runner.result()
    readable_memory = {f"{addr:08X}": v for addr, v in mem.items()}
    cocotb.log.error(f"{type(mem)}, {readable_memory}")
    assert len(mem.keys()) == 1, "Expect one initialized memory location"
    assert 0x123 == mem[1 << 31]

    result_x6 = get_registerfile(dut)["x6"]
    assert 0x123 == result_x6, "Read-from memory value @GP is 0x123 (291)"

    await exec_nop(dut, count=2)

@cocotb.test()
async def test_write_write_read_read(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # TODO: Remove below and fix initialization
    initial_rf = get_registerfile(dut)
    initial_rf["x3"] = 1 << 31
    initial_rf["x5"] = 0xC0FE_C0CA
    initial_rf["x6"] = 0xDEAD_F00D
    set_registerfile(dut, initial_rf)

    program = instr_list_to_program(
        dut,
        [
            SW_X5_0_GP,
            SW_X6_1_GP,
            LW_X7_0_GP,
            LW_X8_1_GP,
            ADDI_X0_X0_0, # TODO: Remove me
        ],
    )

    program_runner = cocotb.start_soon(run_program(dut, program))

    timeout = ClockCycles(dut.clk, 30)
    await First(program_runner, timeout)
    await Timer(2, "ns")

    assert program_runner.done() is True, "Timeout before program could finish"

    mem = program_runner.result()
    readable_memory = {f"0x{addr:08X}": f"0x{v:08X}" for addr, v in mem.items()}
    cocotb.log.error(f"{type(mem)}, {readable_memory}")
    assert len(mem.keys()) == 2, "Expect two initialized memory location"
    assert 0xC0FE_C0CA == mem[(1 << 31) + 0]
    assert 0xDEAD_F00D == mem[(1 << 31) + 4]

    regfile = get_registerfile(dut)
    result_x7 = regfile["x7"]
    result_x8 = regfile["x8"]
    assert 0xC0FE_C0CA == result_x7, "Read-from memory value @GP is 0xC0FE_C0CA"
    assert 0xDEAD_F00D == result_x8, "Read-from memory value @GP is 0xDEAD_F00D"

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
