
module huffman_core (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- Control Signals ---
    input  logic        i_start,        // Pulsed high to begin decoding
    output logic        o_done,         // Pulsed high when EOB is reached
    
    // --- Table Configuration (From AXI-Lite Flip-Flops) ---
    input  huff_cfg_array_t i_table_cfg,
    
    // --- Selector RAM Interface ---
    // Pre-fetches the next table selector to prevent stalls at the 50-symbol boundary
    output logic [15:0] o_sel_addr,
    input  logic [2:0]  i_sel_data,
    
    // --- AXI-Stream-like Input (Compressed Bits) ---
    input  logic [31:0] i_data,
    input  logic        i_valid,
    output logic        o_ready,
    
    // --- Symbol SRAM Interface (To AXI-Lite Dual-Port RAMs) ---
    output logic [2:0]  o_sram_tbl_sel,
    output logic [7:0]  o_sram_addr,
    output logic        o_sram_en,
    input  logic [15:0] i_sram_data,    // From SRAM (1 cycle latency)
    
    // --- AXI-Stream-like Output (Decoded Symbols) ---
    output logic [15:0] o_symbol,
    output logic        o_valid
);

    // =========================================================================
    // STATE MACHINE (Start & Prefetch)
    // =========================================================================
    typedef enum logic [1:0] {IDLE, PREFETCH, DECODE} state_t;
    state_t state_q, state_next;
    
    logic [2:0] active_tbl_q;
    logic [5:0] sym_count_q;    // Counts 0 to 49
    logic [15:0] sel_idx_q;     // Which selector we are on
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q      <= IDLE;
            active_tbl_q <= '0;
            sym_count_q  <= '0;
            sel_idx_q    <= '0;
        end else begin
            state_q <= state_next;
            
            // Selector boundary management (Table Switching)
            if (state_q == PREFETCH) begin
                active_tbl_q <= i_sel_data;
            end else if (state_q == DECODE && s1_match_found) begin
                if (sym_count_q == 49) begin
                    sym_count_q  <= '0;
                    sel_idx_q    <= sel_idx_q + 1;
                    active_tbl_q <= i_sel_data; // Immediately swap to prefetched table
                end else begin
                    sym_count_q <= sym_count_q + 1;
                end
            end
        end
    end

    always_comb begin
        state_next = state_q;
        case (state_q)
            IDLE:     if (i_start) state_next = PREFETCH;
            PREFETCH: state_next = DECODE; // Wait 1 cycle for SRAM to output first selector
            DECODE:   if (o_done) state_next = IDLE;
        endcase
    end

    // Always prefetch the *next* selector so it is ready for the 50-boundary swap
    assign o_sel_addr = (state_q == IDLE) ? 16'd0 : (sel_idx_q + 1);


    // =========================================================================
    // STAGE 1: Sliding Window & 20-Way Parallel Compare
    // =========================================================================
    logic [63:0] window_q, window_next;
    logic [6:0]  valid_bits_q, valid_bits_next;
    logic        load_en;
    
    // We request data when we have 32 or fewer bits left in the window
    assign o_ready = (valid_bits_q <= 32) && (state_q == DECODE);
    assign load_en = o_ready && i_valid;

    // The top 20 valid bits are constantly exposed to the comparators
    logic [19:0] peek_bits;
    assign peek_bits = window_q[63:44];
    
    // 20 parallel comparators outputting a One-Hot vector
    logic [20:1] match_onehot;
    logic [4:0]  matched_len;
    logic        s1_match_found;
    
    // Combinational comparison
    always_comb begin
        match_onehot = '0;
        matched_len  = '0;
        s1_match_found = 1'b0;
        
        // Ensure we have at least 20 bits buffered before evaluating
        if (state_q == DECODE && valid_bits_q >= 20) begin
            for (int L = 1; L <= 20; L++) begin
                logic [19:0] code_val = peek_bits >> (20 - L);
                
                if ((code_val >= i_table_cfg[active_tbl_q][L].min_code) && 
                    (code_val <= i_table_cfg[active_tbl_q][L].max_code)) begin
                    match_onehot[L] = 1'b1;
                    matched_len     = L[4:0];
                    s1_match_found  = 1'b1;
                end
            end
        end
    end
    
    // Combinational sliding window shift and data load
    always_comb begin
        // 1. Shift out the matched bits
        window_next     = window_q << matched_len;
        valid_bits_next = valid_bits_q - matched_len;
        
        // 2. Insert new 32-bit data exactly after the remaining valid bits
        if (load_en) begin
            logic [5:0] shift_amt = 64 - valid_bits_next - 32;
            window_next     = window_next | ({32'd0, i_data} << shift_amt);
            valid_bits_next = valid_bits_next + 32;
        end
    end

    // Sequential window updates
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            window_q     <= '0;
            valid_bits_q <= '0;
        end else if (state_q == DECODE) begin
            window_q     <= window_next;
            valid_bits_q <= valid_bits_next;
        end
    end

    // Pipeline Registers (Stage 1 -> Stage 2)
    logic [19:0] s2_peek_bits;
    logic [4:0]  s2_matched_len;
    logic [2:0]  s2_active_tbl;
    logic        s2_valid;

    always_ff @(posedge clk) begin
        if (!rst_n) s2_valid <= 1'b0;
        else        s2_valid <= s1_match_found;
        
        if (s1_match_found) begin
            s2_peek_bits   <= peek_bits;
            s2_matched_len <= matched_len;
            s2_active_tbl  <= active_tbl_q;
        end
    end


    // =========================================================================
    // STAGE 2: ALU Address Calculation
    // =========================================================================
    logic [19:0] s2_code_val;
    logic [8:0]  s2_sram_addr;
    
    // The Math: idx = base_idx + (code - min_code)
    always_comb begin
        s2_code_val = s2_peek_bits >> (20 - s2_matched_len);
        s2_sram_addr = i_table_cfg[s2_active_tbl][s2_matched_len].base_idx + 
                       (s2_code_val - i_table_cfg[s2_active_tbl][s2_matched_len].min_code);
    end

    // Pipeline Registers (Stage 2 -> Stage 3 SRAM Inputs)
    logic s3_valid;
    
    always_ff @(posedge clk) begin
        if (!rst_n) s3_valid <= 1'b0;
        else        s3_valid <= s2_valid;
        
        if (s2_valid) begin
            o_sram_tbl_sel <= s2_active_tbl;
            o_sram_addr    <= s2_sram_addr[7:0]; // 258 entries fit in 8 bits (0-255). 
                                                 // Note: entry 256/257 might require 9th bit depending on exact table density.
            o_sram_en      <= 1'b1;
        end else begin
            o_sram_en      <= 1'b0;
        end
    end


    // =========================================================================
    // STAGE 3: SRAM Read (Handled by external AXI-Lite RAM)
    // =========================================================================
    // The SRAM receives o_sram_addr on the clock edge, and outputs i_sram_data 
    // before the NEXT clock edge. We simply delay our valid signal by 1 cycle 
    // to keep timing aligned with the SRAM.
    
    logic s4_valid;
    
    always_ff @(posedge clk) begin
        if (!rst_n) s4_valid <= 1'b0;
        else        s4_valid <= s3_valid;
    end


    // =========================================================================
    // STAGE 4: Symbol Output
    // =========================================================================
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            o_valid  <= 1'b0;
            o_symbol <= '0;
            o_done   <= 1'b0;
        end else begin
            o_valid  <= s4_valid;
            
            if (s4_valid) begin
                o_symbol <= i_sram_data;
                // EOB marker (Max symbols in use is up to 258. The software will pass the exact 
                // EOB symbol limit, but 258 is the absolute maximum in the protocol).
                if (i_sram_data == 16'd258 /* Or software programmed EOB */) begin 
                    o_done <= 1'b1;
                end
            end else begin
                o_done <= 1'b0;
            end
        end
    end

endmodule