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
  logic [63:0] m status;
  logic [63:0] misa;
  logic [63:0] medeleg;
  logic [63:0] mideleg;
  logic [63:0] mie;
  logic [63:0] mtvec;
  logic [63:0] mcounteren;
  logic [63:0] m statush;
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
    parameter logic [31:0] INITIAL_MSTATUS = 32'h00000000,
    parameter logic [31:0] MVENDOR_ID = 32'h00000000,
    parameter logic [31:0] MARCH_ID = 32'h00000000,
    parameter logic [31:0] MIMP_ID = 32'h00000000,
    parameter logic [31:0] MHART_ID = 32'h00000000
) (
    input  bit clk,
    input  bit reset,

    input  bit [1:0] priviledge,
    input  bit       instruction_retired,

    // <<<< Register file I/O >>>>
    input  bit        wr,
    input  bit        rd,
    output bit        error,
    input  bit [11:0] addr,
    input  bit [31:0] data_i,
    output bit [31:0] data_o,

    // <<<< TRAPS >>>>
    input  bit        sys_jump_to_m,
    input  bit        sys_ret_from_priv,

    input  bit [31:0] mip_new,
    output bit [31:0] mip_cur,

    input  bit [7:0] interrupts,

    // Explicit exception causes
    input  bit       exception_instr_addr_misaligned,
    input  bit       exception_instr_access_fault,
    input  bit       exception_illegal_instruction,
    input  bit       exception_breakpoint,
    input  bit       exception_load_addr_misaligned,
    input  bit       exception_load_access_fault,
    input  bit       exception_store_addr_misaligned,
    input  bit       exception_store_access_fault,
    input  bit       exception_ecall_from_u_mode,
    input  bit       exception_ecall_from_s_mode,
    input  bit       exception_ecall_from_m_mode,
    input  bit       exception_instr_page_fault,
    input  bit       exception_load_page_fault,
    input  bit       exception_store_page_fault,

    // New signals for assigning to csr_mepc and csr_mtval
    input  bit [31:0] pc_current,
    input  bit [31:0] pc_next,
    input  bit [31:0] load_store_address,
    input  bit [31:0] faulting_instruction,

    input  bit        ret_from_trap,
    output bit        serve_trap,
    output bit [31:0] trap_handler_addr,
    output bit        trap_handler_active,
    output bit        double_fault,

    // <<<< CSRs direct access >>>>
    output bit [31:0] mstatus,
    output bit [31:0] mepc,
    output bit [31:0] mtval,
    output bit [31:0] mtvec,
    // Machine Interrupt Pending
    output bit [31:0] mip,
    // Machine Interrupt Enable
    output bit [31:0] mie
    // output bit [31:0] mscratch,
    // output bit [31:0] mtime,
    // output bit [31:0] mcycle

    // --------------------------------------------------------
    // TODO: Add perf counters as uniform submodule and
    // .mhpmcounter00(1'b1), // Cycles
    // .mhpmcounter01()      // Time
    // .mhpmcounter02(is_new_instr), // Instructions retired
    // .mhpmcounter03() // Whatever
    // .mhpmcounter04() // Whatever
    // .mhpmcounter05() // Whatever
    // .mhpmcounter06() // Whatever
    // .mhpmcounterN() // Whatever
);
    // TODO: Should check if currently serving a trap handler
    // TODO: Set trap_handler_active and tap_handler_* IO signals
    // TODO: Set pending bits in mip after request with additional info somewhere?
    // TODO: Handle pending interrupts according to mip & mie & define order

    // Internal registers for CSRs
    bit [31:0] csr_mstatus;
    bit        csr_mstatus_mie, csr_mstatus_mpie;
    bit [31:0] csr_mepc;
    bit [31:0] csr_mtval;
    bit [31:0] csr_mtvec;
    bit [31:0] csr_mip;
    bit [31:0] csr_mie;
    bit [31:0] csr_mcause;
    bit [31:0] csr_mscratch;

    bit [63:0] csr_mtime;
    bit [63:0] csr_mcycle;
    bit [63:0] csr_minstret;

    // Set: MXL=1 (32b), -0-, RV32I (not E), -0-
    bit [31:0] csr_misa = 32'b0100_0000_0000_0000_0000_0001_0000_0000;

    // Local counter overflow - -ZSscofpmf
    // bit mip_lcofip;
    bit mip_meip;
    // bit mip_seip;
    bit mip_mtip;
    // bit mip_stip;
    bit mip_msip;
    // bit mip_ssip;
    // assign mip_lcofip = mip[13];
    assign mip_meip = mip[11];
    // assign mip_seip = mip[9];
    assign mip_mtip = mip[7];
    // assign mip_stip = mip[5];
    assign mip_msip = mip[3];
    // assign mip_ssip = mip[1];

    // FIXME: Convert speciel bits to their own regs instead of
    //        extracting them akwardly - w.g. mie, mpie, ..

    // Local counter overflow - -ZSscofpmf
    // logic mie_lcofie;
    bit mie_meie;
    // logic mie_seie;
    bit mie_mtie;
    // logic mie_stie;
    bit mie_msie;
    // logic mie_ssie;
    // assign mie_lcofie = mie[13];
    assign mie_meie = mie[11];
    // assign mie_seie = mie[9];
    assign mie_mtie = mie[7];
    // assign mie_stie = mie[5];
    assign mie_msie = mie[3];
    // assign mie_ssie = mie[1];

    // Memory mapped
    bit [63:0] csr_mtimecmp; // Should be memory mapped - also mtime
    assign timer_interrupt = csr_mtimecmp > csr_mtime;


    bit interrupt_nmi; // Not implemented
    bit timer_interrupt; // Not implemented
    bit timer_overflow; // Not implemented

    // TODO: Check WARL and WLRL constraints.
    //       mstatus shifts bits around with each trap

    initial begin
        csr_mtvec   = INITIAL_MTVEC;
        csr_mstatus_mie = INITIAL_MSTATUS[3];
        csr_mstatus_mpie = INITIAL_MSTATUS[7];
        csr_mtval   = 0;
        csr_mcause  = 0;
    end

    bit in_context_handler;
    /// Set if an exception occurs, while in an exception handler. May only be reset via a HW reset
    assign trap_handler_active = in_context_handler;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            in_context_handler <= 0;
            double_fault <= 0;
        end else if(serve_trap) begin
            in_context_handler <= 1;
            double_fault <= in_context_handler;
        end else if(sys_ret_from_priv) begin
            in_context_handler <= 0;
        end
    end

    // CSR updates for mtime and mcycle

     // MSTATUS:
     // - 3: MIE
     // - 7: MPIE
    
    /*
    bit    csr_mstatus_write;

    bit [31:0] csr_mstatus_next;
    always_comb begin : mstatus_mie_mpie
        if(serve_trap) begin
            // MIE  <- 0
            csr_mstatus_next[3] = 0;
            // MPIE <- MIE
            csr_mstatus_next[7] = csr_mstatus[3];
        end else if(ret_from_trap) begin
            // MPIE <- MPIE? // TODO: Check
            csr_mstatus_next[7] = csr_mstatus[7];
            // MIE  <- MPIE
            csr_mstatus_next[3] = csr_mstatus[7];
        end else begin
            csr_mstatus_next[3] = csr_mstatus[3];
            csr_mstatus_next[7] = csr_mstatus[7];
        end
    end
    */

    // Static MSTATUS bits
    
    assign csr_mstatus[ 2: 0] = 0; // ?, SIE, UIE
    assign csr_mstatus[    3] = csr_mstatus_mie;
    assign csr_mstatus[ 6: 4] = 0; // ?, SPIE, UPIE
    assign csr_mstatus[    7] = csr_mstatus_mpie;
    assign csr_mstatus[10: 8] = 0; // ?, SPP
    assign csr_mstatus[12:11] = 2'b11; // MPP Prev Priv - Only M supported
    assign csr_mstatus[31:13] = 0; // SD, ?-?, XS(2), FS(2)
	 
	bit        m_wr;
    bit [31:0] csr_mcause_next, csr_mtval_next;
	assign m_wr = wr && priviledge == 2'b11;
    // Initialize CSRs on reset
    always_ff @(posedge clk or posedge reset) begin : write_to_csrs
        if (reset) begin
            csr_mstatus_mie  <= INITIAL_MSTATUS[3];
            csr_mstatus_mpie <= INITIAL_MSTATUS[7];
            csr_mepc         <= 32'h00000000;
            csr_mtval        <= 32'h00000000;
            csr_mtvec        <= INITIAL_MTVEC;
            csr_mip          <= 32'h00000000;
            csr_mie          <= 32'h00000000;
            csr_mcause       <= 32'h00000000;
            csr_mscratch     <= 32'h00000000;
            csr_mtime        <= 64'h0000000000000000;
            csr_mcycle       <= 64'h0000000000000000;
            error            <= 1'b0;
        end else begin
            // CSR writes
            if(serve_trap) begin
                // Syncronuous exceptions save the faulting/causing instruction
                // and interrupts save the next pc.
                csr_mepc <= handle_exception ? pc_current : pc_next;
            end else if (m_wr && addr == 12'h341) begin
                csr_mepc <= data_i;
            end

            if(serve_trap) begin
                csr_mcause <= csr_mcause_next;
            end else if (m_wr && addr == 12'h342) begin
                csr_mcause <= data_i;
            end

            if(serve_trap) begin
                csr_mtval <= csr_mtval_next;
            end else if (m_wr && addr == 12'h343) begin
                csr_mtval <= data_i;
            end

            if(serve_trap) begin
                csr_mstatus_mie  <= 0;
                csr_mstatus_mpie <= csr_mstatus_mie;
            end else if(ret_from_trap) begin
                csr_mstatus_mie  <= csr_mstatus_mpie;
                csr_mstatus_mpie <= 1;
            end else if (m_wr && addr == 12'h300) begin
                csr_mstatus_mie  <= data_i[3];
                csr_mstatus_mpie <= data_i[7];
            end

            /*
            if(serve_trap || ret_from_trap) begin
                csr_mstatus[3] <= csr_mstatus_next[3];
                csr_mstatus[7] <= csr_mstatus_next[7];
            end else if (m_wr && addr == 12'h300) begin
                csr_mstatus[3] <= data_i[3];
                csr_mstatus[7] <= data_i[7];
            end
            */

            if (m_wr) begin  // Machine mode check
                case (addr)
                    12'h304: csr_mie      <= data_i;
                    12'h305: csr_mtvec    <= data_i;
                    12'h340: csr_mscratch <= data_i;
                    // mepc, mcause, mtval
                    12'h344: csr_mip      <= data_i;
                    12'h701: csr_mtime[31:0]     <= data_i;
                    12'h702: csr_mtime[63:32]    <= data_i;
                    12'hB02: csr_minstret[31:0]  <= data_i;
                    12'hB82: csr_minstret[63:32] <= data_i;
                    12'hB00: csr_mcycle[31:0]    <= data_i;
                    12'hB80: csr_mcycle[63:32]   <= data_i; // TODO: Check address(es)
                    default: error               <= 1'b1;   // Invalid CSR access
                endcase
            end else if (wr && priviledge == 2'b11) begin   // Other modes
                error <= 1'b1;
            end else begin
                error <= 1'b0;
            end

            // TODO: mepc should actually point to the faulting instruction / pc_current?
            // csr_mepc   <= pc_current;
            
            csr_mtime <= csr_mtime + 1;
            csr_mcycle <= csr_mcycle + 1;
				
            if (wr && priviledge == 2'b11 && instruction_retired) begin
                csr_minstret <= csr_minstret + 1;
            end
        end
    end

    // CSR reads
    // always_ff @(posedge clk) begin
    //     if (reset) begin
    //         data_o  <= 32'h00000000;
    //     end else begin
    always_comb begin : read_from_csrs
        if (rd) begin
            case (addr)
                // <<< Machine Trap Setup >>>
                12'h300: data_o = csr_mstatus;
                12'h301: data_o = csr_misa;
                12'h304: data_o = csr_mie;
                12'h305: data_o = csr_mtvec;
                12'h310: data_o = 32'h0; // mstatush
                // Delegation, misa, status, counteren
                // <<< Machine Trap Handling >>>
                12'h340: data_o = csr_mscratch;
                12'h341: data_o = csr_mepc;
                12'h342: data_o = csr_mcause;
                12'h343: data_o = csr_mtval;
                12'h344: data_o = csr_mip;
                // mtval2
                // <<< Machine Counter/Timers >>>
                12'hB00: data_o = csr_mcycle[31:0];
                12'hB80: data_o = csr_mcycle[63:32];
                12'hC01: data_o = csr_mtime[31:0];
                12'hC81: data_o = csr_mtime[63:32];
                12'hB02: data_o = csr_minstret[31:0];
                12'hB82: data_o = csr_minstret[63:32];
                // <<< Machine information >>>
                12'hF11: data_o = MVENDOR_ID;
                12'hF12: data_o = MARCH_ID;
                12'hF13: data_o = MIMP_ID;
                12'hF14: data_o = MHART_ID;
                default: data_o = 32'h00000000;  // Invalid CSR address
            endcase
        end else begin
            data_o = 32'h00000000;
        end
    end

    // TODO: Mixup between faulting address and faulting instruction


    always_comb begin : set_exception_info
        csr_mtval_next = 32'h00000000;
        csr_mcause_next = csr_mcause;

        if (exception_instr_addr_misaligned) begin
            csr_mcause_next = 32'h00000000;
            csr_mtval_next = load_store_address;
        end else if (exception_instr_access_fault) begin
            csr_mcause_next = 32'h00000001;
            csr_mtval_next = load_store_address;
        end else if (exception_illegal_instruction) begin
            csr_mcause_next = 32'h00000002;
            csr_mtval_next = faulting_instruction;
        /*
        end else if (exception_breakpoint) begin
            csr_mcause_next = 32'h00000003;
            csr_mtval_next = faulting_address;
        end else if (exception_load_addr_misaligned) begin
            csr_mcause_next = 32'h00000004;
            csr_mtval_next = faulting_address;
        end else if (exception_load_access_fault) begin
            csr_mcause_next = 32'h00000005;
            csr_mtval_next = faulting_address;
        end else if (exception_store_addr_misaligned) begin
            csr_mcause_next = 32'h00000006;
            csr_mtval_next = faulting_address;
        end else if (exception_store_access_fault) begin
            csr_mcause_next = 32'h00000007;
            csr_mtval_next = faulting_address;
        end else if (exception_ecall_from_u_mode) begin
            csr_mcause_next = 32'h00000008;
            csr_mtval_next = 32'h00000000;
        end else if (exception_ecall_from_s_mode) begin
            csr_mcause_next = 32'h00000009;
            csr_mtval_next = 32'h00000000;  // No specific faulting address
        */
        end else if (exception_ecall_from_m_mode) begin
            csr_mcause_next = 32'h0000000B;
            csr_mtval_next = 32'h00000000;  // No specific faulting address
        /*
        end else if (exception_instr_page_fault) begin
            csr_mcause_next = 32'h0000000C;
            csr_mtval_next = faulting_address;
        end else if (exception_load_page_fault) begin
            csr_mcause_next = 32'h0000000D;
            csr_mtval_next = faulting_address;
        end else if (exception_store_page_fault) begin
            csr_mcause_next = 32'h0000000F;
            csr_mtval_next = faulting_address;
        end else if (interrupt_nmi) begin
            // TODO: Handle interrupt-specifics
            // Set mcause
            csr_mcause_next = 32'h8000000B; // Only for M External
        end else if (interrupts != 0 && mie_meie) begin
            // Platform specific interrupts
            // TODO: Handle interrupt-specifics
            // Set mcause
            csr_mcause_next = 32'h80000010 + int'(interrupts); // Only for M External
        end else if (timer_overflow) begin
            // TODO: Handle interrupt-specifics
            // Set mcause
            csr_mcause_next = 32'h8000000D; // Only for M External
        end else if (timer_interrupt && mie_mtie) begin
            // TODO: Handle interrupt-specifics
            // Set mcause
            csr_mcause_next = 32'h80000007; // Only for M External
        */
        end
    end

    // Trap handling logic
	 /*
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            csr_mcause <= 32'h00000000;
            csr_mepc   <= 32'h00000000;
            csr_mtval  <= 32'h00000000;
        end else begin
            // Check for exceptions
            if (exception_instr_addr_misaligned) begin
                csr_mcause <= 32'h00000000;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_instr_access_fault) begin
                csr_mcause <= 32'h00000001;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_illegal_instruction) begin
                csr_mcause <= 32'h00000002;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_instruction;
            end else if (exception_breakpoint) begin
                csr_mcause <= 32'h00000003;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_load_addr_misaligned) begin
                csr_mcause <= 32'h00000004;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_load_access_fault) begin
                csr_mcause <= 32'h00000005;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_store_addr_misaligned) begin
                csr_mcause <= 32'h00000006;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_store_access_fault) begin
                csr_mcause <= 32'h00000007;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_ecall_from_u_mode) begin
                csr_mcause <= 32'h00000008;
                csr_mepc <= current_pc;
                csr_mtval <= 32'h00000000;
            end else if (exception_ecall_from_s_mode) begin
                csr_mcause <= 32'h00000009;
                csr_mepc <= current_pc;
                csr_mtval <= 32'h00000000;  // No specific faulting address
            end else if (exception_ecall_from_m_mode) begin
                csr_mcause <= 32'h0000000B;
                csr_mepc <= current_pc;
                csr_mtval <= 32'h00000000;  // No specific faulting address
            end else if (exception_instr_page_fault) begin
                csr_mcause <= 32'h0000000C;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_load_page_fault) begin
                csr_mcause <= 32'h0000000D;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (exception_store_page_fault) begin
                csr_mcause <= 32'h0000000F;
                csr_mepc <= current_pc;
                csr_mtval <= faulting_address;
            end else if (interrupt_nmi) begin
                // TODO: Handle interrupt-specifics
                // Set mcause
                csr_mepc <= current_pc;
                csr_mcause <= 32'h8000000B; // Only for M External
            end else if (interrupts != 0 && mie_meie) begin
                // Platform specific interrupts
                // TODO: Handle interrupt-specifics
                // Set mcause
                csr_mepc <= current_pc;
                csr_mcause <= 32'h80000010 + int'(interrupts); // Only for M External
            end else if (timer_overflow) begin
                // TODO: Handle interrupt-specifics
                // Set mcause
                csr_mepc <= current_pc;
                csr_mcause <= 32'h8000000D; // Only for M External
            end else if (timer_interrupt && mie_mtie) begin
                // TODO: Handle interrupt-specifics
                // Set mcause
                csr_mepc <= current_pc;
                csr_mcause <= 32'h80000007; // Only for M External
            end
        end
    end
	 */


    // Sync Trap Taken ---------------------------------

    // Exceptions are HART internal and therefore bounded. Interrupts go through MIP
    bit    handle_exception;
    assign handle_exception =  exception_instr_addr_misaligned
                            || exception_instr_access_fault
                            || exception_illegal_instruction
                            || exception_breakpoint
                            || exception_load_addr_misaligned
                            || exception_load_access_fault
                            || exception_store_addr_misaligned
                            || exception_store_access_fault
                            || exception_ecall_from_u_mode
                            || exception_ecall_from_s_mode
                            || exception_ecall_from_m_mode
                            || exception_instr_page_fault
                            || exception_load_page_fault
                            || exception_store_page_fault;

    assign serve_trap = handle_exception && !double_fault;

    bit [ 1:0] trap_addr_mode;
    bit [31:0] trap_handler_addr_base, trap_handler_addr_offset;
    assign trap_handler_addr_base = {csr_mtvec[31:2], 2'b00};
    assign trap_addr_mode = csr_mtvec[1:0];

    always_comb begin
        if(sys_ret_from_priv) begin : trap_return
            trap_handler_addr = csr_mepc;
        end else if(trap_addr_mode == 2'b01) begin : trap_vectored_mode
            trap_handler_addr = trap_handler_addr_base + trap_handler_addr_offset;
        end else if(trap_addr_mode == 2'b00) begin : trap_direct_mode
            trap_handler_addr = trap_handler_addr_base;
        end else begin
            // ERROR: Invalid mode (reserved)
            trap_handler_addr = trap_handler_addr_base;
        end
    end

    always_comb begin
        // TODO: Implement offset
        trap_handler_addr_offset = 0; // csr_mcause[29:0];
    end

    // Output CSRs -------------------------------------
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