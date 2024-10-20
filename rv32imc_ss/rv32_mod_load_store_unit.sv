// Every active req issues a new request.
// Requests can be issued unless stall is raised.
// New issues are accepted, while old ones are served.
// Min latency: 1 cycle, as everything is registerd without skid buffers
// Some computation (sign) is done on dext_di, so it may not be stable too
// late in a cycle

// FIXME: Check for unaligned reads and writes
module rv32_mod_load_store_unit (
    input  logic clk,
    input  logic reset,

    // HART interface
    input  logic        req,
    input  logic [ 3:0] req_type,  // [S,U]; Reserved; Size
    input  logic        wr,
    input  logic [31:0] address,
    input  logic [31:0] data_i,
    output logic [31:0] data_o,
    output logic        valid,
    output logic        error,
    output logic        stall,

    // External interface
    output logic        dext_req,
    output logic        dext_wr,
    input  logic        dext_ack,
    input  logic        dext_err,
    output logic [ 3:0] dext_be,
    output logic [31:0] dext_addr,
    output logic [31:0] dext_do,
    input  logic [31:0] dext_di
);

  // The address provided is byte oriented, but we operate an words,
  // so set lower two bits permanently to 0 and shift BE by the offset. 
  // Assume aligned reads / writes.
  bit [ 1:0] be_shift;
  assign be_shift = address[1:0];

  bit [ 3:0] dext_be_comb;
  bit [31:0] dext_di_comb;


  bit       req_signed;
  bit [1:0] req_size;

  bit req_active;
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      req_active <= 0;
    end else begin
      // If there is an active rq, that is terminated and no new rq -> New req is handled only in the next cycle 
      if (req_active && (dext_ack || dext_err)) begin
        req_active <= 0;
      end else if (req) begin
        req_active <= 1;
      end
    end
  end


  // Stalling halts the PC, so only emit if there is an actual request

  bit [31:8] sign;
  bit        sign_16;
  bit        sign_8;
  bit        sign_bit;
  assign sign_16 = be_shift[1] ? dext_di[31] : dext_di[15];
  assign sign = {24{sign_bit}};

  // FIXME: Add handling of unaligned store / loads
  always_comb begin
    // dext_be_comb is registered with the request, so calc from input
    case (req_type[1:0])  // == req_size
      //  8-bit
      2'b00:   dext_be_comb = 1'b1 << be_shift;
      // 16-bit
      2'b01:   dext_be_comb = be_shift[1] ? 4'b1100 : 4'b0011;
      // 32-bit
      2'b10:   dext_be_comb = 4'b1111;
      default: dext_be_comb = 0;
    endcase

    // TODO: Fix timing and use external address?
    case (be_shift)
      2'b00:   sign_8 = dext_di[7];
      2'b01:   sign_8 = dext_di[15];
      2'b10:   sign_8 = dext_di[23];
      2'b11:   sign_8 = dext_di[31];
      default: sign_bit = 0;
    endcase

    case ({
      req_signed, req_size
    })
      3'b101:  sign_bit = sign_8;
      3'b110:  sign_bit = sign_16;
      default: sign_bit = 0;
    endcase

    case (req_size)
      2'b00: begin  // 8b
        case (be_shift)
          2'b00:   dext_di_comb = {sign[31:8], dext_di[7:0]};
          2'b01:   dext_di_comb = {sign[31:8], dext_di[15:8]};
          2'b10:   dext_di_comb = {sign[31:8], dext_di[23:16]};
          2'b11:   dext_di_comb = {sign[31:8], dext_di[31:24]};
          default: dext_di_comb = 0;
        endcase
      end
      2'b01: begin  // 16b
        dext_di_comb = address[1] ? {sign[31:16], dext_di[31:16]} : {sign[31:16], dext_di[31:16]};
      end
      2'b10: begin  // 32b
        dext_di_comb = dext_di;
      end
      default: begin  // 64b (not implemented)
        dext_di_comb = 0;
      end
    endcase
  end

  // assign dext_addr = dext_req ? {address[31:2], 2'h0} : 0;
  // assign dext_addr = {address[31:2], 2'h0};

  // HART Output
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      dext_req <= 0;
      dext_wr <= 0;
      dext_be <= 0;
      dext_do <= 0;
      dext_addr <= 0;

      stall <= 0;
      req_signed <= 0;
      req_size <= 0;
    end else if (!req_active && !req) begin
      // Reset IF only if no active or incomming rq
      dext_req <= 0;
      dext_wr <= 0;
      dext_be <= 0;
      dext_do <= 0;
      dext_addr <= 0;

      stall <= 0;
      req_signed <= 0;
      req_size <= 0;
    end else if (req) begin
      // Hold?
      dext_req  <= 1; // Reset after 1 clock
      dext_wr   <= wr;
      dext_be   <= dext_be_comb;
      // dext_do   <= 0;
      dext_addr <= {address[31:2], 2'h0};

      if (wr) begin
        dext_do <= data_i;
        req_signed <= 0;
        req_size <= 0;
      end else begin
        dext_do <= 0;
        req_signed <= req_type[3];
        req_size <= req_type[1:0];
      end
    end else begin
      dext_req  <= 0; // Reset after 1 clock
    end

    // HART Stall
    if (reset) begin
      stall <= 0;
    end else begin
      stall <= (!dext_ack && !dext_err) && (req || req_active);
    end

    // HART Input
    if (reset) begin
      data_o <= 0;
      valid  <= 0;
      error  <= 0;
    end else if (dext_ack || dext_err) begin
      valid <= dext_ack;
      error <= dext_err;

      if (!wr && dext_ack) begin
        data_o <= dext_di_comb;
      end else begin
        data_o <= 0;
      end
    end else begin
      data_o <= 0;
      valid  <= 0;
      error  <= 0;
    end
  end

endmodule

