/// # Low latency, simple, single-clock domain FIFO
/// ## Features
/// - Sync write
/// - Async read
/// - Supports single cycle push and pop passthrough
/// - Output values are valid within a clock cycle as long as `re` is asserted
/// ## Edge cases
/// - Writes to a full fifo will be discarded
/// - Reads from an empty fifo yield 0
module fifo_simple #(
    parameter int DEPTH = 64,
    parameter int DATA_WIDTH = 8
) (
    // <<< System >>>
    input  logic                  clk,
    input  logic                  rst,
    // <<< Write Port >>>
    input  logic                  we,
    input  logic [DATA_WIDTH-1:0] din,
    // <<< Read Port >>>
    input  logic                  re,
    output logic [DATA_WIDTH-1:0] dout,
    // <<< Status >>>
    output logic [     AdrBits:0] entries,
    output logic                  full,
    output logic                  empty
);

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                               Parameters                              │
  // ╰───────────────────────────────────────────────────────────────────────╯
  // logic  [DATA_WIDTH-1:0]  memory [DEPTH];
  // logic [$clog2(DEPTH):0]  write_ptr, read_ptr;
  // logic [$clog2(DEPTH):0]  count;
  localparam int AdrBits = $clog2(DEPTH);

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                Signals                                │
  // ╰───────────────────────────────────────────────────────────────────────╯
  logic [  AdrBits:0] size, size_next;
  logic [AdrBits-1:0] rd_addr;
  logic [AdrBits-1:0] wr_addr;

  logic               re_granted, we_granted;

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                              Assignments                              │
  // ╰───────────────────────────────────────────────────────────────────────╯
  assign empty = (size == 0);
  assign full = (size == DEPTH[AdrBits:0] - 1);
  // Allowsp pop if true - Either contains some or passthrough mode
  assign re_granted = re && (!empty || we);
  assign we_granted = we && !full;
  assign entries = size;

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                 Logic                                 │
  // ╰───────────────────────────────────────────────────────────────────────╯
  always_comb begin
    case ({
      we, re
    })
      'b01: begin
        if(size == 0) begin
          size_next = 0;
        end else begin
          size_next = size - 1;
        end
      end
      'b10: begin
        if(size == DEPTH[AdrBits:0]-1) begin
          size_next = DEPTH[AdrBits:0]-1;
        end else begin
          size_next = size + 1;
        end
      end
      default: begin
        size_next = size;
      end
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin : handle_addresses
    if (rst) begin
      size <= 0;
      rd_addr <= 0;
      wr_addr <= 0;
    end else begin
      size <= size_next;

      if (re_granted) begin
        rd_addr <= rd_addr + 1;
      end

      // TODO: Test this functionality
      // if (we && (!full || re)) begin
      if (we_granted) begin
        wr_addr <= wr_addr + 1;
      end
    end
  end

  // ╭───────────────────────────────────────────────────────────────────────╮
  // │                                Modules                                │
  // ╰───────────────────────────────────────────────────────────────────────╯
  ram_partial_dp_scd #(
      .DEPTH(DEPTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) ram (
      .clk(clk),
      // Write Port
      .we(we_granted),
      .w_addr(wr_addr),
      .w_data(din),
      // Read Port
      .re(re_granted),
      .r_addr(rd_addr),
      .r_data(dout)
  );
endmodule
