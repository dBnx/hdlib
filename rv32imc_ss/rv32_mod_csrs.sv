module rv32_mod_csrs #(
    parameter logic ASYNC_READ = 1
) (
    input         clk,
    input         rst,

    input  [ 1:0] priviledge,

    input         cas_oder_so,
    input  [11:0] addr,
    input  [31:0] data_in,
    output [31:0] data_out
);
    logic [1:0] addr_permission;
    logic [1:0] addr_priviledge;
    logic [3:0] addr_subkey;
    assign addr_permission = addr[11:10];
    assign addr_priviledge = addr[9:8];
    assign addr_subkey     = addr[7:4];
    
    logic illegal_access;
    assign illegal_access = addr_permission > priviledge;

    // Unpriviledged CSRs
    logic [63:0] ufflags;
    logic [63:0] ufrm;
    logic [63:0] ufcsr;

    logic [63:0] usspp;

    logic [63:0] ucycle;
    logic [63:0] utime;
    logic [63:0] uinstret;
    logic [63:0] uhpmcounter[3:31];

    // Priviledged supervisor-level CSRs
    /*
    logic [63:0] sstatus;
    logic [63:0] sie;
    logic [63:0] stvec;
    logic [63:0] scounteren;

    logic [63:0] sscratch;
    logic [63:0] sepc;
    logic [63:0] scause;
    logic [63:0] stval;
    logic [63:0] sip
    logic [63:0] scountovf;
    */

    // Priviledged machine-level CSRs
    // MRO
    logic [63:0] mvendorid;
    logic [63:0] marchid;
    logic [63:0] mimppid;
    logic [63:0] mhartid;
    logic [63:0] mconfigptr;

    // MRW
    logic [63:0] mstatus;
    logic [63:0] misa;
    logic [63:0] medeleg;
    logic [63:0] mideleg;
    logic [63:0] mie;
    logic [63:0] mtvec;
    logic [63:0] mcounteren;
    logic [63:0] mstatush;
    // logic [63:0] medelegh;

    // MRW
    logic [63:0] mscratch;
    logic [63:0] mepc;
    logic [63:0] mcause;
    logic [63:0] mtval;
    logic [63:0] mip;
    logic [63:0] mtinst;
    logic [63:0] mtval2;

    // MRW
    logic [63:0] mnscratch;
    logic [63:0] mnepc;
    logic [63:0] mncause;
    logic [63:0] mnstatus;

    // MRW
    logic [63:0] mcycle;
    logic [63:0] minstret;
    // logic [63:0] mhpmcounter[3:31];

    // logic [63:0] m;

    /*
always_ff @ (posedge clk) begin
    if(write0_enable == 1'b1 && write0_index != 0) begin
        registerfile[write0_index] <= write0_data;
    end
end

generate
    if (ASYNC_READ == 1'b1) begin : gen_USE_ASYNC_READ
        assign read1_data = read1_index == 0 ? 0 : registerfile[read1_index];
        assign read0_data = read0_index == 0 ? 0 : registerfile[read0_index];
    end else begin : gen_USE_SYNC_READ
        always_ff @ (posedge clk) begin
            read1_data <= read1_index == 0 ? 0 : registerfile[read1_index];
            read0_data <= read0_index == 0 ? 0 : registerfile[read0_index];
        end
    end
endgenerate
*/

endmodule