import cocotb
from cocotb.clock import Clock

CLK: int = 50_000_000
CLK_CYCLE_NS: int = int(1. / CLK)
BAUD: int = 115200


def start_clk(clk) -> None:
    cocotb.start_soon(Clock(clk, CLK_CYCLE_NS, units="ns").start())
