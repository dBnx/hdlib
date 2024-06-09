module rv32_mod_load_store_unit #(
) (
    input        clk,
    input        reset,

    // HART Interface
    input [ 3:0] req_type, // [S,U]; Reserved; Size
    input        wr,
    input [31:0] address,
    input [31:0] data_i,
    output logic [31:0] data_o,
    output logic        valid,
    output logic        stall,
    
    // External interf
    output        data_req,
    output        data_wr,
    input         data_ack,
    input         data_err,
    output [ 3:0] data_be,
    output [31:0] data_addr,
    output [31:0] data_data_o,
    input  [31:0] data_data_i
);
    logic req_signed;
    logic [1:0] req_size;
    assign req_signed = req_type[3];
    assign req_size = req_type[1:0];

    assign data_data_o = data_i;
    // assign data_o = data_data_i;
    assign data_req = req_type != 0;
    assign data_wr = wr;
    assign data_addr = {address[31:2], 2'h0};
    assign valid = data_ack;
    // Stalling halts the PC, so only emit if there is an actual request
    assign stall = (!data_ack && !data_err) && data_req;

    logic [31:8] sign;
    logic sign_16;
    logic sign_8;
    logic sign_bit;
    assign sign_16 = address[1] ? data_data_i[31] : data_data_i[15];
    assign sign = {24{sign_bit}};

    // FIXME: Add handling of aligned store / loads
    always_comb begin
        case(req_size)
        2'b01: data_be = 1'b1 << address[1:0];
        2'b10: data_be = address[1] ? 4'b1100 : 4'b0011;
        2'b11: data_be = 4'b1111;
        default: data_be = 0;
        endcase

        case(address[1:0])
        2'b00: sign_8 = data_data_i[7];
        2'b01: sign_8 = data_data_i[15];
        2'b10: sign_8 = data_data_i[23];
        2'b11: sign_8 = data_data_i[31];
        default: sign_bit = 0;
        endcase

        case({req_signed, req_size})
        3'b101: sign_bit = sign_8;
        3'b110: sign_bit = sign_16;
        default: sign_bit = 0;
        endcase

        case(req_size)
        2'b01: begin
            case(address[1:0])
            2'b00: data_o = {sign[31:8], data_data_i[ 7: 0]};
            2'b01: data_o = {sign[31:8], data_data_i[15: 8]};
            2'b10: data_o = {sign[31:8], data_data_i[23:16]};
            2'b11: data_o = {sign[31:8], data_data_i[31:24]};
            default: data_o = 0;
            endcase
        end
        2'b10: data_o = address[1] ? {sign[31:16], data_data_i[31:16]} : {sign[31:16], data_data_i[31:16]};
        2'b11: data_o = data_data_i;
        default: data_o = 0;
        endcase
    end

endmodule