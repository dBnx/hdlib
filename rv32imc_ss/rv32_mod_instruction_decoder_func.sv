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

typedef bit [1:0] wb_source_t;
`define WB_SOURCE_ALU 0
`define WB_SOURCE_PC  1
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
    input [5:0] func,

    output                   rf_write0_enable,
    output                   alu_op0_use_pc,
    output                   alu_op1_use_imm,
    output             [4:0] alu_func,
    output             [3:0] ram_special,
    output                   ram_wr,
    output wb_source_t       wb_source,

    output br_condition_t br_cond,
    output                br_is_cond,
    output                br_jmp
);

  // Set for immediate shift: alu_op1_use_imm 
  // And pass immediate value through imm

endmodule

