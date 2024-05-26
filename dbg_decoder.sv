`timescale 1ns/500ps

`include "dbg_commands.sv"

module dbg_decoder #(
    parameter int DatW = 4,
    parameter int AdrW = 4,
    parameter int BAUD_WIDTH = 12,
    parameter int TimeoutInCycles = 8
  ) (
    // System
    input logic                   clk,
    input logic                   rst,
    // Data
    output logic                  cmd_data_valid,
    output logic  [DataWidth-1:0] cmd_data,
    output logic                  cmd_busy,
    output logic                  cmd_error_detected,
    // Byte Receiver Interface
    input logic recv_data_valid,
    input logic recv_data,
    input logic recv_busy,
    input logic recv_error_detected
    // // Uart
    // input logic                   rx,
    // // Configuration
    // input logic  [BAUD_WIDTH-1:0] baud_divider,
    // input logic                   parity_en,
    // input logic                   parity_type_odd
);

  localparam int CmdW = 1;
  localparam int MaxBytes = CmdW + AdrW + DatW;
  localparam int TOWidth = $clog2(TimeoutInCycles);
  localparam int ByteCtrWidth = $clog2(MaxBytes);

  typedef enum {
    IDLE,
    AWAIT_BYTE,
    FINISHED,
    ERROR
  } state_t;

  assign cmd_data_valid = state === FINISHED;
  assign cmd_error_detected = state === ERROR;

  state_t state, state_next;

  // Cmd
  logic [ByteCtrWidth:0] cmd_required_bytes;
  logic                  cmd_complete;

  // Inputs
  logic recv_data_valid;
  logic recv_data;
  logic recv_busy;
  logic recv_error_detected;
  // uart_rx rx (
  //     // Syscon
  //     .clk (clk),
  //     .rst (rst),
  //     // Data
  //     .valid_data    (uart_valid_data),
  //     .data          (uart_data),
  //     .busy          (uart_busy),
  //     .error_detected(uart_error_detected),
  //     // Uart
  //     .rx (rx),
  //     // Configuration
  //     .baud_divider   (baud_divider),
  //     .parity_en      (parity_en),
  //     .parity_type_odd(parity_type_odd)
  // );


  // logic [ByteCtrWidth:0] ctr_current_byte;
  // logic                  ctr_current_byte_fire;
  logic [TOWidth:0] ctr_timeout;
  logic             ctr_timeout_fire;

  assign ctr_timeout_fire = ctr_timeout == TimeoutInCycles;
  assign ctr_current_byte_fire = ctr_current_byte == NBytes;

  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      state <= IDLE;
    end else begin
      state <= next_state;

      if( state == AWAIT_BYTE ) begin
          if(ctr_current_byte_fire) begin
            cmd_data <= {cmd_data[(NBytes-1)*8-1:8], recv_data};
          end
      end
    end
  end

  always_comb begin
    if (ctr_timeout_fire || recv_error_detected) begin
      next_state = ERROR;
    end else begin
      case (state)
        IDLE: begin
          next_state = recv_busy ? AWAIT_BYTE : IDLE;
        end
        AWAIT_BYTE: begin
          next_state = ctr_current_byte_fire ? FINISHED : AWAIT_BYTE;
        end
        FINISHED: begin
          next_state = IDLE;
        end
        default : begin
          next_state = IDLE;
        end
      endcase
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      ctr_timeout <= 0;
      ctr_timeout_fire <= 0;
      ctr_current_byte <= 0;
    end else if (state != AWAIT_BYTE) begin
      ctr_timeout <= 0;
      ctr_timeout_fire <= 0;
      ctr_current_byte <= 0;
    end else begin
      if(recv_data_valid) begin
        ctr_current_byte <= ctr_current_byte +1;
      end

      if( int'(ctr_timeout_fire) == TimeoutInCycles - 1 ) begin
        ctr_timeout <= ctr_timeout + 1;
      end else begin
        ctr_timeout <= 0;
        ctr_timeout_fire <= 1;
      end
    end
  end

endmodule


