`timescale 1ns / 1ps


// 00 u user/application
// 01 s supervisor
// 11 m machine

/*
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
  logic [63:0] mhpmcounter[3:31];
*/

module rv32_mod_csrs #(
    parameter logic [31:0] INITIAL_MTVEC = 32'h00010000,
    parameter logic [31:0] INITIAL_MSTATUS = 32'h00000080,
    parameter logic [31:0] MVENDOR_ID = 32'h00000000,
    parameter logic [31:0] MARCH_ID = 32'h00000000,
    parameter logic [31:0] MIMP_ID = 32'h00000000,
    parameter logic [31:0] MHART_ID = 32'h00000000
) (
    input logic clk,
    input logic rst,

    input logic [1:0] priviledge,

    // <<<< Register file I/O >>>>
    input logic wr,
    input logic rd,
    output logic error,
    input logic [11:0] addr,
    input logic [31:0] data_i,
    output logic [31:0] data_o, // registered

    // <<<< TRAPS >>>>
    input logic [5:0] interrupts,

    // Explicit exception causes
    input logic exception_instr_addr_misaligned,
    input logic exception_instr_access_fault,
    input logic exception_illegal_instruction,
    input logic exception_breakpoint,
    input logic exception_load_addr_misaligned,
    input logic exception_load_access_fault,
    input logic exception_store_addr_misaligned,
    input logic exception_store_access_fault,
    input logic exception_ecall_from_u_mode,
    input logic exception_ecall_from_s_mode,
    input logic exception_ecall_from_m_mode,
    input logic exception_instr_page_fault,
    input logic exception_load_page_fault,
    input logic exception_store_page_fault,

    // New signals for assigning to csr_mepc and csr_mtval
    input logic [31:0] current_pc,
    input logic [31:0] faulting_address,
    input logic [31:0] faulting_instruction,

    output logic serve_trap, // registered

    // <<<< CSRs direct access >>>>
    output logic [31:0] mstatus,
    output logic [31:0] mepc,
    output logic [31:0] mtval,
    output logic [31:0] mtvec,
    output logic [31:0] mip,
    output logic [31:0] mie
    // output logic [31:0] mscratch,
    // output logic [31:0] mtime,
    // output logic [31:0] mcycle
);

    // Internal registers for CSRs
    logic [31:0] csr_mstatus;
    logic [31:0] csr_mepc;
    logic [31:0] csr_mtval;
    logic [31:0] csr_mtvec;
    logic [31:0] csr_mip;
    logic [31:0] csr_mie;
    logic [31:0] csr_mcause;
    logic [31:0] csr_mscratch;
    logic [63:0] csr_mtime;
    logic [63:0] csr_mcycle;

    // TODO: Check WARL and WLRL constraints.
    //       mstatus shifts bits around with each trap

    // Initialize CSRs on reset
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            csr_mstatus  <= INITIAL_MSTATUS;
            csr_mepc     <= 32'h00000000;
            csr_mtval    <= 32'h00000000;
            csr_mtvec    <= INITIAL_MTVEC;
            csr_mip      <= 32'h00000000;
            csr_mie      <= 32'h00000000;
            csr_mcause   <= 32'h00000000;
            csr_mscratch <= 32'h00000000;
            csr_mtime    <= 64'h0000000000000000;
            csr_mcycle   <= 64'h0000000000000000;
            error        <= 1'b0;
        end else begin
            // CSR writes
            if (wr && priviledge == 2'b11) begin  // Machine mode check
                case (addr)
                    12'h304: csr_mie      <= data_i;
                    12'h305: csr_mtvec    <= data_i;
                    12'h300: csr_mstatus  <= data_i;
                    12'h340: csr_mscratch <= data_i;
                    12'h341: csr_mepc     <= data_i;
                    12'h343: csr_mtval    <= data_i;
                    12'h344: csr_mip      <= data_i;
                    12'h701: csr_mtime[31:0]   <= data_i;
                    12'h702: csr_mtime[63:32]  <= data_i;
                    12'hB00: csr_mcycle[31:0]  <= data_i;
                    12'hB02: csr_mcycle[63:32] <= data_i; // TODO: Check address(es)
                    default: error             <= 1'b1;  // Invalid CSR access
                endcase
            end else if (wr && priviledge == 2'b11) begin  // Other modes
                error <= 1'b1;
            end else begin
                error <= 1'b0;
            end
        end
    end

    // CSR reads
    always_ff @(posedge clk) begin
        if (rst) begin
            data_o  <= 32'h00000000;
        end else begin
            if (rd) begin
                case (addr)
                    12'h300: data_o <= csr_mstatus;
                    12'h304: data_o <= csr_mie;
                    12'h305: data_o <= csr_mtvec;
                    12'h340: data_o <= csr_mscratch;
                    12'h341: data_o <= csr_mepc;
                    12'h342: data_o <= csr_mcause;
                    12'h343: data_o <= csr_mtval;
                    12'h344: data_o <= csr_mip;
                    12'h701: data_o <= csr_mtime[31:0];
                    12'h702: data_o <= csr_mtime[63:32];
                    12'hb00: data_o <= csr_mcycle[31:0];
                    12'hb02: data_o <= csr_mcycle[63:32];
                    12'hF11: data_o <= MVENDOR_ID;
                    12'hF12: data_o <= MARCH_ID;
                    12'hF13: data_o <= MIMP_ID;
                    12'hF14: data_o <= MHART_ID;
                    default: data_o <= 32'h00000000;  // Invalid CSR address
                endcase
            end else begin
                data_o <= 32'h00000000;
            end
        end
    end

    // Trap handling logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            csr_mcause <= 32'h00000000;
            csr_mepc   <= 32'h00000000;
            csr_mtval  <= 32'h00000000;
            serve_trap <= 1'b0;
        end else begin
            // Check for exceptions
            if (exception_instr_addr_misaligned) begin
                csr_mcause <= 32'h00000000;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_instr_access_fault) begin
                csr_mcause <= 32'h00000001;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_illegal_instruction) begin
                csr_mcause <= 32'h00000002;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_instruction;
                serve_trap <= 1'b1;
            end else if (exception_breakpoint) begin
                csr_mcause <= 32'h00000003;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_load_addr_misaligned) begin
                csr_mcause <= 32'h00000004;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_load_access_fault) begin
                csr_mcause <= 32'h00000005;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_store_addr_misaligned) begin
                csr_mcause <= 32'h00000006;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_store_access_fault) begin
                csr_mcause <= 32'h00000007;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_ecall_from_u_mode) begin
                csr_mcause <= 32'h00000008;
                csr_mepc <= current_pc;
                csr_mtval <= 32'h00000000; 
                serve_trap <= 1'b1;
            end else if (exception_ecall_from_s_mode) begin
                csr_mcause <= 32'h00000009;
                csr_mepc <= current_pc;
                csr_mtval <= 32'h00000000;  // No specific faulting address
                serve_trap <= 1'b1;
            end else if (exception_ecall_from_m_mode) begin
                csr_mcause <= 32'h0000000B;
                csr_mepc <= current_pc;
                csr_mtval <= 32'h00000000;  // No specific faulting address
                serve_trap <= 1'b1;
            end else if (exception_instr_page_fault) begin
                csr_mcause <= 32'h0000000C;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_load_page_fault) begin
                csr_mcause <= 32'h0000000D;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (exception_store_page_fault) begin
                csr_mcause <= 32'h0000000F;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
                serve_trap <= 1'b1;
            end else if (interrupts != 6'b000000) begin
                serve_trap <= 1'b1;
                // TODO: Handle interrupt-specifics
            end else begin
                serve_trap <= 1'b0;
            end
        end
    end

    // CSR updates for mtime and mcycle
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            csr_mtime <= 0;
            csr_mcycle <= 0;
        end else begin
            csr_mtime <= csr_mtime + 1;
            csr_mcycle <= csr_mcycle + 1;
        end
    end

    // Output CSRs
    assign mstatus  = csr_mstatus;
    assign mepc     = csr_mepc;
    assign mtval    = csr_mtval;
    assign mtvec    = csr_mtvec;
    assign mip      = csr_mip;
    assign mie      = csr_mie;
    // assign mscratch = csr_mscratch;
    // assign mtime    = csr_mtime[31:0];  // 32-bit access only
    // assign mcycle   = csr_mcycle[31:0]; // 32-bit access only

endmodule
