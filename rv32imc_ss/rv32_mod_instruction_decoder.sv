`define OP_OP_IMM    7'b00100 // I
`define OP_OP_IMM_32 7'b00110 // I
`define OP_LUI       7'b01101 // U
`define OP_AUIPC     7'b00101 // U
`define OP_OP        7'b01100 // R
`define OP_JAL       7'b11011 // J
`define OP_JALR      7'b11001 // I
`define OP_BRANCH    7'b11000 // B
`define OP_LOAD      7'b00000 // I
`define OP_STORE     7'b01000 // S
`define OP_MISC_MEM  7'b00011 // I
`define OP_SYSTEM    7'b11100 // I

module rv32_mod_instruction_decoder (
    input  [31:0] instruction,

    output [ 4:0] rf_read0_index,
    output [ 4:0] rf_read1_index,
    output [ 4:0] rf_write0_index,

    output [ 5:0] instruction_format,
    output [ 5:0] func,
    output        is_compressed
);
    bit [6:0] opcode;
    assign opcode = instruction[6:0];
    assign is_compressed = opcode[1:0] != 3'b11;
    
    // Registers
    bit is_r_type;
    bit is_i_type;
    bit is_s_type;
    bit is_u_type;
    bit [4:0] rs1, rs2, rd;
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign rd = instruction[11:7];
    assign rf_read0_index = is_u_type ? 0 : rs1;
    assign rf_read1_index = is_u_type || is_i_type ? 0 : rs2;
    assign rf_write0_index = is_u_type ? 0 : rd;
    assign instruction_format = {is_r_type, is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j};

    // Subtypes change immediate value encoding
    bit is_u_subtype_j;
    bit is_s_subtype_b;

    // Function
    bit [2:0] funct3;
    bit [6:0] funct7;
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];
    
    /*
    localparam bit[4:0] ALU_I  = 5'b001_X0;
    localparam bit[2:0] ALU_I_ADDI  = 3'b000;
    localparam bit[2:0] ALU_I_SLTI  = 3'b010;
    localparam bit[2:0] ALU_I_SLTIU = 3'b011;
    localparam bit[2:0] ALU_I_XORI  = 3'b100;
    localparam bit[2:0] ALU_I_ORI   = 3'b110;
    localparam bit[2:0] ALU_I_ANDI  = 3'b111;

    localparam bit[4:0] ALU_S         = 5'b011_00;
    localparam bit[2:0] ALU_S_ADD_SUB = 3'b000;
    localparam bit[2:0] ALU_S_SLL     = 3'b001;
    localparam bit[2:0] ALU_S_SLT     = 3'b010;
    localparam bit[2:0] ALU_S_SLTU    = 3'b011;
    localparam bit[2:0] ALU_S_XOR     = 3'b100;
    localparam bit[2:0] ALU_S_SRL_SRA = 3'b101;
    localparam bit[2:0] ALU_S_OR      = 3'b110;
    localparam bit[2:0] ALU_S_AND     = 3'b111;
    */

    always_comb begin
        is_r_type = 0;
        is_i_type = 0;
        is_s_type = 0;
        is_u_type = 0;
        is_u_subtype_j = 0;
        is_s_subtype_b = 0;

        if( !is_compressed ) begin
            case(opcode) 
                OP_OP_IMM  : // I
                    is_i_type = 1;
                    break;
                OP_OP_IMM_32: // I
                    is_i_type = 1;
                    break;
                OP_LUI     : // U
                    is_u_type = 1;
                    break;
                OP_AUIPC   : // U
                    is_u_type = 1;
                    break;
                OP_OP      : // R
                    is_r_type = 1;
                    break;
                OP_JAL     : // J
                    is_j_type = 1;
                    break;
                OP_JALR    : // I
                    is_i_type = 1;
                    break;
                OP_BRANCH  : // B
                    is_s_type = 1;
                    is_s_subtype_b = 1;
                    break;
                OP_LOAD    : // I
                    is_i_type = 1;
                    break;
                OP_STORE   : // S
                    is_s_type = 1;
                    break;
                OP_MISC_MEM: // I
                    is_i_type = 1;
                    break;
                OP_SYSTEM  : // I
                    is_i_type = 1;
                    break;
                default:
                    is_r_type = 0;
                    is_i_type = 0;
                    is_s_type = 0;
                    is_u_type = 0;
                    is_u_subtype_j = 0;
                    is_s_subtype_b = 0;
                    break;
            endcase
        end
    end

endmodule

