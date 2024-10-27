/// Directly mapped, write-through cache. Has a latency of one for cache hits
/// and to pass the write through on a miss. Access to an active cacheline
/// are answered in the same cycle.
///
/// Assumes that the internal ram _always_ has a lower or the same latency as
/// the external interface!
///
/// FIXME: Currently ignores writes and BE.
///       Only focus on use as ICache right now. Will be extended later.
module icache #(
    parameter int ADDR_SIZE = 32,
    parameter int WORD_SIZE = 32,
    parameter int LINES_LOG2 = 5,
    parameter int WAYS_LOG2 = 0, // Not yet implemented
    parameter int WORDS_PER_LINE_LOG2 = 2
) (
    input  bit clk,
    input  bit clken,
    input  bit reset,

    // <<<< Internal I/O >>>>
    // Setting either will initiate a request. Issuing requests while one is in flight are
    // undefined behvariour.
    input  bit                   int_wr,
    input  bit                   int_rd,
    // Termination signals
    output bit                   int_ack,
    output bit                   int_error,
    // In the same cyle as the request is submitted one of the following is set for 1c
    output bit                   int_hit,
    output bit                   int_miss,
    // Must be stable until either ack or error is asserted
    input  bit [  ADDR_SIZE-1:0] int_addr, // Indexes words, not bytes
    input  bit [ByteEnWidth-1:0] int_be,
    input  bit [  WORD_SIZE-1:0] int_data_i,
    // Stable only for the same cycle as either ack or error is asserted
    output bit [  WORD_SIZE-1:0] int_data_o,

    // <<<< External I/O >>>>
    output bit                   ext_wr,
    output bit                   ext_rd,
    input  bit                   ext_ack,
    input  bit                   ext_error,
    output bit [  ADDR_SIZE-1:0] ext_addr, // Indexes words, not bytes
    output bit [ByteEnWidth-1:0] ext_be,
    input  bit [  WORD_SIZE-1:0] ext_data_i,
    output bit [  WORD_SIZE-1:0] ext_data_o
);
    localparam int Lines = 1 << LINES_LOG2;
    localparam int Ways = 1 << WAYS_LOG2;
    localparam int WordsPerLine = 1 << WORDS_PER_LINE_LOG2;
    localparam int ByteEnWidth = WORD_SIZE / 8;

    localparam int LineWidth = WORD_SIZE * WordsPerLine;
    localparam int CacheLineBE = ByteEnWidth * WordsPerLine;
    localparam int AddrTagWidth = ADDR_SIZE-LINES_LOG2 - WORDS_PER_LINE_LOG2;

    /// Types ---------------------------------------------------------------
    typedef struct packed {
        bit [       AddrTagWidth-1:0] tag;
        bit [         LINES_LOG2-1:0] index;
        bit [WORDS_PER_LINE_LOG2-1:0] word;
    } addr_parts_t;
    
    typedef struct packed {
        bit [LINES_LOG2-1:0] index;
        bit [ WAYS_LOG2  :0] way;
    } cache_block_addr_t;

    typedef struct packed {
        bit [WordsPerLine-1:0][WORD_SIZE-1:0] words;
    } cache_line_t;

    typedef struct packed {
        bit [AddrTagWidth-1:0] addr_tag;
        bit [   WAYS_LOG2  :0] lfu;
        bit                    dirty;
        bit                    valid;
    } cl_metadata_t;

    /// Address seperation --------------------------------------------------
    addr_parts_t int_addr_parts;
    assign int_addr_parts = int_addr;

    addr_parts_t ext_addr_parts;
    assign ext_addr_parts.tag   = int_addr_parts.tag;
    assign ext_addr_parts.index = int_addr_parts.index;
    assign ext_addr_parts.word  = cc_state_word;


    /// Cache Tags ----------------------------------------------------------
    cl_metadata_t [WAYS_LOG2  :0] metadata[Lines];

    localparam int CacheLineTagW = AddrTagWidth + 1;

    // bit [CacheLineTagW-1:0] line_metadata[Lines];
    // bit         [Lines-1:0] line_addr;
    bit        [WAYS_LOG2  :0] way_index;

    cache_line_t cache_line_out;
    assign int_data_o = cache_line_out.words[int_addr_parts.word];

    initial begin
        for (int l = 0; l < Lines; l = l + 1) begin
            for (int w = 0; w < Ways; w = w + 1) begin
                metadata[l][w].valid    = 0;
                metadata[l][w].dirty    = 1'bX;
                metadata[l][w].lfu      = 'X;
                metadata[l][w].addr_tag = 'X;
            end
        end
    end

    bit hit, miss;
    always_comb begin
        // TODO: Generate for to match each metadata addr tag and valid tag with current address.
        //       Set cache_miss, cache_hit and CacheLineTagW accordingly.
        way_index = 0;
        hit = 0;
        miss = 1;

        for (int i = 0; i < Ways; i = i + 1) begin
            if(metadata[int_addr_parts.index][i].addr_tag == int_addr_parts.tag) begin
                way_index = i[WAYS_LOG2:0];
                hit = 1;
                miss = 0;
            end
        end
    end

    bit    cache_line_active;
    assign cache_line_active = last_addr.tag == int_addr_parts.tag
                          && last_addr.index == int_addr_parts.index;

    bit int_ack_async;
    assign int_ack_async = cache_line_active && hit && (int_rd || int_wr);

    assign int_hit = hit && (int_rd || int_wr);
    assign int_miss = miss && (int_rd || int_wr);

    addr_parts_t last_addr;
    always_ff @(posedge clk or posedge reset) begin
        last_addr <= int_addr;
    end

    /// Cache Controller ----------------------------------------------------
    // Fills up cache lines on a cache miss and passes through writes
    bit                          cc_ack, cc_wr;
    cache_block_addr_t           cc_addr;
    bit [WordsPerLine-1:0][ByteEnWidth-1:0] cc_be;
    bit [WordsPerLine-1:0][  WORD_SIZE-1:0] cc_data_w;

    bit                           cc_state_active;
    bit                           cc_state_active_2stage;
    bit [WORDS_PER_LINE_LOG2-1:0] cc_state_word;

    bit int_ack_sync;
    assign int_ack = int_ack_async || int_ack_sync;
    always_ff @(posedge clk or posedge reset) begin
        if(reset) begin
            cc_state_active <= 0;
            cc_state_word <= 0;
            cc_wr <= 0;
            ext_wr <= 0;
            int_ack_sync <= 0;

            for (int l = 0; l < Lines; l = l + 1) begin
                for (int w = 0; w < Ways; w = w + 1) begin
                    metadata[l][w].valid    <= 0;
                    metadata[l][w].dirty    <= 1'bX;
                    metadata[l][w].lfu      <= 'X;
                    metadata[l][w].addr_tag <= 'X;
                end
            end

        end else if(hit && cache_line_active && !cc_state_active_2stage) begin
            // Handled by int_ack_async
            // -> we don't have to do anything
            int_ack_sync <= 0;

        end else if(hit && !cache_line_active && !cc_state_active_2stage) begin
            // We have the cache line, but it's not the currently active one
            // So we have to activate it first with a latency of 1
            int_ack_sync <= 1;

            //end else if(miss) begin
            //    // Start SM
            //    cc_state_active <= 1;
            //    int_ack <= 0;
            // end else if(cc_state_active) begin
        end else begin
            // TODO: Increase cc_addr, request, update cache lines and then
            //       report back
            if(cc_state_active_2stage && cc_ack) begin
                // Cache line filling finished
                // - Reset SM
                // - Update cache line valid
                // - Inform internal IF // TODO: -

                // Reset internal SM
                cc_state_active <= 0;
                cc_state_active_2stage <= 0;
                cc_state_word <= 0;
                cc_wr <= 0;

                // cc_be <= 0;
                cc_data_w <= 0;

                // Inform internal IF
                int_ack_sync <= 1;
                // TODO: Check if it matches with memory megafunction delay
            end else if(cc_state_active_2stage && !cc_ack) begin
                // End request
                cc_wr <= 0;

            end else if(cc_state_active && ext_ack && cc_state_word == '1) begin
                // Cache line filling finished
                // - Update SM
                // - Update Metadata

                // Reset internal SM
                cc_state_active_2stage <= 1;

                // Update Cache Line Metadata
                metadata[int_addr_parts.index][way_index].valid    <= 1'b1;
                metadata[int_addr_parts.index][way_index].dirty    <= 1'b0;
                metadata[int_addr_parts.index][way_index].lfu      <= 'b1; // TODO!
                metadata[int_addr_parts.index][way_index].addr_tag <= int_addr_parts.tag;
                // Update LRU flag on the rest of the other ways
                for (int w = 0; w < Ways; w = w + 1) begin
                    if(w != int'(way_index)) begin
                        metadata[int_addr_parts.index][w].lfu <= 'b0; // TODO!
                    end
                end

                // Read current feedback
                cc_wr <= 1;
                cc_addr.index <= int_addr_parts.index;
                cc_addr.way   <= way_index;
                cc_data_w[cc_state_word] <= ext_data_i;

                // FIXME: Register address and write the registered part here
                //        - maybe even update active_cache_line and promoting it to a reg?
            end else if(cc_state_active && ext_ack) begin
                // Cache line filling up ..
                // - Keep stalling int
                // - Keep increasing offset

                // Increase for next request
                cc_state_word <= cc_state_word + 1;

                // Send next command
                int_ack_sync <= 0;
                ext_rd <= 1;
                ext_wr <= 0;
                ext_be <= '1;
                // ext_addr <= ext_addr_parts;

                // Read current feedback
                cc_wr <= 1;
                cc_addr.index <= int_addr_parts.index;
                cc_addr.way   <= way_index;
                cc_data_w[cc_state_word] <= ext_data_i;

                // FIXME: We could also loob back data_w and remove BE lines
            end else if(miss && (int_rd || int_wr)) begin
                // We have to request a new cache line! Start requesting the first word
                // and start SM.
                cc_state_active <= 1;

                // Invalidate active cache line
                metadata[int_addr_parts.index][way_index] <= 0;
                // TODO: If miss, then way_index is not valid - fixme

                // Initial request
                ext_rd <= 1;
                ext_be <= '1;
                // ext_addr <= ext_addr_parts;

                int_ack_sync <= 0;

                // TODO: Implement Associativity:
                // We need a hit_addr and miss_addr to implement LFU

                cc_wr <= 0;
            end else begin
                // Filling up, but we wait for an ACK
                ext_rd <= 0;
                cc_wr <= 0;
                int_ack_sync <= 0;

                // Leave ext_be and ext_addr unchanged.
            end

            // -
        end
    end

    always_ff @( posedge clk or posedge reset ) begin : ram_set_write_be
        if(reset) begin
            cc_be <= 0;
        end else begin
            for (int i = 0; i < WordsPerLine; i = i + 1) begin
                cc_be[i] <= (i == int'(cc_state_word)) ? {ByteEnWidth{1'b1}} : 0;
            end
        end
    end

    assign ext_addr = ext_addr_parts;

    bit                   ram_ack;
    bit                   ram_ack_reset;

    bit                   cache_ack; // TODO
    cache_block_addr_t    cache_addr;
    assign cache_addr.index = int_addr_parts.index;
    assign cache_addr.way = way_index;

    /// Cache Memory --------------------------------------------------------
    ram_dp_handshake #(
        .ADDR_WIDTH(LINES_LOG2 + WAYS_LOG2),
        .BYTES(WordsPerLine * WORD_SIZE / 8)
    ) inst_ram (
        .clk  (clk),
        .clken(clken),

        // First port
        .p0_we   (1'b0),
        .p0_re   (1'b1),
        .p0_ack  (cache_ack),
        .p0_addr (cache_addr.index), // TODO: Ignores .way
        .p0_be   (-1),
        .p0_wdata(0),
        .p0_rdata(cache_line_out),

        // Second port - Cache controller IF to fill cache lines
        .p1_we   (cc_wr),
        .p1_re   (1'b0),
        .p1_ack  (cc_ack),
        .p1_addr (cc_addr.index), // TODO: Ignores .way
        .p1_be   (cc_be),
        .p1_wdata(cc_data_w),
        .p1_rdata()  // TODO: Impl
    );


endmodule