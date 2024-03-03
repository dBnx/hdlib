`timescale 1us/1ns

// Author: David B. <initials_same_order_seperated_with_dot@nsch.at>
// Description: Simple UART receiver with runtime settings (except for data)
//              Allows BAUD of 9600 at 50MHz and much faster settings.
//              Single stop bit between transfers. Inputs are registered at
//              next posedge of clk if not busy. `valid_data` is only asserted
//              for a singly clock cycle. `error_detected?` is asserted until
//              resolved, but never more than once per transfer.
// Notes: Generic `DATA_WIDTH` is not yet implemented and must stay unaltered.
module uart_rx (
    // System
    input logic                   clk,
    input logic                   rst,
    // Data
    output logic                  valid_data,
    output logic [DATA_WIDTH-1:0] data,
    output logic                  busy,
    output logic                  error_detected,
    // Uart
    input logic                   rx,
    // Configuration
    input logic  [BAUD_WIDTH-1:0] baud_divider,
    input logic                   parity_en,
    input logic                   parity_type_odd
);
    // ╭───────────────────────────────────────────────────────────────────────╮
    // │                               Parameters                              │
    // ╰───────────────────────────────────────────────────────────────────────╯
    // TODO: Parity check not yet implemented!
    parameter int DATA_WIDTH = 8;
    parameter int BAUD_WIDTH = 12;

    // ╭───────────────────────────────────────────────────────────────────────╮
    // │                                 Types                                 │
    // ╰───────────────────────────────────────────────────────────────────────╯
    // State Machine
    typedef enum logic [2:0] {
        IDLE       = 3'h0,
        START_BIT  = 3'h1,
        DATA_BITS  = 3'h2,
        PARITY_BIT = 3'h3,
        STOP_BIT   = 3'h4,
        ERROR      = 3'h5
    } state_t;

    // ╭───────────────────────────────────────────────────────────────────────╮
    // │                                Signals                                │
    // ╰───────────────────────────────────────────────────────────────────────╯
    // Internal
    state_t state, next_state;

    logic [$clog2(DATA_WIDTH):0] bit_position;
    logic                        parity_bit, parity_bit_even;
    logic       [DATA_WIDTH-1:0] data_buffer;
    logic       [BAUD_WIDTH-1:0] baud_counter;
    logic       [BAUD_WIDTH-1:0] baud_divider_reference;

    // Registered inputs
    logic                  rx_registered;
    logic [BAUD_WIDTH-1:0] baud_divider_registered;
    logic                  parity_en_registered;
    logic                  parity_type_odd_registered;

    // ╭───────────────────────────────────────────────────────────────────────╮
    // │                              Assignments                              │
    // ╰───────────────────────────────────────────────────────────────────────╯
    assign parity_bit     = (parity_type_odd_registered) ? ~parity_bit_even : parity_bit_even;
    assign error_detected = (state == ERROR);
    assign data           = (valid_data) ? data_buffer : 8'h0;
    assign baud_divider_reference = (state != START_BIT)
                                  ? baud_divider_registered : baud_divider_registered >> 1;

    // ╭───────────────────────────────────────────────────────────────────────╮
    // │                                 Logic                                 │
    // ╰───────────────────────────────────────────────────────────────────────╯
    always_ff @(posedge clk) begin : register_inputs
      if( ~busy ) begin
        baud_divider_registered <= baud_divider;
        parity_en_registered <= parity_en;
        parity_type_odd_registered <= parity_type_odd;
      end
    end

    always_ff @(posedge clk or posedge rst) begin : register_rx
        if (rst) begin
            rx_registered <= 1;
        end else begin
            rx_registered <= rx;
        end
    end

    always_ff @(posedge clk or posedge rst) begin : state_transition
        if (rst) begin
            state <= IDLE;
        end else begin
            case(state)
              IDLE: begin
                state <= next_state;
              end
              ERROR: begin
                state <= next_state;
              end
              default: begin
                state <= ( baud_counter == baud_divider_reference ) ? next_state : state;
              end
            endcase
        end
    end

    always_comb begin : next_state_and_busy
        case (state)
            IDLE: begin
                next_state = (rx_registered === 0) ? START_BIT : IDLE;
                busy = 0;
            end
            START_BIT: begin
                next_state = (rx_registered === 0) ? DATA_BITS : ERROR;
                busy = 1;
            end
            DATA_BITS: begin
                if(bit_position >= 4'(DATA_WIDTH - 1)) begin
                  next_state = (parity_en_registered === 1) ? PARITY_BIT : STOP_BIT;
                end else begin
                  next_state = DATA_BITS;
                end
                busy = 1;
            end
            PARITY_BIT: begin
                next_state = (parity_bit !== rx_registered) ? ERROR : STOP_BIT;
                busy = 1;
            end
            // Same as IDLE
            STOP_BIT: begin
                next_state = (rx_registered === 0) ? ERROR : IDLE;
                busy = ~valid_data;
            end
            ERROR: begin
                next_state = (rx_registered === 0) ? ERROR : IDLE;
                busy = 1;
            end
            default: begin
                next_state = IDLE;
                busy = 1;
            end
        endcase
    end

    // Valid data detection
    always_ff @(posedge clk or posedge rst) begin: data_valid_bit
        if (rst) begin
            valid_data <= 0;
        end else if (state === IDLE) begin
            valid_data <= 0;
        end else if (state === STOP_BIT && !error_detected) begin
            // Only during the transition STOP_BIT -> IDLE, as the transaction
            // could be invalid
            valid_data <= (state === STOP_BIT)
                       && (next_state === IDLE)
                       && (baud_counter == baud_divider_registered-1);
        end else begin
          valid_data <= 0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin : baud_counter_logic
        if (rst) begin
            baud_counter <= 0;
        end else if (state === IDLE) begin
            baud_counter <= 0;
        end else begin
          if( baud_counter < baud_divider_registered ) begin
              baud_counter <= baud_counter + 1;
          end else begin
              baud_counter <= 0;
          end
        end
    end

    always_ff @(posedge clk or posedge rst) begin: data_parity_bit
        if (rst) begin
            data_buffer <= 0;
            parity_bit_even <= 0;
            bit_position <= 0;
        end else if (state === START_BIT) begin
            data_buffer <= 0;
            parity_bit_even <= 0;
            bit_position <= 0;
        end else if (state == DATA_BITS && baud_counter == baud_divider_registered) begin
            data_buffer <= (state == DATA_BITS)
                           ? {rx_registered, data_buffer[7:1]} : data_buffer;

            parity_bit_even <= (parity_en_registered && state == DATA_BITS)
                               ? (parity_bit_even ^ rx_registered) : 1'b0;

            bit_position <= (state == DATA_BITS)
                            ? bit_position + 1 : bit_position;
        end
    end
endmodule

