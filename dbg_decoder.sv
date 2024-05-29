`timescale 1ns/500ps

`include "dbg_commands.sv"

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



module dbg_decoder #(
    parameter int DatW = 4, // in Bytes
    parameter int AdrW = 4, // in Bytes
    parameter int BAUD_WIDTH = 12, // Bits of BAUD divider
    parameter int TimeoutInCycles = 20 * (50000000 / 115200) // Assume serial baud 115200, 10b tolerance and 50MHz clk
  ) (
    // System
    input logic                   clk,
    input logic                   rst,
    // Data
    output logic  [DataWidth-1:0] cmd,
    output logic                  cmd_valid,
    output logic                  error_detected,
    output logic                  idle,
    // Byte Receiver Interface
    input logic recv_data_valid,
    input logic recv_data,
    input logic recv_busy,
    input logic recv_error_detected
);

  // Amound of bytes to make up a command
  localparam int CmdW = 1;
  localparam int MaxBytes = CmdW + AdrW + DatW;
  localparam int TOWidth = $clog2(TimeoutInCycles);
  localparam int ByteCtrWidth = $clog2(MaxBytes);

  typedef enum {
    IDLE,
    AWAIT_CMD_BYTE,
    AWAIT_BYTES,
    FINISHED,
    ERROR
  } state_t;

  state_t state, state_next;

  // After first byte the command is known and so are the remaining bytes
  logic [ByteCtrWidth:0] remaining_bytes_ctr;

  // logic [ByteCtrWidth:0] ctr_current_byte;
  // logic                  ctr_current_byte_fire;
  logic [TOWidth:0] ctr_timeout;
  logic             ctr_timeout_fire;
  
  assign cmd_valid = state === FINISHED;
  assign error_detected = state === ERROR;
  assign idle = state === IDLE;

  assign ctr_timeout_fire = int'(ctr_timeout) == TimeoutInCycles - 1;
  assign ctr_bytes_collected = int'(remaining_bytes_ctr) == 0;

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

  // Byte retrieval and timeout logic
  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      ctr_timeout <= 0;
      ctr_timeout_fire <= 0;
      ctr_current_byte <= 0;
    // end else if (state != AWAIT_BYTES && state != AWAIT_CMD_BYTE) begin
    //   ctr_timeout <= 0;
    //   ctr_timeout_fire <= 0;
    //   ctr_current_byte <= 0;
    end else if (state == AWAIT_CMD_BYTE) begin
      //
    end else if (state == AWAIT_BYTES) begin
      if(recv_data_valid) begin
        ctr_current_byte <= ctr_current_byte +1;
      end

      if( int'(ctr_timeout_fire) == TimeoutInCycles - 1 ) begin
        ctr_timeout <= ctr_timeout + 1;
      end else begin
        ctr_timeout <= 0;
        ctr_timeout_fire <= 1;
      end
    end else begin
      ctr_timeout <= 0;
      ctr_timeout_fire <= 0;
      ctr_current_byte <= 0;
    end
  end

endmodule


