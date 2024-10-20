module ram_dp_handshake #(
    parameter int ADDR_WIDTH = 10,
    parameter int BYTES      =  4,
    parameter int WIDTH      = BYTES * BYTE_WIDTH
) (
    input  bit                  clk,
    input  bit                  clken,

    input  bit                  p0_we,
    input  bit                  p0_re,
    output bit                  p0_ack,
    input  bit [ADDR_WIDTH-1:0] p0_addr,
    input  bit [     BYTES-1:0] p0_be,
    input  bit [     WIDTH-1:0] p0_wdata,
    output bit [     WIDTH-1:0] p0_rdata,

    input  bit                  p1_we,
    input  bit                  p1_re,
    output bit                  p1_ack,
    input  bit [ADDR_WIDTH-1:0] p1_addr,
    input  bit [     BYTES-1:0] p1_be,
    input  bit [     WIDTH-1:0] p1_wdata,
    output bit [     WIDTH-1:0] p1_rdata
);
  localparam int BYTE_WIDTH = 8;
  localparam int WORDS = 1 << ADDR_WIDTH;

  // TODO: Old impl
  // TODO: MAX10 specialization
  // TODO: Compare below and make output register (+1 latency) a parameter
  // TODO: Wire ACK through 
  // TODO: Implement read enable

`ifndef ALTERA_MAX10
  reg [WIDTH-1:0] ram[WORDS];

  always_ff @(posedge clk) begin
      // Port 0: Write Operation
      if (p0_we) begin
          for (int i = 0; i < BYTES; i = i + 1) begin
              if (p0_be[i]) begin
                  ram[p0_addr][i*BYTE_WIDTH+:BYTE_WIDTH] <= p0_wdata[i*BYTE_WIDTH+:BYTE_WIDTH];
              end
          end
      end

      // Port 1: Write Operation
      if (p1_we) begin
          for (int i = 0; i < BYTES; i = i + 1) begin
              if (p1_be[i]) begin
                  ram[p1_addr][i*BYTE_WIDTH+:BYTE_WIDTH] <= p1_wdata[i*BYTE_WIDTH+:BYTE_WIDTH];
              end
          end
      end

      // Port 0: Read Operation
      if (p0_re) begin
          p0_rdata <= ram[p0_addr];
      end

      // Port 1: Read Operation
      if (p1_re) begin
          p1_rdata <= ram[p1_addr];
      end

      // Update acknowledgment signals
      p0_ack <= p0_re | p0_we;
      p1_ack <= p1_re | p1_we;
  end

`else

  altsyncram altsyncram_component (
        .clock0    (clk),
        .clocken0  (clken),
        .address_a (p0_addr),
        .address_b (p0_addr),
        .data_a (p0_wdata),
        .data_b (p1_wdata),
        .wren_a (p0_we),
        .wren_b (p1_we),
        .q_a (p0_rdata),
        .q_b (p1_rdata),
        .aclr0 (1'b0),
        .aclr1 (1'b0),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a (p0_be),
        .byteena_b (p1_be),
        .clock1 (1'b1),
        .clocken1 (1'b1),
        .clocken2 (1'b1),
        .clocken3 (1'b1),
        .eccstatus (),
        .rden_a (p0_re),
        .rden_b (p1_re)
  );
  defparam
    altsyncram_component.address_reg_b = "CLOCK0",
    altsyncram_component.clock_enable_input_a = "NORMAL",
    altsyncram_component.clock_enable_input_b = "NORMAL",
    altsyncram_component.clock_enable_output_a = "BYPASS",
    altsyncram_component.clock_enable_output_b = "BYPASS",
    altsyncram_component.indata_reg_b = "CLOCK0",
    altsyncram_component.intended_device_family = "MAX 10",
    altsyncram_component.lpm_type = "altsyncram",
    altsyncram_component.numwords_a = WORDS,
    altsyncram_component.numwords_b = WORDS,
    altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
    altsyncram_component.outdata_aclr_a = "NONE",
    altsyncram_component.outdata_aclr_b = "NONE",
    altsyncram_component.outdata_reg_a = "UNREGISTERED",
    altsyncram_component.outdata_reg_b = "UNREGISTERED",
    altsyncram_component.power_up_uninitialized = "FALSE",
    altsyncram_component.ram_block_type = "M9K",
    altsyncram_component.read_during_write_mode_mixed_ports = "OLD_DATA",
    altsyncram_component.read_during_write_mode_port_a = "OLD_DATA",
    altsyncram_component.read_during_write_mode_port_b = "OLD_DATA",
    altsyncram_component.widthad_a = ADDR_WIDTH,
    altsyncram_component.widthad_b = ADDR_WIDTH,
    altsyncram_component.width_a = WIDTH,
    altsyncram_component.width_b = WIDTH,
    altsyncram_component.width_byteena_a = BYTES,
    altsyncram_component.width_byteena_b = BYTES,
    altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0";
		// altsyncram_component.init_file = "../hdlib/rv32imc_ss/bootloader.mif",

  always_ff @(posedge clk) begin
      p0_ack <= p0_re | p0_we;
      p1_ack <= p1_re | p1_we;
  end
`endif

endmodule
