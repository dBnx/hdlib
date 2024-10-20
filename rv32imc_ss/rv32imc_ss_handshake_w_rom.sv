
module rv32imc_ss_handshake_w_rom #(
    parameter bit [31:0] INITIAL_PC = 32'h10000000,
    parameter bit [31:0] INITIAL_GP = 32'h80000000,
    parameter bit [31:0] INITIAL_SP = 32'h7FFFFFF0,
    parameter int        RAM_DEPTH32 = 1024,  // Should not be more than 512 with default mapping (2kiB)
    parameter int        ROM_DEPTH32 = 1024,  // (2kiB)
    // parameter string ROM_FILE = "kernel.portecho.hex"
    // parameter string ROM_FILE = "kernel.test.irom.iram.mmr.mem"
    parameter string ROM_FILE = "/home/dave/Sync/Projects/github/hdlib/rv32imc_ss/kernel.test.irom.iram.mmr.mem"
) (
    input logic clk,
    input logic reset,

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
    output logic [31:0] gpio_o[GpioN],
    input logic [31:0] gpio_i[GpioN],
    output logic [GpioN-1:0] gpio_o_update,
    output logic [GpioN-1:0] gpio_i_update
);
  // TODO: Ensure rest is also connected
  assign data_wr = data_wr_int;

  localparam int MMR_DEPTH32 = 512;

  // FIXME: Bug - DEPTH is 32 but other addresses are byte aligned
  localparam int BASE_START_ROM = INITIAL_PC;  // 32'h1000_0000;
  localparam int BASE_END_ROM = INITIAL_PC + (ROM_DEPTH32 << 2);
  localparam int BASE_START_RAM = INITIAL_GP - (RAM_DEPTH32 << 2);
  localparam int BASE_END_RAM = INITIAL_GP;
  localparam int BASE_START_MMR = 1024;  // 256 Registers
  localparam int BASE_END_MMR = 2048;

  localparam int MmrOffsetGpio = 'h030;  // Offset to BASE_START_MMR for the GPIO registers

  localparam int RomW = $clog2(ROM_DEPTH32);
  localparam int RamW = $clog2(RAM_DEPTH32);
  localparam int MmrW = $clog2(MMR_DEPTH32);

  localparam int GpioN = 8;
  localparam int GpioW = $clog2(GpioN);

  // Helper addresses, as we don't care about anything under a 32B alignment (width of BE)
  bit [29:0] instr_addr32_int;
  bit [29:0] data_addr32_int;
  assign instr_addr32_int = instr_addr_int[31:2];
  assign data_addr32_int  = data_addr_int[31:2];

  // Is peripheral slected by partial address decoding? If not, then we assume it's external.
  logic enable_ipath_rom;
  logic enable_dpath_rom;
  logic enable_ipath_ram;
  logic enable_dpath_ram;
  logic enable_dpath_mmr;

  assign enable_ipath_rom = instr_addr_int >= BASE_START_ROM && instr_addr_int < BASE_END_ROM;
  assign enable_dpath_rom = data_addr_int  >= BASE_START_ROM && data_addr_int  < BASE_END_ROM;
  assign enable_ipath_ram = instr_addr_int >= BASE_START_RAM && instr_addr_int < BASE_END_RAM;
  assign enable_dpath_ram = data_addr_int  >= BASE_START_RAM && data_addr_int  < BASE_END_RAM;
  assign enable_dpath_mmr = data_addr_int  >= BASE_START_MMR && data_addr_int  < BASE_END_MMR;

  logic enable_dpath_internal;
  assign enable_dpath_internal = enable_dpath_rom || enable_dpath_mmr || enable_dpath_ram;

  bit [RomW-1:0] rom_ipath_addr;
  bit [RomW-1:0] rom_dpath_addr;
  bit [RamW-1:0] ram_ipath_addr;
  bit [RamW-1:0] ram_dpath_addr;
  bit [MmrW-1:0] mmr_dpath_addr;
  assign rom_ipath_addr = enable_ipath_rom ? instr_addr32_int[RomW-1:0] : 0;
  assign rom_dpath_addr = enable_dpath_rom ? data_addr32_int [RomW-1:0] : 0;
  assign ram_ipath_addr = enable_ipath_ram ? instr_addr32_int[RamW-1:0] : 0;
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
  // TODO: Remove this:
  logic        rom_ack;  // for data path

  bit   [31:0] rom [ROM_DEPTH32] /* synthesis ramstyle = "no_rw_check, M9K" */;
  initial begin
    $readmemh(ROM_FILE, rom);
  end

  // iROM I Path -------------------------------------------------------------
  bit instr_ack_rom = 1;
  bit [31:0] instr_data_i_int_rom;


  // iROM D Path -------------------------------------------------------------

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      rom_ack <= 0;
    end else begin
      if (data_req_int && enable_dpath_rom) begin
        rom_ack <= 1;
      end else begin
        rom_ack <= 0;
      end
    end
  end

  // iRAM --------------------------------------------------------------------
  // TODO: Change declaration of location + size to be more intuitive
  bit [31:0] data_data_i_int_ram;
  bit        ram_ack;
  bit [31:0] instr_data_i_int_ram;
  bit        instr_ack_ram;

  ram_dp_handshake #(
      .ADDR_WIDTH($clog2(RAM_DEPTH32)),
      .BYTES(4)
  ) inst_ram (
      .clk  (clk),
      .clken(1'b1),

      // DPath
      .p0_we   (data_req_int && enable_dpath_ram && data_wr_int),
      .p0_re   (data_req_int && enable_dpath_ram && !data_wr_int),
      .p0_ack  (ram_ack),
      .p0_addr (ram_dpath_addr),
      .p0_be   (data_be),
      .p0_wdata(data_data_o_int),
      .p0_rdata(data_data_i_int_ram),

      // IPath
      .p1_we   (1'b0),
      .p1_re   (instr_req_int && enable_ipath_ram),
      .p1_ack  (instr_ack_ram),
      .p1_addr (ram_ipath_addr),
      .p1_be   (4'hF),
      .p1_wdata(32'h0),
      .p1_rdata(instr_data_i_int_ram)  // TODO: Impl
  );

  // MMR ---------------------------------------------------------------------
  logic [     31:0] mmr_data_o;
  logic             mmr_ack;

  // GPIOs
  logic             gpio_enable;
  logic [GpioW-1:0] gpio_addr;

  // MTIME
  // TODO: & timecmp

  // TODO: Byte enable for RAM & GPIO writes

  assign gpio_enable = enable_dpath_mmr && mmr_dpath_addr[MmrW-1:3] == MmrOffsetGpio[MmrW-1-3:0];
  assign gpio_addr   = mmr_dpath_addr[2:0];
  bit mmr_req;
  assign mmr_req = data_req_int && enable_dpath_mmr;
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      mmr_ack <= 0;
      //gpio_o_update <= 0;
      //gpio_i_update <= 0;
      mmr_data_o <= 0;
    end else begin
      if (data_req_int && enable_dpath_mmr) begin
        mmr_ack <= 1;

        if (gpio_enable) begin
          if (data_wr_int) begin
            // GPIO W
            // gpio_o[gpio_addr] <= data_data_o_int;
            for (int i = 0; i < 4; i = i + 1) begin
              gpio_o[gpio_addr][i*8+:8] <= data_data_o_int[i*8+:8];
            end
            // gpio_o_update[gpio_addr] <= 1;
          end else begin
            // GPIO R
            mmr_data_o <= gpio_i[gpio_addr];
            // gpio_i_update[gpio_addr] <= 1;
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

  generate
    genvar i;
    for (i = 0; i < GpioN; i = i + 1) begin : gpio_update_gen
      always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
          gpio_o_update[i] <= 0;
          gpio_i_update[i] <= 0;
        end else begin
          if (mmr_req && gpio_enable && gpio_addr == i) begin
            if (data_wr_int) begin
              gpio_o_update[i] <= 1;
              gpio_i_update[i] <= 0;
            end else begin
              gpio_o_update[i] <= 0;
              gpio_i_update[i] <= 1;
            end
          end else begin
            gpio_o_update[i] <= 0;
            gpio_i_update[i] <= 0;
          end
        end
      end
    end
  endgenerate

  // MUX IPATH ---------------------------------------------------------------

  always_comb begin
    instr_data_i_int_rom = enable_ipath_rom ? rom[rom_ipath_addr] : instr_data_i;

    if(enable_ipath_rom) begin
      instr_data_i_int = instr_data_i_int_rom;
      instr_ack_int    = instr_ack_rom;
      instr_err_int    = 0;
    end else if(enable_ipath_ram) begin
      instr_data_i_int = instr_data_i_int_ram;
      instr_ack_int    = instr_ack_ram;
      instr_err_int    = 0;
    end else begin
      instr_data_i_int = instr_data_i;
      instr_ack_int    = instr_ack;
      instr_err_int    = instr_err;
    end
  end

  // MUX DPATH ---------------------------------------------------------------

  always_comb begin
    if (enable_dpath_internal) begin
      // Internal peripherals
      case ({
        enable_dpath_rom, enable_dpath_ram, enable_dpath_mmr
      })
        3'b100: begin
          data_ack_int = rom_ack;
          data_data_i_int = rom[rom_dpath_addr];
        end
        3'b010: begin
          data_ack_int = ram_ack;
          data_data_i_int = data_data_i_int_ram;
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
      .INITIAL_PC(INITIAL_PC),
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
