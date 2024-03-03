/// Syn write with async read
module ram_partial_dp_scd #(
  parameter int DEPTH = 64,
  parameter int DATA_WIDTH = 8
) (
  // <<< System >>>
  input  logic                    clk,
  // <<< Write Port >>>
  input  logic                    re,
  input  logic    [(AdrBits-1):0] r_addr,
  output logic [(DATA_WIDTH-1):0] r_data,
  // <<< Read Port >>>
  input  logic                    we,
  input  logic    [(AdrBits-1):0] w_addr,
  input  logic [(DATA_WIDTH-1):0] w_data
);
  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                               Parameters                              │
  // ╰───────────────────────────────────────────────────────────────────────╯
  localparam int AdrBits = $clog2(DEPTH);

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                Signals                                │
  // ╰───────────────────────────────────────────────────────────────────────╯
  logic [(DATA_WIDTH-1):0] ram[DEPTH];

  logic short_circuit;
  assign short_circuit = re == 1 && we == 1 && w_addr == r_addr;

  always_comb begin
    if(re) begin
      r_data = (short_circuit) ? w_data : ram[r_addr];
    end else begin
      r_data = 0;
    end
  end

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                 Logic                                 │
  // ╰───────────────────────────────────────────────────────────────────────╯
  always_ff @(posedge clk)
  begin
    if (we) begin
      ram[w_addr] <= w_data;
    end
  end
endmodule
