// `define TOP_LEVEL // Top level of a single cycle RISC-V32 processor

// `include "rv32imc_ss/rv32_mod_instruction_decoder.sv"
// `include "rv32imc_ss/rv32_mod_instruction_decoder_func.sv"
// `include "rv32imc_ss/rv32_mod_registerfile.sv"
// `include "rv32imc_ss/rv32_mod_alu.sv"

`define WB_SOURCE_ALU 0
`define WB_SOURCE_PC 1
`define WB_SOURCE_LSU 2


`define BR_COND_NOP 0
`define BR_COND_EQ 1
`define BR_COND_NE 2
`define BR_COND_GT 3
`define BR_COND_GE 4
`define BR_COND_LT 5
`define BR_COND_LE 6

module rv32imc_ss_handshake #(
    parameter logic [31:0] INITIAL_PC = 32'h10000000,
    parameter logic [31:0] INITIAL_GP = 32'h80000000,
    parameter logic [31:0] INITIAL_SP = 32'h7FFFFFF0,

    parameter logic [31:0] INITIAL_MTVEC   = 32'h00010000,
    parameter logic [31:0] INITIAL_MSTATUS = 32'h00000080,
    parameter logic [31:0] MVENDOR_ID      = 32'h00000000,
    parameter logic [31:0] MARCH_ID        = 32'h00000000,
    parameter logic [31:0] MIMP_ID         = 32'h00000000,
    parameter logic [31:0] MHART_ID        = 32'h00000000
    // parameter logic [31:0] INITIAL_MTVEC = INITIAL_GP & 1, // 32'h10000000,
) (
    input logic clk,
    input logic reset,

    output logic        instr_req,
    input  logic        instr_ack,
    input  logic        instr_err,
    output logic [31:0] instr_addr,
    input  logic [31:0] instr_data_i,

    output logic        data_req,
    output logic        data_wr,
    input  logic        data_ack,
    input  logic        data_err,
    output logic [ 3:0] data_be,
    output logic [31:0] data_addr,
    output logic [31:0] data_data_o,
    input  logic [31:0] data_data_i
);

  // Instruction Fetcher -----------------------------------------------------
  // logic [31:0] if_address;
  logic [31:0] if_instruction;
  logic        if_valid;
  logic        if_instr_req;
  assign instr_req = if_instr_req;
  // assign if_address = pc_current;

  // Program Counter ( global pointer ) --------------------------------------
  // logic        global_stall;
  logic [31:0] pc_current;
  logic [31:0] pc_next;

  logic [31:0] pc_overwrite_data;
  logic        pc_overwrite_enable;
  assign pc_overwrite_data = alu_result;
  assign pc_overwrite_enable = branch_taken;

  // Register File -----------------------------------------------------------
  logic        rf_write0_enable;
  logic [ 4:0] rf_write0_index;
  logic [31:0] rf_read0_data, rf_read1_data, rf_write0_data;
  assign rf_write0_enable = enable_mut_rf ? id_write0_enable : 0;
  assign rf_write0_index = id_write0_index;

  always_comb begin
    case (wb_source)
      // TODO: Move encoding inside instr decode (?)
      `WB_SOURCE_ALU: rf_write0_data = alu_result;
      `WB_SOURCE_PC: rf_write0_data = pc_next;  // To register must be next
      `WB_SOURCE_LSU: rf_write0_data = lsu_data_o;
      default: rf_write0_data = 0;
    endcase
  end

  // Instruction Decoder -----------------------------------------------------
  logic                 id_write0_enable;
  logic          [ 4:0] rf_read0_index, rf_read1_index, id_write0_index;
  logic          [31:0] immediate;
  logic          [ 5:0] func;
  logic                 is_mem_or_io;
  logic                 is_compressed;

  logic                 alu_op0_use_pc;
  logic                 alu_op1_use_imm;
  logic          [ 4:0] alu_func;
  logic          [ 3:0] lsu_req_type;
  logic                 lsu_wr;
  logic                 lsu_req;
  wb_source_t           id_wb_source;
  br_condition_t        br_cond;
  logic                 br_is_cond;
  logic                 br_is_jmp;

  // logic                 is_nop;
  // assign                is_nop = 0; // TODO

  logic          [ 5:0] id_instruction_format;
  assign lsu_req = is_mem_or_io && !lsu_req_suppressor;

  logic lsu_req_suppressor;
  always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
          lsu_req_suppressor <= 0;
      end else if(lsu_valid) begin
          // If we don't reset after we detect the end of a load or store, then
          // we suppress the next instruction if it's also a load or store.
          lsu_req_suppressor <= 0;
      end else if(if_valid) begin
          lsu_req_suppressor <= is_mem_or_io;
      end
  end

  // ALU ---------------------------------------------------------------------
  logic [31:0] alu_read0_data, alu_read1_data;
  logic [31:0] alu_result;
  assign alu_read0_data = alu_op0_use_pc ? pc_current : rf_read0_data;
  assign alu_read1_data = alu_op1_use_imm ? immediate : rf_read1_data;

  // Branching Module --------------------------------------------------------
  logic        branch_taken;

  // Load Store Unit ---------------------------------------------------------
  logic [31:0] lsu_address;
  logic [31:0] lsu_data_o;
  logic        lsu_valid, lsu_error; // TODO: lsu_error not connected
  logic        lsu_stall;
  assign lsu_address = alu_result;

  wb_source_t           wb_source;
  assign wb_source = id_wb_source;

  // - Resolve stalled write
  // - TODO: ID must hold values until stall is resolved
  // - TODO: Replace *_stalled variants with a stall_lsu and stall_* variants.
  // logic       rf_stalled, rf_stalled_p1, rf_stalled_passthrough;
  // logic       rf_write0_enable_stalled;
  // logic [4:0] rf_write0_index_stalled;
  // assign rf_stalled_passthrough = is_mem_or_io || (rf_stalled_p1 || rf_stalled); // FIXME: Same as lsu_valid

  // logic save_stalled;
  // assign save_stalled = is_mem_or_io && !rf_stalled;

  // assign wb_source = rf_stalled_passthrough ? `WB_SOURCE_LSU : id_wb_source;

    /*
  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
        rf_stalled <= 0;
        rf_write0_enable_stalled <= 0;
        rf_write0_index_stalled <= 0;
    end else if (lsu_valid) begin
        rf_stalled <= 0;
        rf_write0_enable_stalled <= 0;
        rf_write0_index_stalled <= 0;
    end else if(save_stalled) begin
        rf_stalled <= 1;
        rf_write0_enable_stalled <= id_write0_enable;
        rf_write0_index_stalled <= id_write0_index;
    end

    rf_stalled_p1 <= rf_stalled;
  end
  */

  // Stall Controller --------------------------------------------------------

  logic enable_mut_pc;
  logic enable_mut_rf;
  // logic enable_mut_lsu; // DOME
  logic enable_mut_if;
  logic enable_mut_csr; // TODO

  rv32_mod_stallington inst_stall (
      .clk  (clk  ),
      .reset(reset),

      .is_instr_new   (if_valid    ),
      .is_mem_or_io   (is_mem_or_io),
      .is_branch_taken(branch_taken),
      .io_lsu_valid   (lsu_valid   ),

      .enable_mut_pc (enable_mut_pc ),
      .enable_mut_rf (enable_mut_rf ),
      // .enable_mut_lsu(enable_mut_lsu),
      .enable_mut_if (enable_mut_if ),
      .enable_mut_csr(enable_mut_csr)
  );

  rv32_mod_instruction_fetch inst_if (
      .clk  (clk),
      .reset(reset),

      .if_enable         (enable_mut_if),
      .if_address_current(pc_current),
      .if_address_next   (pc_next),
      .if_instruction    (if_instruction),
      .if_valid          (if_valid),

      // External Interface
      .instr_req   (if_instr_req),
      .instr_ack   (instr_ack),
      .instr_err   (instr_err),
      .instr_addr  (instr_addr),
      .instr_data_i(instr_data_i)
  );

  rv32_mod_pc #(
        .INITIAL_PC(INITIAL_PC)
  ) inst_pc (
      .clk  (clk),
      .reset(reset),

      .stall        (!enable_mut_pc),
      .is_compressed(is_compressed),
      .pc_current   (pc_current),
      .pc_next      (pc_next),

      .pc_overwrite_data  (pc_overwrite_data),
      .pc_overwrite_enable(pc_overwrite_enable)
  );

  rv32_mod_instruction_decoder inst_instr_dec (
      .instruction(if_instruction),

      .rf_read0_index    (rf_read0_index),
      .rf_read1_index    (rf_read1_index),
      .rf_write0_index   (id_write0_index),
      .instruction_format(id_instruction_format),
      .func              (func),
      .is_mem_or_io      (is_mem_or_io),
      .is_compressed     (is_compressed)
  );

  rv32_mod_instruction_decoder_func inst_instr_dec_func (
      .instruction_format(id_instruction_format),
      .func              (func),
      .is_mem_or_io      (is_mem_or_io),

      .rf_write0_enable(id_write0_enable),
      .alu_op0_use_pc  (alu_op0_use_pc),
      .alu_op1_use_imm (alu_op1_use_imm),
      .alu_func        (alu_func),
      .ram_req         (lsu_req_type),
      .ram_wr          (lsu_wr),
      .wb_source       (id_wb_source),
      .br_cond         (br_cond),
      .br_is_cond      (br_is_cond),
      .br_jmp          (br_is_jmp)
  );

  rv32_mod_instruction_decoder_imm inst_instr_dec_imm (
      .instruction       (if_instruction),
      .instruction_format(id_instruction_format),
      .immediate         (immediate)
  );

  rv32_mod_registerfile #(
        .INITIAL_GP(INITIAL_GP),
        .INITIAL_SP(INITIAL_SP)
  ) inst_registerfile (
      .clk  (clk),
      .reset(reset), // DOME

      .read0_index  (rf_read0_index),
      .read0_data   (rf_read0_data),
      .read1_index  (rf_read1_index),
      .read1_data   (rf_read1_data),
      .write0_index (rf_write0_index),
      .write0_data  (rf_write0_data),
      .write0_enable(rf_write0_enable)
  );

  rv32_mod_alu inst_alu (
      .func      (alu_func),
      .read0_data(alu_read0_data),
      .read1_data(alu_read1_data),
      .result    (alu_result)
  );

  rv32_mod_branch inst_branch (
      .rf_read0    (rf_read0_data),
      .rf_read1    (rf_read1_data),
      .cond        (br_cond),
      .is_cond     (br_is_cond),
      .is_jmp      (br_is_jmp),
      .branch_taken(branch_taken)
  );

  rv32_mod_load_store_unit inst_lsu (
      .clk  (clk),
      .reset(reset),

      .req     (lsu_req),
      .wr      (lsu_wr),
      .req_type(lsu_req_type),
      .address (lsu_address),
      .data_i  (rf_read1_data),
      .data_o  (lsu_data_o),
      .valid   (lsu_valid),
      .error   (lsu_error),
      .stall   (lsu_stall),

      .dext_req (data_req),
      .dext_be  (data_be),
      .dext_wr  (data_wr),
      .dext_ack (data_ack),
      .dext_err (data_err),
      .dext_addr(data_addr),
      .dext_do  (data_data_o),
      .dext_di  (data_data_i)
  );

  // TODO: Inst CSR
  // .INITIAL_MTVEC  (INITIAL_MTVEC   ),
  // .INITIAL_MSTATUS(INITIAL_MSTATUS ),
  // .MVENDOR_ID     (MVENDOR_ID      ),
  // .MARCH_ID       (MARCH_ID        ),
  // .MIMP_ID        (MIMP_ID         ),
  // .MHART_ID       (MHART_ID        )
endmodule
