module rv32_mod_registerfile #(
    parameter logic ASYNC_READ = 1
) (
    input        clk,

    input  [ 4:0] read0_index,
    output [31:0] read0_data,

    input  [ 4:0] read1_index,
    output [31:0] read1_data,

    input [ 4:0] write0_index,
    input [31:0] write0_data,
    input        write0_enable
);

logic [31:0] registerfile [31];

always_ff @ (posedge clk) begin
    if(write0_enable == 1'b1 && write0_index != 0) begin
        registerfile[write0_index] <= write0_data;
    end
end

generate
    if (ASYNC_READ == 1'b1) begin : gen_USE_ASYNC_READ
        assign read1_data = read1_index == 0 ? 0 : registerfile[read1_index];
        assign read0_data = read0_index == 0 ? 0 : registerfile[read0_index];
    end else begin : gen_USE_SYNC_READ
        always_ff @ (posedge clk) begin
            read1_data <= read1_index == 0 ? 0 : registerfile[read1_index];
            read0_data <= read0_index == 0 ? 0 : registerfile[read0_index];
        end
    end
endgenerate

endmodule