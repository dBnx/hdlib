
module rv32_mod_alu #(
    // parameter logic ASYNC_READ = 1
) (
    // For complex instructions
    // input         clk,
    // output        stall

    input [4:0] func,
    input [31:0] read0_data,
    input [31:0] read1_data,
    output logic [31:0] result
);

  
  // Lower three bit are funct3
  localparam bit [4:0] ALU_OP_ADD  = 5'b00_000;
  localparam bit [4:0] ALU_OP_SUB  = 5'b01_000;
  localparam bit [4:0] ALU_OP_SLL  = 5'b00_001;
  localparam bit [4:0] ALU_OP_SLT  = 5'b00_010;
  localparam bit [4:0] ALU_OP_SLTU = 5'b00_010;
  localparam bit [4:0] ALU_OP_XOR  = 5'b00_100;
  localparam bit [4:0] ALU_OP_SRL  = 5'b00_101;
  localparam bit [4:0] ALU_OP_SRA  = 5'b01_101;
  localparam bit [4:0] ALU_OP_OR   = 5'b00_110;
  localparam bit [4:0] ALU_OP_AND  = 5'b00_111;

  // localparam bit [4:0] ALU_OP_MUL = 5'b11_110;

  // localparam bit [4:0] ALU_OP_SETL = 5'b00_000;
  // localparam bit [4:0] ALU_OP_SLLV = 5'b00_000;
  // localparam bit [4:0] ALU_OP_SRLV = 5'b00_000;

  always_comb begin
    case (func)
      ALU_OP_ADD: result = read0_data + read1_data;
      ALU_OP_SUB: result = read0_data - read1_data;
      ALU_OP_AND: result = read0_data & read1_data;
      ALU_OP_OR:  result = read0_data | read1_data;
      ALU_OP_XOR: result = read0_data ^ read1_data;

      ALU_OP_SLL: result = read0_data << read1_data[4:0];
      ALU_OP_SRL: result = read0_data >> read1_data[4:0];
      ALU_OP_SLT:  result = {31'h0, read0_data < read1_data};
      // ALU_OP_SETL: result = {31'h0, read0_data <= read1_data};

      // ALU_OP_MUL: result = read0_data * read1_data;

      // NOP
      default: result = read0_data;
    endcase
    ;
  end
endmodule
