`timescale 1ns / 1ps

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
    input  bit [31:0] instruction,
    input  bit [ 1:0] priviledge,
    input  bit        in_trap_handler,

    output bit [ 4:0] rf_read0_index,
    output bit [ 4:0] rf_read1_index,
    output bit [ 4:0] rf_write0_index,
    output bit        rf_target_is_x0,
    output bit        rf_source_is_x0,

    output bit        sys_jump_to_m,
    output bit        sys_ret_from_priv,

    output bit [ 5:0] instruction_format,
    output bit [ 5:0] func,
    output bit [ 2:0] funct3,
    output bit [ 6:0] funct7,
    output bit        is_mem_or_io,
    output bit        is_system,
    output bit        is_compressed,
    output bit        error
);
    bit [6:0] opcode;
    assign opcode = instruction[6:0];
    assign is_compressed = opcode[1:0] != 2'b11;

    bit is_m_mode;
    assign is_m_mode = priviledge == 2'b11;

    // Registers
    bit       is_r_type;
    bit       is_i_type;
    bit       is_s_type;
    bit       is_u_type;
    bit [4:0] rs1, rs2, rd;
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign rd  = instruction[11:7];
    assign rf_read0_index     = is_u_type ? 0 : rs1;
    assign rf_read1_index     = is_u_type ? 0 : rs2;
    assign rf_write0_index    = is_s_type ? 0 : rd;
    assign instruction_format = {is_r_type, is_i_type, is_s_type, is_s_subtype_b,
                                 is_u_type, is_u_subtype_j};
    assign rf_target_is_x0 = rd == 0;
    assign rf_source_is_x0 = rs1 == 0;

    // System instructions:
    bit is_sys_ecall, is_sys_ebreak, is_sys_mret;
    bit is_sys_pause, is_sys_wfi;
    // TODO: Rewrite constants to not check for instr[7]
    // TODO: pause and wfi are probably also available in is_m_mode?
    // NOTE: is_sys_ecall does not test for !in_trap_handler as we double fault anyway.
    assign is_sys_ecall  = is_system && !instruction[7] && instruction[31:8] == 24'h000_00_0;
    assign is_sys_ebreak = is_system && !instruction[7] && instruction[31:8] == 24'h001_00_0;
    assign is_sys_mret   = is_system && !instruction[7] && instruction[31:8] == 24'h302_00_0
                           && is_m_mode && in_trap_handler;
    assign is_sys_pause  = is_system && !instruction[7] && instruction[31:8] == 24'h010_00_0;
    assign is_sys_wfi    = is_system && !instruction[7] && instruction[31:8] == 24'h105_00_0;

    assign sys_jump_to_m = is_sys_ecall || is_sys_ebreak;
    assign sys_ret_from_priv = is_sys_mret;

    // TODO: Better implement pause and wfi. Currently NOPs


    // Subtypes change immediate value encoding
    bit is_u_subtype_j;
    bit is_s_subtype_b;

    // Function
    // bit [2:0] funct3;
    // bit [6:0] funct7;
    bit       alternative_func;
    assign funct3 = instruction[14:12];
    // In the special case of SRAI we have to pass through funct7, even though it's I type.
    // Reason is that S??I type instructions use I type, but split it like R type. Instead of
    // reading index, we use that part as an immediate. Includes: SLLI SRLI, SRAI
    assign funct7 = is_r_type || (is_i_type && funct3 == 3'b101) ? instruction[31:25] : 7'b000_0000;
    assign alternative_func = funct7[5] && (!is_i_type || is_i_type && funct3 == 3'b101); // FIXME: To whitelist -> r_type?
    // Tr
    assign func[3:0] = {alternative_func, funct3};
    assign func[4] = opcode[6:2] == `OP_LUI;
    assign func[5] = opcode[6:2] == `OP_JALR;

    // logic promote_priviledge_m;
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

    bit is_sys_csr;
    always_comb begin
        is_r_type = 0;
        is_i_type = 0;
        is_s_type = 0;
        is_u_type = 0;
        is_u_subtype_j = 0;
        is_s_subtype_b = 0;
        is_mem_or_io = 0;
        is_system = 0;
        is_sys_csr = 0;
        // promote_priviledge_m = 0;
        // error = 0;

        if( !is_compressed ) begin
            case(opcode[6:2])
                `OP_OP_IMM  : // I
                    is_i_type = 1;
                    // FIXME: Use is_i_type = instruction[11:7] != 0;
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
                `OP_MISC_MEM: begin  // I
                    // FENCE FENCE.TSO PAUSE
                    // is_i_type = 1;
                end
                `OP_SYSTEM  : begin
                    is_system = 1;
                    is_sys_csr = funct3[1:0] != 2'b00;
                    // I
                    // ECALL (0), EBREAK (1)
                    is_i_type = 1;
                    // promote_priviledge_m = 1;
                    // CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI
                    // Depending on the type rs1 == x0 has different effects.
                    // is_weird_type = 1;
                    // if(!sys_known_instr) begin
                    //     // Unkwnon instruction
                    //     error = 1;
                    // end
                end
                default: begin
                    // error = 1;
                end
            endcase
        end
    end

    bit sys_known_instr;
    assign sys_known_instr = is_sys_ebreak || is_sys_ecall || is_sys_mret || is_sys_pause || is_sys_wfi || is_sys_csr;

    bit sys_permission_error;
    assign sys_permission_error = is_system && !sys_known_instr;

    always_comb begin : id_error
        error = 0;
        if     (instruction[1:0] != 2'b11) error = 1;
        else if(sys_permission_error)      error = 1;
    end


endmodule
