  /*
  rv32_mod_stallington inst_stall (
      .clk  (clk),
      .reset(reset),

      .is_instr_valid(if_valid),
      .is_mem_or_io(is_mem_or_io),
      .is_branch_taken(branch_taken),
      .io_lsu_valid(lsu_valid),
      
      //.(),

      .enable_mut_pc(),
      .enable_mut_rf(),
      .enable_mut_lsu(),
      .enable_mut_if(),
      .enable_mut_csr()
  );

  endmodule

  assign rf_write0_enable = rf_stalled_passthrough ? rf_write0_enable_stalled 
                          : (id_write0_enable && if_valid);

  // assign rf_stalled_passthrough = is_mem_or_io || (rf_stalled_p1 || rf_stalled); // FIXME: Same as lsu_valid
  assign save_stalled = is_mem_or_io && !rf_stalled;

  // wb_source_t           wb_source;
  // assign wb_source = rf_stalled_passthrough ? `WB_SOURCE_LSU : id_wb_source;
  */

module rv32_mod_stallington (
    input  logic clk,
    input  logic reset,

    input  logic is_instr_new,
    input  logic is_mem_or_io,
    input  logic is_branch_taken,
    input  logic io_lsu_valid,

    output logic enable_mut_pc,
    output logic enable_mut_rf,
    // output logic enable_mut_lsu,
    output logic enable_mut_if,
    output logic enable_mut_csr // TODO
);
    logic enable_mut_if_next;

    always_comb begin
        enable_mut_pc = 1'b0;
        enable_mut_rf = 1'b0;
        enable_mut_if_next = 1'b0;
        enable_mut_csr = 1'b0;

        if (reset) begin
            // If reset, disable all mutating signals
            enable_mut_pc = 1'b0;
            enable_mut_rf = 1'b0;
            enable_mut_if_next = 1'b0;
            enable_mut_csr = 1'b0;
        end else begin
            if (is_mem_or_io && io_lsu_valid) begin
                // We can now continue
                enable_mut_rf = 1'b1;
                enable_mut_pc = 1'b1;
                enable_mut_if_next = 1'b1;
            end else if (is_instr_new && !is_mem_or_io) begin
                // Other instructions are single cycle, directly continue
                enable_mut_rf = 1;
                enable_mut_pc = 1;
                enable_mut_if_next = 1;
            end else begin
                // We neither have a new instruction, nor is one of the stall-able units
                // finished.
                enable_mut_rf = 1'b0;
                enable_mut_pc = 1'b0;
                enable_mut_if_next = 1'b0;
            end
        end
    end

    // Needed to:
    // - Break cycle from controller > IF > ID > controller
    // - Creates a delay of 1 cycle after reset
    // - If we fetch an instruction, we can only act on the next one anyway
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            enable_mut_if <= 1;
        end else begin
            enable_mut_if <= enable_mut_if_next;
        end
    end

endmodule
