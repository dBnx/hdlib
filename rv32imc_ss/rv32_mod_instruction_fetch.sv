`timescale 1ns / 1ps

module rv32_mod_instruction_fetch (
    input clk,
    input reset,

    // HART Interface
    input  logic        if_enable,
    input  logic [31:0] if_address_current,
    input  logic [31:0] if_address_next,
    output logic [31:0] if_instruction,
    output logic        if_valid,

    // External interface
    output logic        instr_req,
    input  logic        instr_ack,
    input  logic        instr_err,
    output logic [31:0] instr_addr,
    input  logic [31:0] instr_data_i
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

  logic external_valid;
  assign external_valid = instr_ack || !if_enable;

  logic [31:0] instr_buffer;


  // Buffer output req and addr?
  assign instr_addr = if_address_current;
  assign instr_req  = if_enable;

  always_comb begin
    // Output current instr_data
    if (external_valid) begin
      if_instruction = instr_data_i;
      if_valid       = 1;
    end else begin
      // Handle instr_err
      if_instruction = instr_buffer;
      if_valid       = 0; // Should be one or renamed to if_new?
    end
  end

  // Normally we forwarward the external interface directly, but if we have to stall then we save the current
  // Instruction and continue outputting it until the instruction is retired. Basically a skid buffer
  always_ff @(posedge clk or posedge reset) begin
    if(reset) begin
      instr_buffer <= InstrNop;
    end else if(external_valid) begin
      instr_buffer <= instr_data_i;
    end
  end

  initial begin
    instr_buffer = InstrNop;
  end

endmodule
