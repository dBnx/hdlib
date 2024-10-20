module rom_dp_handshake #(
    parameter bit REGISTERED_READ = 0,
    parameter int ADDR_WIDTH = 9,
    parameter int BYTES      = 4,
`ifndef ALTERA_MAX10
    parameter string ROM_FILE = ""
`else
    parameter ROM_FILE = ""
`endif
) (
    input  bit                  clk,
    input  bit                  clken,

    input  bit                  p0_re,
    output bit                  p0_ack,
    input  bit [ADDR_WIDTH-1:0] p0_addr,
    output bit [     WIDTH-1:0] p0_rdata,

    input  bit                  p1_re,
    output bit                  p1_ack,
    input  bit [ADDR_WIDTH-1:0] p1_addr,
    output bit [     WIDTH-1:0] p1_rdata
);
  localparam int BYTE_WIDTH = 8;
  localparam int WIDTH      = BYTES * BYTE_WIDTH,
  localparam int WORDS = 1 << ADDR_WIDTH;

  // TODO: Old impl
  // TODO: MAX10 specialization

  bit   [WIDTH-1:0] rom [WORDS];
  initial begin
	$readmemh(ROM_FILE, rom);
  end

  generate
  if(!REGISTERED_READ) begin : gen_sync_read
	// Async read requires rom map in all cases. Just assign to output:
	assign p0_ack = p0_re;
	assign p1_ack = p1_re;
	assign p0_rdata = rom[p0_addr];
	assign p1_rdata = rom[p1_addr];
  end else begin : gen_async_read
	`ifndef ALTERA_MAX10
		// Registered read reference implementation:
		always_ff @(posedge clk) begin
			p0_rdata <= rom[p0_addr];
			p1_rdata <= rom[p1_addr];
			p0_ack <= p0_re;
			p1_ack <= p1_re;
		end
	`else
		// Registered read using MAX10's 
		altsyncram	altsyncram_component (
			.clock0    (clk),
			.clocken0  (clken),
			.address_a (p0_addr),
			.address_b (p0_addr),
			.data_a (32'h0),
			.data_b (32'h0),
			.wren_a (1'h0),
			.wren_b (1'h0),
			.q_a (p0_rdata),
			.q_b (p1_rdata),
			// synopsys translate_off
			.aclr0 (),
			.aclr1 (),
			.addressstall_a (),
			.addressstall_b (),
			.byteena_a (),
			.byteena_b (),
			.clock1 (),
			.clocken1 (),
			.clocken2 (),
			.clocken3 (),
			.eccstatus (),
			.rden_a (),
			.rden_b ()
			// synopsys translate_on
		);
		defparam
			altsyncram_component.address_reg_b = "CLOCK0",
			altsyncram_component.clock_enable_input_a = "NORMAL",
			altsyncram_component.clock_enable_input_b = "NORMAL",
			altsyncram_component.clock_enable_output_a = "BYPASS",
			altsyncram_component.clock_enable_output_b = "BYPASS",
			altsyncram_component.indata_reg_b = "CLOCK0",
			altsyncram_component.init_file = "../hdlib/rv32imc_ss/bootloader.mif",
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
			altsyncram_component.widthad_a = ADDR_WIDTH,
			altsyncram_component.widthad_b = ADDR_WIDTH,
			altsyncram_component.width_a = WIDTH,
			altsyncram_component.width_b = WIDTH,
			altsyncram_component.width_byteena_a = 1,
			altsyncram_component.width_byteena_b = 1,
			altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0";

		always_ff @(posedge clk) begin
			p0_ack <= p0_re;
			p1_ack <= p1_re;
		end

	`endif
  end
  endgenerate

endmodule