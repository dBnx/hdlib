module rv32_mod_branch (
    input  [31:0] rf_read0,
    input  [31:0] rf_read1,
    input  [ 2:0] cond,
    input         is_cond,
    input         is_jmp,
    output        branch_taken
);
  logic cond_statisfied;
  assign branch_taken = is_jmp || (is_cond && cond_statisfied);

  always_comb begin
    case (cond[2:1])
      // TODO: Encoding
      2'b00:  cond_statisfied = cond[0] ^ (rf_read0 == rf_read1);
      2'b10:  cond_statisfied = cond[0] ^ ($signed(rf_read0) < $signed(rf_read1));
      2'b11:  cond_statisfied = cond[0] ^ (rf_read0 < rf_read1);
      default: cond_statisfied = 0;
    endcase
  end

endmodule
