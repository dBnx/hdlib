`timescale 1ns / 1ps

module rv32_mod_registerfile #(
    parameter logic [31:0] INITIAL_GP = 32'h80000000,
    parameter logic [31:0] INITIAL_SP = 32'h7FFFFFF0,
    parameter logic        ASYNC_READ = 1
) (
    input  logic clk,
    input  logic reset, // Currently unused!

    input  logic [ 4:0] read0_index,
    output logic [31:0] read0_data,

    input  logic [ 4:0] read1_index,
    output logic [31:0] read1_data,

    input  logic [ 4:0] write0_index,
    input  logic [31:0] write0_data,
    input  logic        write0_enable
);

  logic [31:0] registerfile[31];

  initial begin
    registerfile[1] = INITIAL_GP;
    registerfile[2] = INITIAL_SP;
  end

  always_ff @(posedge clk) begin
    if (write0_enable == 1'b1 && write0_index != 0) begin
      registerfile[write0_index] <= write0_data;
    end
  end

  generate
    if (ASYNC_READ == 1'b1) begin : gen_USE_ASYNC_READ
      assign read1_data = read1_index == 0 ? 0 : registerfile[read1_index];
      assign read0_data = read0_index == 0 ? 0 : registerfile[read0_index];
    end else begin : gen_USE_SYNC_READ
      always_ff @(posedge clk) begin
        read1_data <= read1_index == 0 ? 0 : registerfile[read1_index];
        read0_data <= read0_index == 0 ? 0 : registerfile[read0_index];
      end
    end
  endgenerate

endmodule

