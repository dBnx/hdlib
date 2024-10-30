`timescale 1ns / 1ps

module rv32_mod_registerfile #(
    parameter bit [31:0] INITIAL_GP = 32'h80000000,
    parameter bit [31:0] INITIAL_SP = 32'h7FFFFFF0,
    parameter bit        ASYNC_READ = 1
) (
    input  bit clk,
    input  bit reset,

    input  bit [ 4:0] read0_index,
    output bit [31:0] read0_data,

    input  bit [ 4:0] read1_index,
    output bit [31:0] read1_data,

    input  bit [ 4:0] write0_index,
    input  bit [31:0] write0_data,
    input  bit        write0_enable
);

  bit [31:0] registerfile[31];

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
      always_ff @(posedge clk or posedge reset) begin
        if(reset) begin
          read1_data <= 0;
          read0_data <= 0;
        end else begin
          read1_data <= read1_index == 0 ? 0 : registerfile[read1_index];
          read0_data <= read0_index == 0 ? 0 : registerfile[read0_index];
        end
      end
    end
  endgenerate

endmodule

