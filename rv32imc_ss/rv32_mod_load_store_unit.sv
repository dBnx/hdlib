module rv32_mod_load_store_unit #(
) (
    input        clk,
    input        reset,

    // HART Interface
    input [ 3:0] req_type,
    input        wr,
    input [31:0] address,
    input [31:0] data_i,
    output logic [31:0] data_o,
    output logic        valid,
    output logic        stall,
    
    // External interf
    output        data_req,
    input         data_wr,
    input         data_ack,
    input         data_err,
    output [31:0] data_addr,
    output [31:0] data_data_o,
    input  [31:0] data_data_i
);


endmodule