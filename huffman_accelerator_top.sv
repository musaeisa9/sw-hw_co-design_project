import huffman_pkg::*;

module huffman_accelerator_top #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 16
)(
    input  logic aclk,
    input  logic aresetn,

    // 1. AXI-Lite Slave Interface (From CPU)
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,

    // 2. AXI-Stream Slave Interface (Bitstream from TX DMA)
    input  logic [31:0] s_axis_tdata,
    input  logic [3:0]  s_axis_tkeep,
    input  logic s_axis_tlast,
    input  logic s_axis_tvalid,
    output logic s_axis_tready,

    // 3. AXI-Stream Master Interface (Decoded Symbols to RX DMA)
    output logic [15:0] m_axis_tdata, 
    output logic [1:0]  m_axis_tkeep,
    output logic m_axis_tlast,
    output logic m_axis_tvalid,
    input  logic m_axis_tready
);

    // --- Internal Routing Wires ---
    logic hw_start;
    huff_cfg_array_t table_cfg;
    
    logic [15:0] sel_addr;
    logic [2:0]  sel_data;
    
    logic [2:0]  sram_tbl_sel;
    logic [7:0]  sram_addr;
    logic        sram_en;
    logic [15:0] sram_data;
    
    logic core_done;

    // --- Hardwired AXI-Stream Attributes ---
    // We are always outputting 16-bit valid integers (2 bytes)
    assign m_axis_tkeep = 2'b11; 
    assign m_axis_tlast = core_done;

    // =========================================================================
    // INSTANTIATE: Control Plane (AXI-Lite Slave + Memories)
    // =========================================================================
    huffman_axi_lite_slv #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) ctrl_plane_inst (
        .s_axi_aclk     (aclk),
        .s_axi_aresetn  (aresetn),
        
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        
        .hw_start       (hw_start),
        .o_table_cfg    (table_cfg),
        
        .i_sel_addr     (sel_addr),
        .o_sel_data     (sel_data),
        
        .i_sram_tbl_sel (sram_tbl_sel),
        .i_sram_addr    (sram_addr),
        .i_sram_en      (sram_en),
        .o_sram_data    (sram_data)
    );

    // =========================================================================
    // INSTANTIATE: Data Plane (Huffman Algorithm Core)
    // =========================================================================
    huffman_core data_plane_inst (
        .clk            (aclk),
        .rst_n          (aresetn),
        
        .i_start        (hw_start),
        .o_done         (core_done),
        
        .i_table_cfg    (table_cfg),
        
        .o_sel_addr     (sel_addr),
        .i_sel_data     (sel_data),
        
        .i_data         (s_axis_tdata),
        .i_valid        (s_axis_tvalid),
        .o_ready        (s_axis_tready),
        
        .o_sram_tbl_sel (sram_tbl_sel),
        .o_sram_addr    (sram_addr),
        .o_sram_en      (sram_en),
        .i_sram_data    (sram_data),
        
        .o_symbol       (m_axis_tdata),
        .o_valid        (m_axis_tvalid)
        // Note: Assumes RX DMA is always ready. In a production IP, 
        // m_axis_tready would be wired back to stall the sliding window.
    );

endmodule