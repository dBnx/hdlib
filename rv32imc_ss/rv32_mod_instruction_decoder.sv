module rv32_mod_instruction_decoder (
    input  [31:0] instruction,

    output [ 4:0] rf_read0_index,
    output [ 4:0] rf_read1_index,
    output [ 4:0] rf_write0_index,

    output [31:0] immediate,
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

    // Function
    bit [2:0] funct3;
    bit [6:0] funct7;
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];
    
    // Immediates
    bit [10:0] imm_i;
    bit [ 9:0] imm_s;
    bit [19:0] imm_u;
    assign imm_i = instruction[31:20];
    assign imm_s = {funct7, rsd};
    assign imm_u = instruction[31:12];
    always_comb begin
        // TODO: Add b-type, j-type handling
        case({is_r_type, is_i_type, is_s_type, is_u_type}) 
            4'b1000: immediate = imm_r;
            4'b0100: immediate = imm_i;
            4'b0010: immediate = imm_s;
            4'b0001: immediate = imm_u;
        endcase
    end
    
    localparam logic[4:0] ALU_I  = 5'b001_X0;
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
    always_comb begin
        is_r_type = 0;
        is_i_type = 0;
        is_s_type = 0;
        is_u_type = 0;
        if( !is_compressed ) begin
            case(opcode) 
                OP_ADD:
                    is_r_type = 1;
                    break;
                OP_SUB:
                    is_r_type = 1;
                    break;
                OP_SLL:
                    is_r_type = 1;
                    break;
                OP_SLT:
                    is_r_type = 1;
                    break;
                OP_SLTU:
                    is_r_type = 1;
                    break;
                OP_XOR:
                    is_r_type = 1;
                    break;
                OP_SRL:
                    is_r_type = 1;
                    break;
                OP_SRA:
                    is_r_type = 1;
                    break;
                OP_OR:
                    is_r_type = 1;
                    break;
                OP_AND:
                    is_r_type = 1;
                    break;
                OP_ADDI:
                    is_i_type = 1;
                    break;
                OP_SLLI:
                    is_i_type = 1;
                    break;
                OP_SLTI:
                    is_i_type = 1;
                    break;
                OP_SLTUI:
                    is_i_type = 1;
                    break;
                OP_XORI:
                    is_i_type = 1;
                    break;
                OP_SRLI:
                    is_i_type = 1;
                    break;
                OP_SRAI:
                    is_i_type = 1;
                    break;
                OP_ORI:
                    is_i_type = 1;
                    break;
                OP_ANDI:
                    is_i_type = 1;
                    break;
                OP_SLLI:
                    is_i_type = 1;
                    break;
                OP_JALR:
                    is_r_type = 1;
                    break;
                OP_LB:
                    is_i_type = 1;
                    break;
                OP_LH:
                    is_i_type = 1;
                    break;
                OP_LW:
                    is_i_type = 1;
                    break;
                OP_LBU:
                    is_i_type = 1;
                    break;
                OP_LHU:
                    is_i_type = 1;
                    break;
                OP_SB:
                    is_s_type = 1;
                    break;
                OP_SH:
                    is_s_type = 1;
                    break;
                OP_SW:
                    is_s_type = 1;
                    break;
                OP_ADDIW:
                    is_i_type = 1;
                    break;
                OP_SLLIW:
                    is_i_type = 1;
                    break;
                OP_SRLIW:
                    is_i_type = 1;
                    break;
                OP_SRAIW:
                    is_i_type = 1;
                    break;
                OP_ADDW:
                    is_r_type = 1;
                    break;
                OP_SUBW:
                    is_r_type = 1;
                    break;
                OP_SLLW:
                    is_r_type = 1;
                    break;
                OP_SRLW:
                    is_r_type = 1;
                    break;
                OP_SRAW:
                    is_r_type = 1;
                    break;
                OP_SLTW:
                    is_r_type = 1;
                    break;
                OP_SLTUW:
                    is_r_type = 1;
                    break;
                OP_XORW:
                    is_r_type = 1;
                    break;
                OP_ORW:
                    is_r_type = 1;
                    break;
                OP_ANDW:
                    is_r_type = 1;
                    break;
                OP_FENCE:
                    is_u_type = 1;
                    break;
                OP_FENCEI:
                    is_u_type = 1;
                    break;
                OP_ECALL:
                    is_u_type = 1;
                    break;
                OP_EBREAK:
                    is_u_type = 1;
                    break;
                OP_CSRRW:
                    is_u_type = 1;
                    break;
                OP_CSRRS:
                    is_u_type = 1;
                    break;
                OP_CSRRC:
                    is_u_type = 1;
                    break;
                OP_CSRRWI:
                    is_u_type = 1;
                    break;
                OP_CSRRSI:
                    is_u_type = 1;
                    break;
                OP_CSRRCI:
                    is_u_type = 1;
                    break;
                OP_LUI:
                    is_u_type = 1;
                    break;
                default:
                    is_r_type = 0;
                    is_i_type = 0;
                    is_s_type = 0;
                    is_u_type = 0;
                    break;
            endcase
        end
    end
    
    assign rs1 = instruction[];


endmodule

