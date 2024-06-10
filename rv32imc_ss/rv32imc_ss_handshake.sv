// `define TOP_LEVEL // Top level of a single cycle RISC-V32 processor

// `include "rv32imc_ss/rv32_mod_instruction_decoder.sv"
// `include "rv32imc_ss/rv32_mod_instruction_decoder_func.sv"
// `include "rv32imc_ss/rv32_mod_registerfile.sv"
// `include "rv32imc_ss/rv32_mod_alu.sv"

`define WB_SOURCE_ALU 0
`define WB_SOURCE_PC  1
`define WB_SOURCE_LSU 2


`define BR_COND_NOP 0
`define BR_COND_EQ 1
`define BR_COND_NE 2
`define BR_COND_GT 3
`define BR_COND_GE 4
`define BR_COND_LT 5
`define BR_COND_LE 6

module rv32imc_ss_handshake #(
    parameter logic [31:0] INITIAL_GP = 32'h10000000,
    parameter logic [31:0] INITIAL_SP = 32'h7ffffff0
) (
    input clk,
    input reset,

    output        instr_req,
    input         instr_ack,
    input         instr_err,
    output [31:0] instr_addr,
    input  [31:0] instr_data_i,

    output        data_req,
    output        data_wr,
    input         data_ack,
    input         data_err,
    output [ 3:0] data_be,
    output [31:0] data_addr,
    output [31:0] data_data_o,
    input  [31:0] data_data_i
);

  // Instruction Fetcher
  // logic [31:0] if_address;
  logic [31:0] if_instruction;
  logic        if_valid;
  // assign if_address = pc_current;

  // Program Counter ( global pointer )
  logic        pc_stall;
  logic [31:0] pc_current;
  logic [31:0] pc_next;

  logic [31:0] pc_overwrite_data;
  logic        pc_overwrite_enable;
  assign pc_overwrite_data = alu_result;
  assign pc_overwrite_enable = branch_taken;
  assign pc_stall = !if_valid || lsu_stall;

  // Register File
  logic [31:0] rf_read0_data, rf_read1_data, rf_write0_data;
  always_comb begin
    case (wb_source)
      // TODO: Move encoding inside instr decode (?)
      `WB_SOURCE_ALU: rf_write0_data = alu_result;
      `WB_SOURCE_PC:  rf_write0_data = pc_next; // To register must be next
      `WB_SOURCE_LSU: rf_write0_data = lsu_data_o;
      default: rf_write0_data = 0;
    endcase

  end

  // Instruction Decoder
  logic rf_write0_enable;
  logic [4:0] rf_read0_index, rf_read1_index, rf_write0_index;
  logic          [31:0] immediate;
  logic          [ 5:0] func;
  logic                 is_mem_or_io;
  logic                 is_compressed;

  logic                 alu_op0_use_pc;
  logic                 alu_op1_use_imm;
  logic          [ 4:0] alu_func;
  logic          [ 3:0] lsu_req_type;
  logic                 lsu_wr;
  wb_source_t           wb_source;
  br_condition_t        br_cond;
  logic                 br_is_cond;
  logic                 br_is_jmp;

  logic          [ 5:0] id_instruction_format;

  // ALU
  logic [31:0] alu_read0_data, alu_read1_data;
  logic [31:0] alu_result;
  assign alu_read0_data = alu_op0_use_pc ? pc_current : rf_read0_data;
  assign alu_read1_data = alu_op1_use_imm ? immediate : rf_read1_data;

  // Branching module
  logic        branch_taken;

  // Load store unit
  logic [31:0] lsu_address;
  logic [31:0] lsu_data_o;
  logic        lsu_valid;
  logic        lsu_stall;
  assign lsu_address = alu_result;


  rv32_mod_instruction_fetch inst_if (
      .clk  (clk),
      .reset(reset),

      .if_address_current(pc_current),
      .if_address_next(pc_next),
      .if_instruction(if_instruction),
      .if_valid(if_valid),

      .instr_req(instr_req),
      .instr_ack(instr_ack),
      .instr_err(instr_err),
      .instr_addr(instr_addr),
      .instr_data_i(instr_data_i)
  );

  rv32_mod_pc inst_pc (
      .clk  (clk),
      .reset(reset),

      .stall(pc_stall),
      .is_compressed(is_compressed),
      .pc_current(pc_current),
      .pc_next(pc_next),

      .pc_overwrite_data  (pc_overwrite_data),
      .pc_overwrite_enable(pc_overwrite_enable)
  );

  rv32_mod_instruction_decoder inst_instr_dec (
      .instruction(if_instruction),

      .rf_read0_index(rf_read0_index),
      .rf_read1_index(rf_read1_index),
      .rf_write0_index(rf_write0_index),
      .instruction_format(id_instruction_format),
      .func(func),
      .is_mem_or_io(is_mem_or_io),
      .is_compressed(is_compressed)
  );

  rv32_mod_instruction_decoder_func inst_instr_dec_func (
      .instruction_format(id_instruction_format),
      .func(func),
      .is_mem_or_io(is_mem_or_io),

      .rf_write0_enable(rf_write0_enable),
      .alu_op0_use_pc(alu_op0_use_pc),
      .alu_op1_use_imm(alu_op1_use_imm),
      .alu_func(alu_func),
      .ram_req(lsu_req_type),
      .ram_wr(lsu_wr),
      .wb_source(wb_source),
      .br_cond(br_cond),
      .br_is_cond(br_is_cond),
      .br_jmp(br_is_jmp)
  );

  rv32_mod_instruction_decoder_imm inst_instr_dec_imm (
      .instruction(if_instruction),
      .instruction_format(id_instruction_format),
      .immediate(immediate)
  );

  rv32_mod_registerfile inst_registerfile (
      .clk(clk),

      .read0_index(rf_read0_index),
      .read0_data(rf_read0_data),
      .read1_index(rf_read1_index),
      .read1_data(rf_read1_data),
      .write0_index(rf_write0_index),
      .write0_data(rf_write0_data),
      .write0_enable(rf_write0_enable)
  );

  rv32_mod_alu inst_alu (
      .func(alu_func),
      .read0_data(alu_read0_data),
      .read1_data(alu_read1_data),
      .result(alu_result)
  );

  rv32_mod_branch inst_branch (
      .rf_read0(rf_read0_data),
      .rf_read1(rf_read1_data),
      .cond(br_cond),
      .is_cond(br_is_cond),
      .is_jmp(br_is_jmp),
      .branch_taken(branch_taken)
  );

  rv32_mod_load_store_unit inst_lsu (
      .clk  (clk),
      .reset(reset),

      .req_type(lsu_req_type),
      .wr(lsu_wr),
      .address(lsu_address),
      .data_i(rf_read1_data),
      .data_o(lsu_data_o),
      .valid(lsu_valid),
      .stall(lsu_stall),

      .data_req(data_req),
      .data_be(data_be),
      .data_wr(data_wr),
      .data_ack(data_ack),
      .data_err(data_err),
      .data_addr(data_addr),
      .data_data_o(data_data_o),
      .data_data_i(data_data_i)
  );

endmodule
