`timescale 1us / 1ns

// Author: David B. <initials_same_order_seperated_with_dot@nsch.at>
// Description: -
//              -
// First de-assert CS.
// At every pos edge MOSI must be stable ans MISO can be read
//              -
// Notes: Generic `DATA_WIDTH` is not yet implemented and must stay unaltered.
//        Controller/Peripheral
module spi_device(
    // ╭────────────────────────────────────────────────────────────────────╮
    // │                              System                                │
    // ╰────────────────────────────────────────────────────────────────────╯
    input  logic        clk,
    input  logic        rst,
    // ╭────────────────────────────────────────────────────────────────────╮
    // │                              System                                │
    // ╰────────────────────────────────────────────────────────────────────╯
    // Control - In
    input  logic        start_cycle,
    input  logic        wr_secondary,
    input  logic        sel_secondary,
    // Control - Out
    output logic        busy_bit,
    output logic        busy_transfer,
    output logic        incomplete,
    // Data
    input  logic [ 7:0] data_secondary,
    input  logic [ 7:0] data_primary,
    output logic [ 7:0] data_primary,
    // ╭────────────────────────────────────────────────────────────────────╮
    // │                               SPI                                  │
    // ╰────────────────────────────────────────────────────────────────────╯
    input  logic        si,
    output logic        so,
    output logic        so_highz,
    input  logic        sck,
    input  logic        cs_n,
    // ╭────────────────────────────────────────────────────────────────────╮
    // │                           Configuration                            │
    // ╰────────────────────────────────────────────────────────────────────╯
    input  logic        cpol,
    input  logic        cpha
);
  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                 Types                                 │
  // ╰───────────────────────────────────────────────────────────────────────╯
  // State Machine
  typedef enum logic [2:0] {
    IDLE       = 3'b000,
    START      = 3'b001,
    DATA_BITS  = 3'b010,
    STOP       = 3'b100
  } state_t;

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                Signals                                │
  // ╰───────────────────────────────────────────────────────────────────────╯
  state_t      state, next_state;

  logic [ 3:0] bit_position; // TODO: Impl
  // logic [11:0] baud_counter;

  logic [ 7:0] data_primary;   // TODO: Impl
  logic [ 7:0] data_secondary; // TODO: Impl

  logic        next_bit;

  // Registered inputs
  logic        mode_cpol, mode_cpha;
  // logic        sclk_bit_pos;  // Rising edge always means change data
  logic        sclk_next_bit;    // Rising edge always means shift
  logic        transfer_secondary;

  logic        cs;
  logic        sclk_active_high;
  logic        sclk_active_high_previous;
  logic        sclk_active_high_posedge;


  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                 Logic                                 │
  // ╰───────────────────────────────────────────────────────────────────────╯

  always_ff @(posedge clk or posedge rst) begin : state_transition
    if (rst) begin
      state <= IDLE;
    end else begin
      if(start === IDLE || sclk_active_high_posedge) begin
        state <= next_state;
      end
    end
  end

  always_ff @(posedge clk) begin : register_inputs
    if (start && state == IDLE) begin
      transfer_secondary <= sel_secondary;
      mode_cpol <= cpol;
      mode_cpha <= cpha;
    end

    cs <= ~cs_n;
    sclk_active_high_previous <= sclk_active_high;
  end

  // TODO: Check this one
  assign sclk_next_bit = mode_cpha && ~mode_cpol ? sck : ~sck;
  assign sclk_active_high = mode_cpha ? ~sck : sck;
  assign sclk_active_high_posedge = sclk_active_high && ~sclk_active_high_previous;

  always_comb begin : next_state_and_busy
    case (state)
      IDLE: begin
        next_state = start === 1 ? START : IDLE;
      end
      START: begin
        next_state <= DATA_BITS;
      end
      // START: begin
      //   next_state = sclk === 1 ? START : IDLE;
      //   next_state = DATA_BITS;
      // end
      DATA_BITS: begin
        if (~cs) begin
          next_state = IDLE;
        end else if (bit_position >= 7) begin
          next_state = START;
        end else begin
          next_state = DATA_BITS;
        end
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin : data
    if (rst) begin
      bit_position <= data_primary;
      parity_bit   <= data_secondary;
    end else if (state === IDLE && start) begin
      // TODO:
      bit_position <= 0;
      parity_bit   <= 0;
    end else begin
      // TODO:
      if (baud_counter == baud_divider_registered) begin
        parity_bit   <= parity_bit ^ data_registered[3'(bit_position)];
        bit_position <= bit_position + 1;
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin : bit_counter
    if (rst) begin
      bit_position <= 0;
    end else if (state != DATA_BITS) begin
      bit_position <= 0;
    end else begin
      if (sclk_active_high_posedge) begin
        bit_position <= bit_position + 1;
      end
    end
  end
endmodule

