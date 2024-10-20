// `define TOP_LEVEL // Top level of a single cycle RISC-V32 processor

// `include "rv32imc_ss/rv32_mod_instruction_decoder.sv"
// `include "rv32imc_ss/rv32_mod_instruction_decoder_func.sv"
// `include "rv32imc_ss/rv32_mod_registerfile.sv"
// `include "rv32imc_ss/rv32_mod_alu.sv"

`define WB_SOURCE_ALU 0
`define WB_SOURCE_PC  1
`define WB_SOURCE_LSU 2
`define WB_SOURCE_CSR 3

`define BR_COND_NOP 0
`define BR_COND_EQ  1
`define BR_COND_NE  2
`define BR_COND_GT  3
`define BR_COND_GE  4
`define BR_COND_LT  5
`define BR_COND_LE  6

module rv32imc_ss_handshake #(
    parameter bit [31:0] INITIAL_PC = 32'h10000000,
    parameter bit [31:0] INITIAL_GP = 32'h80000000,
    parameter bit [31:0] INITIAL_SP = 32'h7FFFFFF0,

    parameter bit [31:0] INITIAL_MTVEC   = 32'h00010000,
    parameter bit [31:0] INITIAL_MSTATUS = 32'h00000080,
    parameter bit [31:0] MVENDOR_ID      = 32'h00000000,
    parameter bit [31:0] MARCH_ID        = 32'h00000000,
    parameter bit [31:0] MIMP_ID         = 32'h00000000,
    parameter bit [31:0] MHART_ID        = 32'h00000000
    // parameter bit [31:0] INITIAL_MTVEC = INITIAL_GP & 1, // 32'h10000000,
) (
    input  bit        clk,
    input  bit        reset,

    output bit        instr_req,
    input  bit        instr_ack,
    input  bit        instr_err,
    output bit [31:0] instr_addr,
    input  bit [31:0] instr_data_i,

    output bit        data_req,
    output bit        data_wr,
    input  bit        data_ack,
    input  bit        data_err,
    output bit [ 3:0] data_be,
    output bit [31:0] data_addr,
    output bit [31:0] data_data_o,
    input  bit [31:0] data_data_i
);

  // Instruction Fetcher -----------------------------------------------------
  // bit [31:0] if_address;
  bit [31:0] if_instruction;
  bit        if_valid;
  bit        if_instr_req;
  assign instr_req = if_instr_req;
  // assign if_address = pc_current;

  // Program Counter ( global pointer ) --------------------------------------
  // bit        global_stall;
  bit [31:0] pc_current;
  bit [31:0] pc_next;

  bit [31:0] pc_overwrite_data;
  bit        pc_overwrite_enable;
  assign pc_overwrite_data = trap_taken ? csr_trap_handler_addr : alu_result;
  assign pc_overwrite_enable = branch_taken || trap_taken;

  // Register File -----------------------------------------------------------
  bit        rf_target_is_x0;
  bit        rf_source_is_x0;
  bit        rf_write0_enable;
  bit [ 4:0] rf_write0_index;
  bit [31:0] rf_read0_data, rf_read1_data, rf_write0_data;
  assign rf_write0_enable = enable_mut_rf ? id_write0_enable : 0;
  assign rf_write0_index = id_write0_index;

  always_comb begin
    case (wb_source)
      // TODO: Move encoding inside instr decode (?)
      `WB_SOURCE_ALU: rf_write0_data = alu_result;
      `WB_SOURCE_PC:  rf_write0_data = pc_next;  // To register must be next
      `WB_SOURCE_LSU: rf_write0_data = lsu_data_o;
      `WB_SOURCE_CSR: rf_write0_data = csr_data_o;
      default: rf_write0_data = 0;
    endcase
  end

  // Instruction Decoder -----------------------------------------------------
  bit                 id_write0_enable;
  bit          [ 4:0] rf_read0_index, rf_read1_index, id_write0_index;
  bit          [31:0] immediate;
  bit          [ 5:0] func;
  bit                 is_mem_or_io;
  bit                 is_system;
  bit                 is_compressed;
  bit                 id_error_0, id_error_1;
  bit                 id_error;

  bit                 id_sys_jump_to_m;
  bit                 id_sys_ret_from_priv;


  bit                 alu_op0_use_pc;
  bit                 alu_op1_use_imm;
  bit                 alu_force_add;
  bit          [ 2:0] alu_funct3;
  bit          [ 6:0] alu_funct7;
  bit          [ 3:0] lsu_req_type;
  bit                 lsu_wr;
  bit                 lsu_req;
  wb_source_t         id_wb_source;
  br_condition_t      br_cond;
  bit                 br_is_cond;
  bit                 br_is_jmp;
  assign id_error = id_error_0 || id_error_1; // TODO: Use

  bit          [ 5:0] id_instruction_format;
  assign lsu_req = is_mem_or_io && !lsu_req_suppressor;

  bit lsu_req_suppressor;
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
  bit [31:0] alu_read0_data, alu_read1_data;
  bit [31:0] alu_result;
  bit        alu_error; // TODO
  assign     alu_read0_data = alu_op0_use_pc ? pc_current : rf_read0_data;
  assign     alu_read1_data = alu_op1_use_imm ? immediate : rf_read1_data;

  // Branching Module --------------------------------------------------------
  bit        branch_taken;

  // Load Store Unit ---------------------------------------------------------
  bit [31:0] lsu_address;
  bit [31:0] lsu_data_o;
  bit        lsu_valid, lsu_error; // TODO: lsu_error not connected
  bit        lsu_stall;
  assign     lsu_address = alu_result;

  wb_source_t wb_source;
  assign      wb_source = id_wb_source;

  // CSRs --------------------------------------------------------------------
    bit [31:0] csr_mstatus;
    bit [31:0] csr_mepc;
    bit [31:0] csr_mtval;
    bit [31:0] csr_mtvec;
    bit [31:0] csr_mcause;


  // - [x] Set jump location - not vectored
  // - [x] Set mepc
  // - [-] Set mcause
  // - [-] Set mtval

    // TODO: In own module
    // TODO: Handle vectored

  // Stall Controller --------------------------------------------------------
  bit enable_mut_pc;
  bit enable_mut_rf;
  // bit enable_mut_lsu; // DOME
  bit enable_mut_if;
  bit enable_mut_csr; // TODO

  // Instantiations ----------------------------------------------------------
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
      .instruction       (if_instruction),
      .priviledge        (priviledge),

      .funct3            (alu_funct3),
      .funct7            (alu_funct7),

      .sys_jump_to_m     (id_sys_jump_to_m),
      .sys_ret_from_priv (id_sys_ret_from_priv),

      .rf_target_is_x0   (rf_target_is_x0),
      .rf_source_is_x0   (rf_source_is_x0),
      .rf_read0_index    (rf_read0_index),
      .rf_read1_index    (rf_read1_index),
      .rf_write0_index   (id_write0_index),
      .instruction_format(id_instruction_format),
      .func              (func),
      .is_mem_or_io      (is_mem_or_io),
      .is_system         (is_system),
      .is_compressed     (is_compressed),
      .error             (id_error_0)
  );

  rv32_mod_instruction_decoder_func inst_instr_dec_func (
      .instruction_format(id_instruction_format),
      .func              (func),
      .is_mem_or_io      (is_mem_or_io),
      .is_system         (is_system),
      .rf_target_is_x0   (rf_target_is_x0),
      .rf_source_is_x0   (rf_source_is_x0),

      .rf_write0_enable  (id_write0_enable),
      .alu_op0_use_pc    (alu_op0_use_pc),
      .alu_op1_use_imm   (alu_op1_use_imm),
      .alu_force_add     (alu_force_add),
      .ram_req           (lsu_req_type),
      .ram_wr            (lsu_wr),
      .csr_wr            (csr_wr),
      .csr_rd            (csr_rd),
      .csr_bit_op        (csr_bit_op),
      .csr_bit_set_or_clr(csr_bit_set_or_clr),
      .csr_use_imm       (csr_use_imm),
      .wb_source         (id_wb_source),
      .br_cond           (br_cond),
      .br_is_cond        (br_is_cond),
      .br_jmp            (br_is_jmp),
      .error             (id_error_1)
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
      .force_add (alu_force_add),
      .funct3    (alu_funct3),
      .funct7    (alu_funct7),
      .read0_data(alu_read0_data),
      .read1_data(alu_read1_data),
      .result    (alu_result),
      .error     (alu_error)
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

    // TODO: Finish:
    //       - Sync exceptions
    //       - Interrupts

    // Currently only machine mode is supported
    bit [ 1:0] priviledge = 2'b11;

    bit        csr_bit_op;
    bit        csr_bit_set_or_clr;
    bit        csr_use_imm;
    bit        csr_wr;
    bit        csr_rd;
    bit        csr_error; // TODO
    bit [11:0] csr_addr;
    bit [31:0] csr_data_i;
    bit [31:0] csr_data_o;
    assign csr_data_i = csr_bit_op ? csr_data_i_bitmanip : rf_read0_data; // TODO: Check
    assign csr_addr = immediate[11:0]; // TODO: This should work ..
    // assign csr_addr = if_instruction[31:20];

    // Local
    bit [ 3:0] csr_bit_shift;
    bit [31:0] csr_data_i_bitmanip;
    bit [31:0] csr_bitmask;
    bit [31:0] csr_bitmask_inversion;
    assign csr_bit_shift = csr_use_imm ? rf_read0_index[3:0] : rf_read0_data[3:0];
    // Set or reset bits based on csr_bit_set 
    assign csr_bitmask_inversion = {32{csr_bit_set_or_clr}};
    assign csr_bitmask = (1 << csr_bit_shift) ^ csr_bitmask_inversion;
    assign csr_data_i_bitmanip = csr_data_o & csr_bitmask;

    bit instruction_retired;
    assign instruction_retired = enable_mut_pc; // TODO: Verify

    bit exception_instr_addr_misaligned;
    assign exception_instr_addr_misaligned = pc_next[1:0] != 2'b00;

    bit exception_illegal_instruction;
    assign exception_illegal_instruction = id_error;

    bit trap_taken;
    bit [31:0] csr_trap_handler_addr;

    rv32_mod_csrs #(
        .INITIAL_MTVEC  (INITIAL_MTVEC  ),
        .INITIAL_MSTATUS(INITIAL_MSTATUS),
        .MVENDOR_ID     (MVENDOR_ID     ),
        .MARCH_ID       (MARCH_ID       ),
        .MIMP_ID        (MIMP_ID        ),
        .MHART_ID       (MHART_ID       )
    ) inst_csrs (
        .clk       (clk),
        .reset     (reset),
        .priviledge(priviledge),
        .instruction_retired(instruction_retired),

        // <<<< Register file I/O >>>>
        .wr    (csr_wr),     // input logic wr,
        .rd    (csr_rd),     // input logic rd,
        .error (csr_error),  // output logic error,
        .addr  (csr_addr), // input  logic [11:0] addr,
        .data_i(csr_data_i), // input  logic [31:0] data_i,
        .data_o(csr_data_o), // output logic [31:0] data_o, // registered

        // TODO: Everything else :)
        // <<<< TRAPS >>>>
        .sys_jump_to_m     (id_sys_jump_to_m),
        .sys_ret_from_priv (id_sys_ret_from_priv),

        .mip_new(), // input  logic [31:0] mip_new,
        .mip_cur(), // output logic [31:0] mip_cur,

        .interrupts         (), // input  logic [5:0] interrupts,
        .trap_handler_clear (), // input  logic trap_handler_clear,
        .trap_handler_active(), // output logic trap_handler_active,

        // Explicit exception causes
        .exception_instr_addr_misaligned(exception_instr_addr_misaligned),
        .exception_instr_access_fault   (1'b0), // input logic exception_instr_access_fault,
        .exception_illegal_instruction  (exception_illegal_instruction),
        .exception_breakpoint           (1'b0), // input logic exception_breakpoint,
        .exception_load_addr_misaligned (1'b0), // input logic exception_load_addr_misaligned,
        .exception_load_access_fault    (instr_err),
        .exception_store_addr_misaligned(1'b0), // input logic exception_store_addr_misaligned,
        .exception_store_access_fault   (data_err),
        .exception_ecall_from_u_mode    (1'b0), // input logic exception_ecall_from_u_mode,
        .exception_ecall_from_s_mode    (1'b0), // input logic exception_ecall_from_s_mode,
        .exception_ecall_from_m_mode    (id_sys_jump_to_m),
        .exception_instr_page_fault     (1'b0), // input logic exception_instr_page_fault,
        .exception_load_page_fault      (1'b0), // input logic exception_load_page_fault,
        .exception_store_page_fault     (1'b0), // input logic exception_store_page_fault,

        // New signals for assigning to csr_mepc and csr_mtval
        .pc_current          (pc_current),
        .pc_next             (pc_next),
        .faulting_address    (), // input logic [31:0] faulting_address, // TODO
        .faulting_instruction(if_instruction), // input logic [31:0] faulting_instruction,

        .serve_trap       (trap_taken), // output logic serve_trap, // registered
        .trap_handler_addr(csr_trap_handler_addr),

        // <<<< CSRs direct access >>>>
        .mstatus(csr_mstatus), // output logic [31:0] mstatus,
        .mepc   (csr_mepc), // output logic [31:0] mepc,
        .mtval  (csr_mtval), // output logic [31:0] mtval,
        .mtvec  (csr_mtvec), // output logic [31:0] mtvec,
        // Machine Interrupt Pending
        .mip    (), // output logic [31:0] mip,
        // Machine Interrupt Enable
        .mie    () // output logic [31:0] mie
        // output logic [31:0] mscratch,
        // output logic [31:0] mtime,
        // output logic [31:0] mcycle
    );

endmodule
