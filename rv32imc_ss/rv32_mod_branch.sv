module rv32_mod_branch #(
    // parameter logic ASYNC_READ = 1
) (
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
    casex (cond[1:0])
      // TODO: Encoding
      3'bX01:  cond_statisfied = cond[2] ^ (rf_read0 > rf_read1);
      3'bX10:  cond_statisfied = cond[2] ^ (rf_read0 == rf_read1);
      3'bX11:  cond_statisfied = cond[2] ^ (rf_read0 < rf_read1);
      default: cond_statisfied = 0;
    endcase
  end

endmodule
