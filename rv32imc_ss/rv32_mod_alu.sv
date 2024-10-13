`timescale 1ns / 1ps

module rv32_mod_alu (
    input  logic [ 4:0] func,
    input  logic [31:0] read0_data,
    input  logic [31:0] read1_data,
    output logic [31:0] result
);
  logic f_alternate;
  logic [2:0] f_operation;
  assign f_alternate = func[4];
  assign f_operation = func[2:0];


  // Lower three bit are funct3
  `define ALU_OP_ADD 4'b0_000
  `define ALU_OP_SUB 4'b1_000 // ALT_ADD
  `define ALU_OP_SLL 4'b0_001
  `define ALU_OP_SLT 4'b0_010
  `define ALU_OP_SLTU 4'b0_011
  `define ALU_OP_XOR 4'b0_100
  `define ALU_OP_SRL 4'b0_101
  `define ALU_OP_SRA 4'b1_101 // ALT SR
  `define ALU_OP_OR 4'b0_110
  `define ALU_OP_AND 4'b0_111

  // localparam bit [4:0] ALU_OP_MUL = 5'b11_110;

  // localparam bit [4:0] ALU_OP_SETL = 5'b00_000;
  // localparam bit [4:0] ALU_OP_SLLV = 5'b00_000;
  // localparam bit [4:0] ALU_OP_SRLV = 5'b00_000;

  always_comb begin
    // case ({1'b0, func[2:0]}) // Always use default operation
    case (func[3:0])  // NOTE: What do to with last bit?
      `ALU_OP_ADD: result = $signed(read0_data) + $signed(read1_data);
      `ALU_OP_SUB: result = $signed(read0_data) - $signed(read1_data);
      `ALU_OP_SLL: result = read0_data << read1_data[4:0];
      `ALU_OP_SLT: result = {31'h0, $signed(read0_data) < $signed(read1_data)};
      `ALU_OP_SLTU: result = {31'h0, read0_data < read1_data};
      `ALU_OP_XOR: result = read0_data ^ read1_data;
      `ALU_OP_SRL: result = read0_data >> read1_data[4:0];
      `ALU_OP_SRA: result = $signed(read0_data) >>> read1_data[4:0];
      `ALU_OP_OR: result = read0_data | read1_data;
      `ALU_OP_AND: result = read0_data & read1_data;
      // ALU_OP_SETL: result = {31'h0, read0_data <= read1_data};
      // ALU_OP_MUL: result = read0_data * read1_data;
      default: result = read0_data;
    endcase
  end
endmodule
