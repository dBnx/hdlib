
module rv32imc_ss_handshake_w_rom #(
    parameter logic [31:0] INITIAL_GP = 32'h10000000,
    parameter logic [31:0] INITIAL_SP = 32'h7ffffff0,
    parameter int ROM_DEPTH32 = 2048,
    parameter logic [8*32-1:0] ROM_FILE = ""
) (
    input clk,
    input reset,

    // Used outside of internal ROM
    output        instr_req,
    input         instr_ack,
    input         instr_err,
    output [31:0] instr_addr,
    input  [31:0] instr_data_i,

    output        data_req,
    input         data_wr,
    input         data_ack,
    input         data_err,
    output [31:0] data_addr,
    output [31:0] data_data_o,
    input  [31:0] data_data_i
);
  logic        instr_req_int;
  wire         instr_ack_int;
  wire         instr_err_int;
  logic [31:0] instr_addr_int;
  logic [31:0] instr_data_i_int;
  
  // localparam bit [31:0] INSTR_NOP = 32'h0000_0013; // ADDI x0, x0, 0
  
  logic instr_internal;
  assign instr_internal = instr_addr_int >= INITIAL_GP && instr_addr_int < (INITIAL_GP + ROM_DEPTH32);

  bit [31:0] rom [ROM_DEPTH32];
  
  // FIXME: Don't register if external <- Should be registered?
  // always_ff @(posedge clk or posedge reset) begin
  always_comb begin
      // if(reset) begin
      //     instr_data_i_int = INSTR_NOP;
      //     instr_ack_int = 0;
      //     instr_err_int = 0;
      // end else begin
          instr_data_i_int = instr_internal ? rom[instr_addr] : instr_data_i;
          instr_ack_int = instr_internal ? 1 : instr_ack;
          instr_err_int = instr_internal ? 0 : instr_err;
      // end
  end

  initial begin
    $readmemh(ROM_FILE, rom);
  end

  rv32imc_ss_handshake #(
        .INITIAL_GP(INITIAL_GP),
        .INITIAL_SP(INITIAL_SP)
  ) inst_hart (
      .clk  (clk),
      .reset(reset),

      .instr_req(instr_req_int),
      .instr_ack(instr_ack_int),
      .instr_err(instr_err_int),
      .instr_addr(instr_addr_int),
      .instr_data_i(instr_data_i_int),

      .data_req(data_req),
      .data_wr(data_wr),
      .data_ack(data_ack),
      .data_err(data_err),
      .data_addr(data_addr),
      .data_data_o(data_data_o),
      .data_data_i(data_data_i)
  );

endmodule
