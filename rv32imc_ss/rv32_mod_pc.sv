module rv32_mod_pc #(
    parameter logic [31:0] INITIAL_GP = 32'h10000000
) (
    input        clk,
    input        reset,

    input         stall,
    input         is_compressed,
    output logic [31:0] pc_current,
    output logic [31:0] pc_next,

    input  [31:0] pc_overwrite_data,
    input         pc_overwrite_enable
);
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_current <= INITIAL_GP;
        end else if(!stall) begin
            if(pc_overwrite_enable) begin
                pc_current <= pc_overwrite_data;
            end else begin
                pc_current <= pc_next;
            end
        end
    end

    always_comb begin
        pc_next = is_compressed ? pc_current + 2 : pc_current + 4;
    end


endmodule