module rv32_mod_load_store_unit #(
) (
    input        clk,
    input        reset,

    // HART Interface
    input        req,
    input [ 3:0] req_type, // [S,U]; Reserved; Size
    input        wr,
    input [31:0] address,
    input [31:0] data_i,
    output logic [31:0] data_o,
    output logic        valid,
    output logic        error,
    output logic        stall,
    
    // External interf
    output        dext_req,
    output        dext_wr,
    input         dext_ack,
    input         dext_err,
    output [ 3:0] dext_be,
    output [31:0] dext_addr,
    output [31:0] dext_do,
    input  [31:0] dext_di
);
    logic [ 3:0] dext_be_comb;
    logic [31:0] dext_di_comb;


    logic req_signed;
    logic [1:0] req_size;
    assign req_signed = req_type[3];
    assign req_size = req_type[1:0];

    // Stalling halts the PC, so only emit if there is an actual request

    logic [31:8] sign;
    logic sign_16;
    logic sign_8;
    logic sign_bit;
    assign sign_16 = address[1] ? dext_di[31] : dext_di[15];
    assign sign = {24{sign_bit}};

    // FIXME: Add handling of aligned store / loads
    always_comb begin
        case(req_size)
        2'b00: dext_be_comb = 1'b1 << address[1:0];
        2'b01: dext_be_comb = address[1] ? 4'b1100 : 4'b0011;
        2'b10: dext_be_comb = 4'b1111;
        default: dext_be_comb = 0;
        endcase

        case(address[1:0])
        2'b00: sign_8 = dext_di[7];
        2'b01: sign_8 = dext_di[15];
        2'b10: sign_8 = dext_di[23];
        2'b11: sign_8 = dext_di[31];
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
            2'b00: dext_di_comb = {sign[31:8], dext_di[ 7: 0]};
            2'b01: dext_di_comb = {sign[31:8], dext_di[15: 8]};
            2'b10: dext_di_comb = {sign[31:8], dext_di[23:16]};
            2'b11: dext_di_comb = {sign[31:8], dext_di[31:24]};
            default: dext_di_comb = 0;
            endcase
        end
        2'b10: dext_di_comb = address[1] ? {sign[31:16], dext_di[31:16]} : {sign[31:16], dext_di[31:16]};
        2'b11: dext_di_comb = dext_di;
        default: dext_di_comb = 0;
        endcase
    end

    assign stall = (!dext_ack && !dext_err) && dext_req;
    always_ff @( posedge clk or posedge reset ) begin
        if(reset) begin
            dext_req <= 0;
            dext_wr <= 0;
            dext_addr <= 0;
            dext_be <= 0;
        end else begin
            // Hold?
            dext_req <= req;
            dext_wr <= wr;
            dext_addr <= {address[31:2], 2'h0};
            dext_be <= dext_be_comb;

            valid = dext_ack;
            error = dext_err;

            if(wr) begin
                dext_do <= data_i;
            end else if(!wr && dext_ack) begin
                data_o <= dext_di_comb;
            end
        end
    end

endmodule