module uart_buffered_rx (
    // System
    input logic         clk,
    input logic         rst,
    // Data
    output logic         valid,
    output logic   [7:0] data,
    output logic         buffer_empty,
    output logic         buffer_full,
    // Uart
    output logic        rx,
    // Configuration
    output logic        error,
    input logic  [11:0] baud_divider,
    input logic         parity_en,
    input logic         parity_type_odd
);

    logic uart_busy, buffer_re;
    logic [7:0] buffer_2_uart;
    assign ack = we && ~buffer_full;
    assign buffer_re = ~buffer_empty && ~uart_busy;

    fifo fifo_tx (
        // System
        .clk_write(clk),
        .clk_read(clk),
        .rst(rst),
        // <<<< Write Port >>>>
        .we(ack),
        .din(wb_dat_i),
        .full(buffer_full),
        // <<<< Read Port >>>>
        .re(buffer_re),
        .dout(buffer_2_uart),
        .empty(buffer_empty)
    );

    uart_tx tx (
        // System
        .clk(clk),
        .rst(rst),
        // Data
        .start(Buffer_re),
        .data(buffer_2_uart),
        .busy(uart_busy),
        // Uart TX
        .tx(tx),
        // Configuration
        .baud_divider(baud_divider),
        .parity_en(parity_en),
        .parity_type_odd(parity_type_odd)
    );

endmodule

