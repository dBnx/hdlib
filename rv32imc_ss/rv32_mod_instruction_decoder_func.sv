/*
typedef enum logic [2:0] {
  BR_COND_EQ,
  BR_COND_NE,
  BR_COND_GT,
  BR_COND_GE,
  BR_COND_LT,
  BR_COND_LE
} br_condition_t;

typedef enum bit [1:0] {
  WB_SOURCE_ALU,
  WB_SOURCE_PC,
  WB_SOURCE_LSU
} wb_source_t;
*/

`define ALU_OP_ADD 4'b0_000

typedef bit [1:0] wb_source_t;
`define WB_SOURCE_ALU 0
`define WB_SOURCE_PC 1
`define WB_SOURCE_LSU 2

typedef bit [2:0] br_condition_t;
`define BR_COND_NOP 0
`define BR_COND_EQ 1
`define BR_COND_NE 2
`define BR_COND_GT 3
`define BR_COND_GE 4
`define BR_COND_LT 5
`define BR_COND_LE 6

module rv32_mod_instruction_decoder_func (
    input [5:0] instruction_format,  // or opcode?
    input [2:0] funct3,
    input [0:0] b30,

    output logic             rf_write0_enable,
    output logic             alu_op0_use_pc,
    output logic             alu_op1_use_imm,
    output logic       [4:0] alu_func,
    output logic       [3:0] ram_req,
    output logic             ram_wr,
    output wb_source_t       wb_source,

    output br_condition_t br_cond,
    output logic          br_is_cond,
    output logic          br_jmp
);
  // {is_r_type, is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j};

  // Subtypes change immediate value encoding
  // bit is_u_subtype_j;
  // bit is_s_subtype_b;

  // Function
  // bit [2:0] funct3;
  // bit [6:0] funct7;
  // assign funct3 = instruction[14:12];
  // assign funct7 = instruction[31:25];


  always_comb begin
    rf_write0_enable = 0;
    alu_op0_use_pc = 0;
    alu_op1_use_imm = 0;
    alu_func = {1'b0, `ALU_OP_ADD};
    ram_req = 0;
    ram_wr = 0;
    wb_source = `WB_SOURCE_ALU;

    br_cond = 0;
    br_is_cond = 0;
    br_jmp = 0;

    case (instruction_format)
      6'b100000: begin  // R Type
        rf_write0_enable = 1;
        alu_func[2:0] = funct3;
      end
      6'b010000: begin  // I Type - Op or Loads! // TODO: Impl load
        rf_write0_enable = 1;
        alu_op1_use_imm  = 1;
        if (1 == 1) begin  // opcode != `OP_LOAD ) begin
          alu_func[2:0] = funct3;
        end else begin
          wb_source = `WB_SOURCE_LSU;
          alu_func[3:0]  = `ALU_OP_ADD;  // TODO: Handle addressing somehow
          ram_req[2:0]   = funct3;  // Width and signdness
        end
      end
      6'b001000: begin  // S Type - Store
        alu_op1_use_imm = 1;
        ram_req[2:0] = funct3;  // Width and signdness
        alu_func[3:0] = `ALU_OP_ADD;  // TODO: Handle addressing somehow
        ram_wr = 1;
      end
      6'b001100: begin  // B Type - Conditional
        br_cond = funct3;  // FIXME: Check!
        br_is_cond = 1;
        alu_op0_use_pc = 1;  // check!
      end
      6'b000010: begin  // U Type - LUI AUIPC
        rf_write0_enable = 1;
        alu_op1_use_imm = 1;
        alu_func[3:0] = `ALU_OP_ADD;
      end
      6'b000011: begin  // J Type - Unconditional
        alu_op0_use_pc = 1;
        alu_func[3:0] = `ALU_OP_ADD;  // TODO: Handle addressing somehow
        br_jmp = 1;
      end
      default: begin
      end
    endcase
  end
  /*
    always_comb begin
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
*/

  /*
    localparam bit[4:0] ALU_I  = 5'b001_X0;
    localparam bit[2:0] ALU_I_ADDI  = 3'b000;
    localparam bit[2:0] ALU_I_SLTI  = 3'b010;
    localparam bit[2:0] ALU_I_SLTIU = 3'b011;
    localparam bit[2:0] ALU_I_XORI  = 3'b100;
    localparam bit[2:0] ALU_I_ORI   = 3'b110;
    localparam bit[2:0] ALU_I_ANDI  = 3'b111;
  */

  // Set for immediate shift: alu_op1_use_imm 
  // And pass immediate value through imm

endmodule

