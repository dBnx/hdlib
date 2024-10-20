`timescale 1ns / 1ps

module rv32_mod_alu (
    input  bit        force_add,
    input  bit [ 6:0] funct7,
    input  bit [ 2:0] funct3,
    input  bit [31:0] read0_data,
    input  bit [31:0] read1_data,
    output bit [31:0] result,
    output bit        error
);
  bit       is_int;
  bit       is_int_alt;
  bit       is_muldiv;
  assign    is_int     = funct7 == 7'b0000000;
  assign    is_int_alt = funct7 == 7'b0100000;
  assign    is_muldiv  = funct7 == 7'b0000001;

  bit [5:0] operation;
  assign    operation = {is_muldiv, is_int_alt, is_int, funct3};

  // Lower three bit are funct3
  `define ALU_OP_INT_ADD  6'b001_000
  `define ALU_OP_INT_SUB  6'b010_000 // ALT_ADD
  `define ALU_OP_INT_SLL  6'b001_001
  `define ALU_OP_INT_SLT  6'b001_010
  `define ALU_OP_INT_SLTU 6'b001_011
  `define ALU_OP_INT_XOR  6'b001_100
  `define ALU_OP_INT_SRL  6'b001_101
  `define ALU_OP_INT_SRA  6'b010_101 // ALT SR
  `define ALU_OP_INT_OR   6'b001_110
  `define ALU_OP_INT_AND  6'b001_111
  // TODO: Fix codes
  `define ALU_OP_MULDIV_MUL    6'b100_000
  `define ALU_OP_MULDIV_MULH   6'b100_001
  `define ALU_OP_MULDIV_MULHSU 6'b100_010
  `define ALU_OP_MULDIV_MULHU  6'b100_011
  `define ALU_OP_MULDIV_DIV    6'b100_100
  `define ALU_OP_MULDIV_DIVU   6'b100_101
  `define ALU_OP_MULDIV_REM    6'b100_110
  `define ALU_OP_MULDIV_REMU   6'b100_111

  // localparam bit [4:0] ALU_OP_MUL = 5'b11_110;

  // localparam bit [4:0] ALU_OP_SETL = 5'b00_000;
  // localparam bit [4:0] ALU_OP_SLLV = 5'b00_000;
  // localparam bit [4:0] ALU_OP_SRLV = 5'b00_000;

  // bit [63:0] result_mulu;
  bit [63:0] result_muls;
  // assign result_mulu = $unsigned(read0_data) * $unsigned(read1_data);
  assign result_muls = $signed(read0_data) * $signed(read1_data);

  always_comb begin
    error = 0;
    // case ({1'b0, func[2:0]}) // Always use default operation
    case (force_add ? `ALU_OP_INT_ADD : operation)  // NOTE: What do to with last bit?
      `ALU_OP_INT_ADD:  result = $signed(read0_data) + $signed(read1_data);
      `ALU_OP_INT_SUB:  result = $signed(read0_data) - $signed(read1_data);
      `ALU_OP_INT_SLL:  result = read0_data << read1_data[4:0];
      `ALU_OP_INT_SLT:  result = {31'h0, $signed(read0_data) < $signed(read1_data)};
      `ALU_OP_INT_SLTU: result = {31'h0, read0_data < read1_data};
      `ALU_OP_INT_XOR:  result = read0_data ^ read1_data;
      `ALU_OP_INT_SRL:  result = read0_data >> read1_data[4:0];
      `ALU_OP_INT_SRA:  result = $signed(read0_data) >>> read1_data[4:0];
      `ALU_OP_INT_OR:   result = read0_data | read1_data;
      `ALU_OP_INT_AND:  result = read0_data & read1_data;

      `ALU_OP_MULDIV_MUL:  result = result_muls[31:0];
      `ALU_OP_MULDIV_MULH: result = result_muls[63:32];
      // `ALU_OP_DIV: result = $signed(read0_data) / $signed(read1_data);
      // `ALU_OP_REM: result = $signed(read0_data) % $signed(read1_data);
      // `ALU_OP_DIVU: result = $unsigned(read0_data) / $unsigned(read1_data);
      // `ALU_OP_REMU: result = $unsigned(read0_data) % $unsigned(read1_data);

      // ALU_OP_SETL: result = {31'h0, read0_data <= read1_data};
      // ALU_OP_MUL: result = read0_data * read1_data;
      default: begin
        result = 32'hXXXX_XXXX;
        error = 1;
      end
    endcase
  end
endmodule
