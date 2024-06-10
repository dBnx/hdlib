`define OP_OP_IMM    5'b00100 // I
`define OP_OP_IMM_32 5'b00110 // I
`define OP_LUI       5'b01101 // U
`define OP_AUIPC     5'b00101 // U
`define OP_OP        5'b01100 // R
`define OP_JAL       5'b11011 // J
`define OP_JALR      5'b11001 // I
`define OP_BRANCH    5'b11000 // B
`define OP_LOAD      5'b00000 // I
`define OP_STORE     5'b01000 // S
`define OP_MISC_MEM  5'b00011 // I
`define OP_SYSTEM    5'b11100 // I

module rv32_mod_instruction_decoder (
    input  [31:0] instruction,

    output [ 4:0] rf_read0_index,
    output [ 4:0] rf_read1_index,
    output [ 4:0] rf_write0_index,

    output [ 5:0] instruction_format,
    output [ 4:0] func,
    output logic      is_mem_or_io,
    output logic      is_compressed
);
    bit [6:0] opcode;
    assign opcode = instruction[6:0];
    assign is_compressed = opcode[1:0] != 2'b11;
    
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
    assign rf_write0_index = is_s_type ? 0 : rd;
    assign instruction_format = {is_r_type, is_i_type, is_s_type, is_s_subtype_b,
                                 is_u_type, is_u_subtype_j};

    // Subtypes change immediate value encoding
    bit is_u_subtype_j;
    bit is_s_subtype_b;

    // Function
    bit [2:0] funct3;
    bit [6:0] funct7;
    bit       alternative_func;
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];
    assign alternative_func = funct7[5] && (!is_i_type || is_i_type && funct3 == 3'b101); // FIXME: To whitelist -> r_type?
    // Tr
    assign func[3:0] = {alternative_func, funct3};
    assign func[4] = opcode[6:2] == `OP_LUI;

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
        is_mem_or_io = 0;

        if( !is_compressed ) begin
            case(opcode[6:2]) 
                `OP_OP_IMM  : // I
                    is_i_type = 1;
                `OP_OP_IMM_32: // I
                    is_i_type = 1;
                `OP_LUI     : // U
                    is_u_type = 1;
                `OP_AUIPC   : // U
                    is_u_type = 1;
                `OP_OP      : // R
                    is_r_type = 1;
                `OP_JAL     : begin // J
                    is_u_type = 1;
                    is_u_subtype_j = 1;
                end
                `OP_JALR    : // I
                    is_i_type = 1;
                `OP_BRANCH  : begin // B
                    is_s_type = 1;
                    is_s_subtype_b = 1;
                end
                `OP_LOAD    : begin // I
                    is_i_type = 1;
                    is_mem_or_io = 1;
                end
                `OP_STORE   : begin // S
                    is_s_type = 1;
                    is_mem_or_io = 1;
                end
                `OP_MISC_MEM: // I
                    is_i_type = 1;
                `OP_SYSTEM  : // I
                    is_i_type = 1;
                default: begin
                    is_r_type = 0;
                    is_i_type = 0;
                    is_s_type = 0;
                    is_s_subtype_b = 0;
                    is_u_type = 0;
                    is_u_subtype_j = 0;
                end
            endcase
        end
    end

endmodule

