module rv32_mod_instruction_decoder_imm (
    input [31:0] instruction,
    input [ 5:0] instruction_format,


    output [31:0] immediate
);
  bit is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j;
  assign {is_i_type, is_s_type, is_s_subtype_b, is_u_type, is_u_subtype_j} = instruction_format[4:0];

  // Different fragments used to create it. Numbers represent bit ranges.
  bit [10:0] imm_30_20;
  bit [ 5:0] imm_30_25;
  bit [ 3:0] imm_24_21;
  bit [ 7:0] imm_19_12;
  bit [ 3:0] imm_11_8;
  bit [ 0:0] imm_20;
  bit [ 0:0] imm_7;
  assign imm_30_20 = instruction[30:20];
  assign imm_30_25 = instruction[30:25];
  assign imm_24_21 = instruction[24:21];
  assign imm_19_12 = instruction[19:12];
  assign imm_11_8 = instruction[11:8];
  assign imm_20 = instruction[20];
  assign imm_7 = instruction[7];

  // Sign extension
  bit [31:12] sign = {20{instruction[31]}};
  // Construction
  assign immediate[0] = is_i_type ? imm_20 : (is_s_type && !is_s_subtype_b) ? imm_7 : 0;
  assign immediate[4:1] = is_i_type || is_u_subtype_j ? imm_24_21 : is_u_type ? 0 : imm_11_8;
  assign immediate[10:5] = is_u_type && !is_u_subtype_j ? 0 : imm_30_25;
  assign immediate[11] = is_u_type ? 0 : is_s_subtype_b ? imm_7 : is_u_subtype_j ? imm_20 : sign[31];
  assign immediate[19:12] = is_u_type ? imm_19_12 : sign[19:12];
  assign immediate[30:20] = is_u_type && !is_u_subtype_j ? imm_30_20 : sign[30:20];
  assign immediate[31] = instruction[31];
endmodule
