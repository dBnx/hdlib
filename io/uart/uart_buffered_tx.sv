`timescale 1us / 1ns

module uart_buffered_tx (
    // System
    input  logic        clk,
    input  logic        rst,
    // Data
    input  logic        we,
    input  logic [ 7:0] data,
    output logic        buffer_empty,
    output logic        buffer_full,
    // Uart TX
    output logic        tx,
    // Configuration
    input  logic [11:0] baud_divider,
    input  logic        parity_en,
    input  logic        parity_type_odd
);

  logic uart_busy, buffer_re, buffer_we;
  logic [7:0] buffer_2_uart;
  logic just_issued_cmd;



  assign buffer_re = !buffer_empty && !uart_busy;
  assign buffer_we = we && !buffer_full;

  fifo_simple fifo (
      // <<< System >>>
      .clk(clk),
      .rst(rst),
      // <<< Write Port >>>
      .we(buffer_we),  // REVIEW: Remove buffer_full?
      .din(data),
      // <<< Read Port >>>
      .re(buffer_re),
      .dout(buffer_2_uart),
      // <<< Status >>>
      .full(buffer_full),
      .empty(buffer_empty)
  );

  uart_tx uart_tx_mod (
      // <<< System >>>
      .clk(clk),
      .rst(rst),
      // <<< Data >>>
      .start(buffer_re),
      .data(buffer_2_uart),
      .busy(uart_busy),
      // <<< Uart TX >>>
      .tx(tx),
      // <<< Configuration >>>
      .baud_divider(baud_divider),
      .parity_en(parity_en),
      .parity_type_odd(parity_type_odd)
  );

endmodule
