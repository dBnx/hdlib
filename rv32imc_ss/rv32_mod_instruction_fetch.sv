module rv32_mod_instruction_fetch #(
    // parameter logic [31:0] INITIAL_GP = 32'h10000000
) (
    input clk,
    input reset,

    // HART Interface
    input        [31:0] if_address,
    output logic [31:0] if_instruction,
    output logic        if_valid,

    // External interface
    output        instr_req,
    input         instr_ack,
    input         instr_err,
    output [31:0] instr_addr,
    input  [31:0] instr_data_i
);

  localparam bit [31:0] InstrNop = 32'h0000_0013;  // ADDI x0, x0, 0

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

  // Buffer output req and addr?
  assign instr_addr = if_address;
  assign instr_req  = 1;  // FIXME: Only request when necessary

endmodule
