/// Syn write with async read
module lru_tracker #(
  parameter int N = 3
) (
  // <<< System >>>
  input  logic                    clk,
  input  logic                    rst,
  // <<< IO >>>
  input  logic                    en,
  input  logic                    active,
  output logic                    lru
);
  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                Signals                                │
  // ╰───────────────────────────────────────────────────────────────────────╯
  logic            [N-1:0] ctr;
  logic            [N-1:0] ctr_next;

  assign lru = ctr == 0;

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                 Logic                                 │
  // ╰───────────────────────────────────────────────────────────────────────╯
  always_ff @(posedge clk or posedge rst)
  begin
    if (rst) begin
      ctr <= 0;
    end else begin
      ctr <= ctr_next;
    end
  end

  always_comb begin
    if(~en) begin
      ctr_next = ctr;
    end else if(active) begin
      ctr_next = -1;
    end else begin
      ctr_next = ctr - 1;
    end
  end
endmodule
