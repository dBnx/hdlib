
module rv32imc_ss_handshake_w_rom #(
    parameter logic [31:0] INITIAL_PC = 32'h10000000,
    parameter logic [31:0] INITIAL_GP = 32'h80000000,
    parameter logic [31:0] INITIAL_SP = 32'h7FFFFFF0,
    parameter int RAM_DEPTH32 =  512, // Should not be more than 512 with default mapping (2kiB)
    parameter int ROM_DEPTH32 =  512, // (2kiB)
    // parameter string ROM_FILE = "kernel.portecho.hex"
    // parameter string ROM_FILE = "kernel.test.irom.iram.mmr.mem"
    parameter string ROM_FILE = "/home/dave/Sync/Projects/github/hdlib/rv32imc_ss/kernel.test.irom.iram.mmr.mem"
) (
    input  logic clk,
    input  logic reset,

    // Used outside of internal ROM
    output logic        instr_req,
    input  logic        instr_ack,
    input  logic        instr_err,
    output logic [31:0] instr_addr,
    input  logic [31:0] instr_data_i,

    output logic        data_req,
    output logic        data_wr,
    input  logic        data_ack,
    input  logic        data_err,
    output logic [31:0] data_addr,
    output logic [ 3:0] data_be,
    output logic [31:0] data_data_o,
    input  logic [31:0] data_data_i,

    // TODO: GPIO
    output logic [31:0] gpio_o[8],
    input  logic [31:0] gpio_i[8]
);
  // TODO: Ensure rest is also connected
  assign data_wr = data_wr_int;

  localparam int MMR_DEPTH32 = 512;

  // FIXME: Bug - DEPTH is 32 but other addresses are byte aligned
  localparam int BASE_START_ROM = INITIAL_PC; // 32'h1000_0000;
  localparam int BASE_END_ROM   = INITIAL_PC + (ROM_DEPTH32 << 2);
  localparam int BASE_START_RAM = INITIAL_GP - (RAM_DEPTH32 << 2);
  localparam int BASE_END_RAM   = INITIAL_GP;
  localparam int BASE_START_MMR = 1024; // 256 Registers
  localparam int BASE_END_MMR   = 2048;

  localparam int RomW = $clog2(ROM_DEPTH32);
  localparam int MmrW = $clog2(MMR_DEPTH32);
  localparam int RamW = $clog2(RAM_DEPTH32);

  // Helper addresses, as we don't care about anything under a 32B alignment (width of BE)
  bit [29:0] instr_addr32_int;
  bit [29:0] data_addr32_int;
  assign instr_addr32_int = instr_addr_int[31:2];
  assign data_addr32_int = data_addr_int[31:2];

  // Is peripheral slected by partial address decoding? If not, then we assume it's external.
  logic enable_ipath_rom;
  logic enable_dpath_rom;
  logic enable_dpath_mmr;
  logic enable_dpath_ram;

  assign enable_ipath_rom = instr_addr_int >= BASE_START_ROM && instr_addr_int < BASE_END_ROM;
  assign enable_dpath_rom = data_addr_int  >= BASE_START_ROM && data_addr_int  < BASE_END_ROM;
  assign enable_dpath_mmr = data_addr_int  >= BASE_START_MMR && data_addr_int  < BASE_END_MMR;
  assign enable_dpath_ram = data_addr_int  >= BASE_START_RAM && data_addr_int  < BASE_END_RAM;

  logic enable_dpath_internal;
  assign enable_dpath_internal = enable_dpath_rom || enable_dpath_mmr || enable_dpath_ram;

  bit [RomW-1:0] rom_ipath_addr;
  bit [RomW-1:0] rom_dpath_addr;
  bit [RamW-1:0] ram_dpath_addr;
  bit [MmrW-1:0] mmr_dpath_addr;
  assign rom_ipath_addr = enable_ipath_rom ? instr_addr32_int[RomW-1:0] : 0;
  assign rom_dpath_addr = enable_dpath_rom ? data_addr32_int [RomW-1:0] : 0;
  assign ram_dpath_addr = enable_dpath_ram ? data_addr32_int [RamW-1:0] : 0;
  assign mmr_dpath_addr = enable_dpath_mmr ? data_addr32_int [MmrW-1:0] : 0;

  logic        instr_req_int;
  logic        instr_ack_int;
  logic        instr_err_int;
  logic [31:0] instr_addr_int;
  logic [31:0] instr_data_i_int;

  logic        data_req_int;
  logic        data_wr_int;
  logic        data_ack_int;
  logic        data_err_int;
  logic [31:0] data_addr_int;
  logic [31:0] data_data_o_int;
  logic [31:0] data_data_i_int;

  // iROM --------------------------------------------------------------------
  // iROM I Path -------------------------------------------------------------

  logic rom_ack; // for data path

  bit [31:0] rom[ROM_DEPTH32];
  initial begin
    $readmemh(ROM_FILE, rom);
  end

  always_comb begin
    instr_data_i_int = enable_ipath_rom ? rom[rom_ipath_addr] : instr_data_i;
    instr_ack_int    = enable_ipath_rom ? 1 : instr_ack;
    instr_err_int    = enable_ipath_rom ? 0 : instr_err;
  end

  // iROM D Path -------------------------------------------------------------

  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      rom_ack <= 0;
    end else begin
      if(data_req_int && enable_dpath_rom) begin
        rom_ack <= 1;
      end else begin
        rom_ack <= 0;
      end
    end
  end

  // iRAM --------------------------------------------------------------------
  // TODO: Change declaration of location + size to be more intuitive

  // TODO: Byte enable
  bit [31:0] ram[RAM_DEPTH32];
  logic ram_ack;

  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      ram_ack <= 0;
    end else begin
      if(data_req_int && enable_dpath_ram) begin
        // Acknowledge read & writes
        ram_ack <= 1;

        if(data_wr_int) begin
          ram[ram_dpath_addr] <= data_data_o;
        end
      end else begin
        ram_ack <= 0;
      end
    end
  end

  // MMR ---------------------------------------------------------------------
  logic [31:0] mmr_data_o;
  logic        mmr_ack;

  // GPIOs
  logic [31:0] gpio[8];
  logic        gpio_enable;
  logic [ 2:0] gpio_addr;

  // MTIME
  // TODO: & timecmp

  // TODO: Byte enable for RAM & GPIO writes

  assign gpio_enable = enable_dpath_mmr && mmr_dpath_addr[MmrW-1:3] == 0;
  assign gpio_addr = mmr_dpath_addr[2:0];

  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      mmr_ack <= 0;
    end else begin
      if(data_req_int && enable_dpath_mmr) begin
        mmr_ack <= 1;

        if(gpio_enable) begin
          if(data_wr_int) begin
            // GPIO W
            gpio[gpio_addr] <= data_data_o;
          end else begin
            // GPIO R
            mmr_data_o <= gpio[gpio_addr];
          end
        end else begin
          // Non_GPIO
          mmr_data_o <= 0;
        end
      end else begin
        mmr_ack <= 0;
        mmr_data_o <= 0;
      end
    end
  end

  // Mux ---------------------------------------------------------------------
  always_comb begin
    if(enable_dpath_internal) begin
      // Internal peripherals
      case({enable_dpath_rom, enable_dpath_ram, enable_dpath_mmr})
        3'b100: begin
          data_ack_int = rom_ack;
          data_data_i_int = rom[rom_dpath_addr];
        end
        3'b010: begin
          data_ack_int = ram_ack;
          data_data_i_int = ram[ram_dpath_addr];
        end
        3'b001: begin
          data_ack_int = mmr_ack;
          data_data_i_int = mmr_data_o;
        end
        default: begin
          data_ack_int = 0;
          data_data_i_int = 0;
        end
      endcase
    end else begin
      // External interface
      data_ack_int = data_ack;
      data_data_i_int = data_data_i;
    end
  end

  // Hart --------------------------------------------------------------------
  rv32imc_ss_handshake #(
      .INITIAL_GP(INITIAL_GP),
      .INITIAL_SP(INITIAL_SP)
  ) inst_hart (
      .clk  (clk),
      .reset(reset),

      .instr_req(instr_req_int),
      .instr_ack(instr_ack_int),
      .instr_err(instr_err_int),
      .instr_addr(instr_addr_int),
      .instr_data_i(instr_data_i_int),

      .data_req(data_req_int),
      .data_wr(data_wr_int),
      .data_ack(data_ack_int),
      .data_err(data_err_int),
      .data_addr(data_addr_int),
      .data_be(data_be),
      .data_data_o(data_data_o_int),
      .data_data_i(data_data_i_int)
  );

endmodule
