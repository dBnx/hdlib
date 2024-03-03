`timescale 1us / 1ns

// Author: David B. <initials_same_order_seperated_with_dot@nsch.at>
// Description: Simple UART transceiver with runtime settings (except for data)
//              Allows BAUD of 9600 at 50MHz and much faster settings.
//              Single stop bit between transfers. Inputs are registered at
//              next posedge of clk if not busy. Ongoing transfers can not be
//              stopped.
// Notes: Generic `DATA_WIDTH` is not yet implemented and must stay unaltered.
module uart_tx (
    // System
    input  logic        clk,
    input  logic        rst,
    // Data
    input  logic        start,
    input  logic [ 7:0] data,
    output logic        busy,
    // Uart
    output logic        tx,
    // Configuration
    input  logic [11:0] baud_divider,
    input  logic        parity_en,
    input  logic        parity_type_odd
);
  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                               Parameters                              │
  // ╰───────────────────────────────────────────────────────────────────────╯
  // TODO: Not yet implemented
  parameter int DATA_WIDTH = 8;

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                 Types                                 │
  // ╰───────────────────────────────────────────────────────────────────────╯
  // State Machine
  typedef enum logic [2:0] {
    IDLE       = 3'b000,
    START_BIT  = 3'b001,
    DATA_BITS  = 3'b010,
    PARITY_BIT = 3'b011,
    STOP_BIT   = 3'b100
  } state_t;

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                Signals                                │
  // ╰───────────────────────────────────────────────────────────────────────╯
  // Internal
  state_t state, next_state;

  logic [ 3:0] bit_position;
  logic [11:0] baud_counter;
  logic        parity_bit;

  // Registered inputs
  logic [ 7:0] data_registered;
  logic [11:0] baud_divider_registered;
  logic        parity_en_registered;
  logic        parity_type_odd_registered;
  logic        start_registered;

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                 Logic                                 │
  // ╰───────────────────────────────────────────────────────────────────────╯
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      start_registered <= 0;
    end else if (state == STOP_BIT && baud_counter == 0) begin
      start_registered <= 0;
    end else if (~busy && start) begin
      start_registered <= 1;
    end else begin
      start_registered <= start_registered;
    end
  end

  always_ff @(posedge clk) begin : register_inputs
    if (!busy && start && !start_registered) begin
      data_registered <= data;
      baud_divider_registered <= baud_divider;
      parity_en_registered <= parity_en;
      parity_type_odd_registered <= parity_type_odd;
    end
  end

  always_ff @(posedge clk or posedge rst) begin : state_transition
    if (rst) begin
      state <= IDLE;
      busy  <= 0;
    end else begin
      if ((state == IDLE) || (baud_counter == baud_divider_registered)) begin
        state <= next_state;
      end

      if ((state === IDLE || state === STOP_BIT) && !start && !start_registered) begin
        busy <= 0;
      end else begin
        busy <= 1;
      end
    end
  end

  always_comb begin : next_state_and_busy
    case (state)
      IDLE: begin
        // Cast needed for icarus
        next_state = (start === 1 || start_registered === 1) ? START_BIT : IDLE;
      end
      START_BIT: begin
        next_state = DATA_BITS;
      end
      DATA_BITS: begin
        if (bit_position >= 4'(DATA_WIDTH - 1)) begin
          next_state = (parity_en_registered === 1) ? PARITY_BIT : STOP_BIT;
        end else begin
          next_state = DATA_BITS;
        end
      end
      PARITY_BIT: begin
        next_state = STOP_BIT;
      end
      // Same as IDLE
      STOP_BIT: begin
        next_state = (start_registered === 1) ? START_BIT : IDLE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  always_comb begin : uart_tx
    case (state)
      START_BIT: begin
        tx = 0;
      end
      DATA_BITS: begin
        // TODO: Which direction?
        tx = data_registered[3'(bit_position)];
      end
      PARITY_BIT: begin
        tx = (parity_type_odd) ? ~parity_bit : parity_bit;
      end
      default: begin
        tx = 1;
      end
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin : baud_counter_logic
    if (rst) begin
      baud_counter <= 0;
    end else if (state === IDLE) begin
      baud_counter <= 0;
    end else begin
      if (baud_counter < baud_divider_registered) begin
        baud_counter <= baud_counter + 1;
      end else begin
        baud_counter <= 0;
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin : bit_pos_and_parity
    if (rst) begin
      bit_position <= 0;
      parity_bit   <= 0;
    end else if (state != DATA_BITS) begin
      bit_position <= 0;
      parity_bit   <= 0;
    end else begin
      if (baud_counter == baud_divider_registered) begin
        parity_bit   <= parity_bit ^ data_registered[3'(bit_position)];
        bit_position <= bit_position + 1;
      end
    end
  end
endmodule

