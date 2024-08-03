module rv32_mod_instruction_fetch (
    input clk,
    input reset,

    // HART Interface
    input        [31:0] if_address_current,
    input        [31:0] if_address_next,
    output logic [31:0] if_instruction,
    output logic        if_valid,

    // External interface
    output logic        instr_req,
    input               instr_ack,
    input               instr_err,
    output logic [31:0] instr_addr,
    input        [31:0] instr_data_i
);
  /// Must register if_instruction

  localparam bit [31:0] InstrNop = 32'h0000_0013;  // ADDI x0, x0, 0

  // Should be a FIFO with addr tag:
  // Query for cur and then next (?)

  /*
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_instruction <= InstrNop;
      if_valid       <= 0;
    end else begin
      if (instr_ack) begin
        if_instruction <= instr_data_i;
        if_valid       <= 1;
      end else begin
        // Handle instr_err
        if_instruction <= InstrNop;
        if_valid       <= 0;
      end
    end
  end
  */

  // Buffer output req and addr?
  assign instr_addr = if_address_current;
  assign instr_req  = 1;  // FIXME: Only request when necessary

  always_comb begin
    if (instr_ack) begin
      if_instruction = instr_data_i;
      if_valid       = 1;
    end else begin
      // Handle instr_err
      if_instruction = InstrNop;
      if_valid       = 0;
    end
  end


endmodule
