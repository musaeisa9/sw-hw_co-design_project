import huffman_pkg::*;

module huffman_axi_lite_slv #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 16
)(
    // AXI-Lite Clock and Reset
    input  logic s_axi_aclk,
    input  logic s_axi_aresetn,

    // AXI-Lite Write Channels
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,

    // Outputs to Huffman Core
    output logic            hw_start,
    output huff_cfg_array_t o_table_cfg,
    
    // Selector RAM Read Interface (from Core)
    input  logic [15:0]     i_sel_addr,
    output logic [2:0]      o_sel_data,
    
    // Symbol RAM Read Interface (from Core)
    input  logic [2:0]      i_sram_tbl_sel,
    input  logic [7:0]      i_sram_addr,
    input  logic            i_sram_en,
    output logic [15:0]     o_sram_data
);

    // =========================================================================
    // AXI-LITE HANDSHAKE LOGIC
    // =========================================================================
    logic aw_en;
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            aw_en         <= 1'b1;
        end else begin
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else begin
                s_axi_awready <= 1'b0;
            end

            if (~s_axi_wready && s_axi_wvalid && s_axi_awvalid && aw_en) begin
                s_axi_wready <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end

            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
                aw_en <= 1'b1;
            end
        end
    end

    logic write_trigger;
    assign write_trigger = s_axi_awready && s_axi_wready && s_axi_awvalid && s_axi_wvalid;


    // =========================================================================
    // MEMORY MAP DECODING
    // =========================================================================
    // 0x0000 - 0x0FF8: Selector RAM
    // 0x0FFC: START Register
    // 0x1000 - 0x1FFF: Table 0 (min=0x1000, max=0x1100, base=0x1200, sym=0x1400)
    // 0x2000 - 0x2FFF: Table 1 ... up to 0x6000 for Table 5
    
    logic [3:0] block_sel;
    logic [3:0] array_sel;
    logic [7:0] index_sel;
    logic [2:0] tbl_idx;
    
    assign block_sel = s_axi_awaddr[15:12];
    assign array_sel = s_axi_awaddr[11:8];
    assign index_sel = s_axi_awaddr[9:2];
    assign tbl_idx   = block_sel[2:0] - 3'b001; // Maps 0x1000->0, 0x6000->5


    // =========================================================================
    // FLIP-FLOPS (Limits & Start Trigger)
    // =========================================================================
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            hw_start <= 1'b0;
            o_table_cfg <= '{default: '0};
        end else if (write_trigger) begin
            // Start Register
            if (s_axi_awaddr == 16'h0FFC) begin
                hw_start <= s_axi_wdata[0];
            end 
            // Configuration Limits (1 to 20)
            else if ((block_sel >= 4'h1) && (block_sel <= 4'h6) && (index_sel <= 8'd20)) begin
                case (array_sel)
                    4'h0: o_table_cfg[tbl_idx][index_sel].min_code <= s_axi_wdata[19:0];
                    4'h1: o_table_cfg[tbl_idx][index_sel].max_code <= s_axi_wdata[19:0];
                    4'h2: o_table_cfg[tbl_idx][index_sel].base_idx <= s_axi_wdata[8:0];
                endcase
            end
        end else begin
            hw_start <= 1'b0; // Pulse START for 1 cycle
        end
    end


    // =========================================================================
    // SRAM INSTANTIATIONS (Symbols and Selectors)
    // =========================================================================
    
    // --- 1. Selector RAM ---
    logic we_sel;
    logic [31:0] sel_dout;
    assign we_sel = write_trigger && (block_sel == 4'h0) && (s_axi_awaddr != 16'h0FFC);
    
    dual_port_ram #(.DATA_WIDTH(32), .ADDR_WIDTH(14)) sel_ram_inst (
        .clk    (s_axi_aclk),
        .we_a   (we_sel),
        .addr_a (s_axi_awaddr[15:2]),
        .din_a  (s_axi_wdata),
        .addr_b (i_sel_addr[13:0]),
        .dout_b (sel_dout)
    );
    assign o_sel_data = sel_dout[2:0];

    // --- 2. Symbol RAMs (6 independent tables) ---
    logic [5:0] we_sym;
    logic [31:0] sym_ram_dout [0:5];

    genvar i;
    generate
        for (i = 0; i < 6; i++) begin : SYM_RAM_GEN
            assign we_sym[i] = write_trigger && (block_sel == (i + 1)) && (array_sel == 4'h4);
            
            dual_port_ram #(.DATA_WIDTH(32), .ADDR_WIDTH(8)) sym_ram_inst (
                .clk    (s_axi_aclk),
                .we_a   (we_sym[i]),
                .addr_a (index_sel),
                .din_a  (s_axi_wdata),
                .addr_b (i_sram_addr),
                .dout_b (sym_ram_dout[i])
            );
        end
    endgenerate

    // Delay the active table selector by 1 cycle to match SRAM read latency
    logic [2:0] sram_tbl_sel_d1;
    always_ff @(posedge s_axi_aclk) begin
        if (i_sram_en) sram_tbl_sel_d1 <= i_sram_tbl_sel;
    end
    
    // Mux the SRAM outputs based on the delayed selector
    assign o_sram_data = sym_ram_dout[sram_tbl_sel_d1][15:0];

endmodule