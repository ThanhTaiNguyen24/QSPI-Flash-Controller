`timescale 1ns/1ps
 
module qspi_flash_top #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH_APB = 12,
    parameter TKEEP_WIDTH = DATA_WIDTH/8
) (
    // ──────────────── CLOCK & RESET DOMAINS ────────────────
    input  logic                            clk_apb,          
    input  logic                            clk_ctrl,        
    input  logic                            pclk_reset_n,    
    input  logic                            clk_axi,
   
    // ──────────────── APB BUS INTERFACE ────────────────
    input  logic                            psel,          
    input  logic                            penable,      
    input  logic                            pwrite,        
    input  logic  [ADDR_WIDTH_APB - 1:0]    paddr,        
    input  logic  [DATA_WIDTH - 1:0]        pwdata,        
    output logic  [DATA_WIDTH - 1:0]        prdata,        
    output logic                            pready,        
    output logic                            pslverr,      
   
//    // ──────────────── TEST INTERFACE ────────────────
//    input  logic  [DATA_WIDTH-1:0]          wr_fifo_rdata,        
//    output logic                            wr_fifo_rd_en,      
//    input  logic                            wr_fifo_empty,      
   
//    output logic  [DATA_WIDTH-1:0]          rd_fifo_wdata,        
//    output logic                            rd_fifo_wr_en,      
//    input  logic                            rd_fifo_full,  
    // ──────────────── QSPI INTERFACE ────────────────
    output logic                            sck,
    output logic                            CSn,
    inout  logic  [3:0]                     io,
 
    // ──────────────── AXIS INTERFACE (SLAVE) ────────────────
    input  logic                            s_axis_tvalid,
    output logic                            s_axis_tready,
    input  logic  [DATA_WIDTH-1:0]          s_axis_tdata,
    input  logic  [TKEEP_WIDTH-1:0]         s_axis_tkeep,
    input  logic                            s_axis_tlast,

    // ──────────────── AXIS INTERFACE (MASTER) ────────────────
    output logic                            m_axis_tvalid,
    input  logic                            m_axis_tready,
    output logic  [DATA_WIDTH-1:0]          m_axis_tdata,
    output logic  [TKEEP_WIDTH-1:0]         m_axis_tkeep,
    output logic                            m_axis_tlast
);
// ====================================================================
// INTERNAL SIGNALS DECLARATION
// ====================================================================
 
    // APB Side Registers
    logic [31:0]            ctrl_reg_apb;
    logic [31:0]            flash_addr_apb;
    logic [31:0]            xfer_len_apb;
 
    // Controller Side Registers (CDC on Latch APB -> CTRL)
    logic [31:0]            ctrl_reg_ctrl;
    logic [31:0]            flash_addr_ctrl;
    logic [31:0]            xfer_len_ctrl;
 
    // Status Signals (CDC CTRL -> APB)
    logic                   status_busy;        
    logic                   status_done;        
    logic                   status_error;      
    logic                   status_flash_busy;  
 
    // CDC Status Signals (Synced to APB Domain)
    logic                   status_busy_cdc;
    logic                   status_done_cdc;
    logic                   status_error_cdc;
    logic                   status_flash_busy_cdc;
 
    // Start Pulse (Pulse Sync APB -> CTRL)
    logic                   start_from_apb;  
    logic                   start_pulse_cdc;      
 
    // Internal Reset Synchronization
    logic                   cclk_reset_n;        
 
    // FSM <-> QSPI Phy Control Signals
    logic                   qspi_start;
    logic                   qspi_byte_done;
    logic                   CSn_internal;
    logic [7:0]             tx_payload;            
    logic [7:0]             rx_payload;        
    logic [15:0]            xfer_len_fsm;    
 
    //AXI4-Stream  
    logic [DATA_WIDTH-1:0]  wdata_m_s;
    logic                   wr_en_m_s;
    logic                   wr_full_m_s;
    logic [DATA_WIDTH-1:0]  rdata_m_s;
    logic                   rd_en_m_s;
    logic                   rd_empty_m_s;
 
    logic [DATA_WIDTH-1:0]  wdata_s_m;
    logic                   wr_en_s_m;
    logic                   wr_full_s_m;
    logic [DATA_WIDTH-1:0]  rdata_s_m;
    logic                   rd_en_s_m;
    logic                   rd_empty_s_m;
    
    axis_if #(.DATA_WIDTH(DATA_WIDTH)) axis_s_int (.clk(clk_axi), .reset_n(pclk_reset_n));
    axis_if #(.DATA_WIDTH(DATA_WIDTH)) axis_m_int (.clk(clk_axi), .reset_n(pclk_reset_n));

    assign axis_s_int.tvalid = s_axis_tvalid;
    assign axis_s_int.tdata  = s_axis_tdata;
    assign axis_s_int.tkeep  = s_axis_tkeep;
    assign axis_s_int.tlast  = s_axis_tlast;
    assign s_axis_tready     = axis_s_int.tready;

    assign m_axis_tvalid     = axis_m_int.tvalid;
    assign m_axis_tdata      = axis_m_int.tdata;
    assign m_axis_tkeep      = axis_m_int.tkeep;
    assign m_axis_tlast      = axis_m_int.tlast;
    assign axis_m_int.tready = m_axis_tready;

    // Tín hiệu cho AXI CDC
    logic                   start_pulse_axi;
    logic [31:0]            xfer_len_axi;
 
// ====================================================================
// REGISTER FILE & APB SLAVE
// ====================================================================
 
    apb_slave u_apb_slave (
        .pclk(clk_apb),        
        .presetn(pclk_reset_n),      
        .psel,          
        .penable,      
        .pwrite,        
        .paddr,        
        .pwdata,        
        .prdata,        
        .pready,        
        .pslverr,      
        .start(start_from_apb),
        .status_busy_cdc,
        .status_done_cdc,
        .status_error_cdc,
        .status_flash_busy_cdc,
        .ctrl_reg(ctrl_reg_apb),
        .flash_addr_reg(flash_addr_apb),
        .xfer_len_reg(xfer_len_apb)
    );
 
    // ====================================================================
    // CLOCK DOMAIN CROSSING (CDC) MODULES
    // ====================================================================
    // Pulse synchronization: APB→CTRL
    pulse_sync u_pulse_sync (
        .clk_src(clk_apb),          
        .rst_n_src(pclk_reset_n),  
        .clk_dst(clk_ctrl),        
        .rst_n_dst(cclk_reset_n),  
        .pulse_in(start_from_apb),
        .pulse_out(start_pulse_cdc)
    );
    // 2-Flip-Flop synchronizers for status signals: CTRL→APB
    sync_2ff u_busy (
        .clk_dst(clk_apb),
        .rst_n_dst(pclk_reset_n),
        .d_in(status_busy),
        .d_out(status_busy_cdc)
    );
    sync_2ff u_done (
        .clk_dst(clk_apb),
        .rst_n_dst(pclk_reset_n),
        .d_in(status_done),
        .d_out(status_done_cdc)
    );
    sync_2ff u_error (
        .clk_dst(clk_apb),
        .rst_n_dst(pclk_reset_n),
        .d_in(status_error),
        .d_out(status_error_cdc)
    );
    sync_2ff u_flash_busy (
        .clk_dst(clk_apb),
        .rst_n_dst(pclk_reset_n),
        .d_in(status_flash_busy),
        .d_out(status_flash_busy_cdc)
    );
    rst_sync u_reset_cdc(
        .clk_dst(clk_ctrl),
        .rst_in_n(pclk_reset_n),
        .rst_out_n(cclk_reset_n)
    );
    // Register Capture on START PULSE (Latch APB -> CTRL)
    latch_on_start u_ctrl_cdc (
        .clk_ctrl(clk_ctrl),              
        .rst_n_ctrl(cclk_reset_n),
        .reg_apb(ctrl_reg_apb),        
        .start_pulse_cdc(start_pulse_cdc),
        .reg_ctrl(ctrl_reg_ctrl)
    );
   
    latch_on_start u_addr_cdc (
        .clk_ctrl(clk_ctrl),
        .rst_n_ctrl(cclk_reset_n),
        .reg_apb(flash_addr_apb),
        .start_pulse_cdc(start_pulse_cdc),
        .reg_ctrl(flash_addr_ctrl)
    );
   
    latch_on_start u_len_cdc (
        .clk_ctrl(clk_ctrl),
        .rst_n_ctrl(cclk_reset_n),
        .reg_apb(xfer_len_apb),
        .start_pulse_cdc(start_pulse_cdc),
        .reg_ctrl(xfer_len_ctrl)
    );
   
   // ──────────────── CDC for CLK_AXI ────────────────
    pulse_sync u_pulse_sync_axi (
        .clk_src(clk_apb),          
        .rst_n_src(pclk_reset_n),  
        .clk_dst(clk_axi),        
        .rst_n_dst(pclk_reset_n),  
        .pulse_in(start_from_apb),
        .pulse_out(start_pulse_axi)
    );

    latch_on_start u_len_axi_cdc (
        .clk_ctrl(clk_axi),              
        .rst_n_ctrl(pclk_reset_n),
        .reg_apb(xfer_len_apb),        
        .start_pulse_cdc(start_pulse_axi),
        .reg_ctrl(xfer_len_axi)
    );
    // ====================================================================
    // CORE FSM INSTANTIATION
    // ====================================================================
    ctrl_fsm u_ctrl_fsm (
        .clk_ctrl(clk_ctrl),
        .reset_n(cclk_reset_n),
       
        // Register inputs (captured via CDC)
        .ctrl_reg(ctrl_reg_ctrl),
        .flash_addr_in(flash_addr_ctrl),
        .xfer_len_in(xfer_len_ctrl),
        .start_pulse(start_pulse_cdc),
       
        // Status outputs (go to CDC sync stage)
        .busy_out(status_busy),
        .done_out(status_done),
        .error_out(status_error),
        .flash_busy_poll(status_flash_busy),  
       
        // QSPI Physical Interface Control
        .qspi_start(qspi_start),
        .tx_payload(tx_payload),
        .CSn(CSn_internal),
        .rx_payload(rx_payload),
        .qspi_byte_done(qspi_byte_done),
        .xfer_len(xfer_len_fsm),
       
//        .wr_fifo_rdata(wr_fifo_rdata),
//        .wr_fifo_rd_en(wr_fifo_rd_en),
//        .wr_fifo_empty(wr_fifo_empty),
//        .rd_fifo_wdata(rd_fifo_wdata),
//        .rd_fifo_wr_en(rd_fifo_wr_en),
//        .rd_fifo_full(rd_fifo_full)
        // FIFO Placeholders
        .wr_fifo_rdata(rdata_m_s),
        .wr_fifo_rd_en(rd_en_m_s),
        .wr_fifo_empty(rd_empty_m_s),
        .rd_fifo_wdata(wdata_s_m),
        .rd_fifo_wr_en(wr_en_s_m),
        .rd_fifo_full(wr_full_s_m)
    );
 
 
    // ====================================================================
    // QSPI PHYSICAL LAYER INSTANTIATION
    // ====================================================================
 
    qspi_phy u_qspi_phy (
        .clk_ctrl(clk_ctrl),
        .reset_n(cclk_reset_n),
        .sck(sck),
        .CSn(CSn),              
        .io(io),              
        .qspi_start(qspi_start),
        .tx_payload(tx_payload),
        .CSn_in(CSn_internal),
        .xfer_len(xfer_len_fsm),
        .rx_payload(rx_payload),
        .qspi_byte_done(qspi_byte_done)
    );
 
    // ====================================================================
    // AXI4-STREAM INSTANTIATION
    // ====================================================================

    async_fifo u_async_fifo_wr (
        .wclk(clk_axi),
        .wrst_n(pclk_reset_n),
        .wdata(wdata_m_s),
        .wr_en(wr_en_m_s),
        .wr_full(wr_full_m_s),
        .rclk(clk_ctrl),
        .rrst_n(cclk_reset_n),
        .rdata(rdata_m_s),
        .rd_en(rd_en_m_s),
        .rd_empty(rd_empty_m_s)
    );
 
 
    async_fifo u_async_fifo_rd (
        .wclk(clk_ctrl),
        .wrst_n(cclk_reset_n),
        .wdata(wdata_s_m),
        .wr_en(wr_en_s_m),
        .wr_full(wr_full_s_m),
        .rclk(clk_axi),
        .rrst_n(pclk_reset_n),
        .rdata(rdata_s_m),
        .rd_en(rd_en_s_m),
        .rd_empty(rd_empty_s_m)
    );
    
    axis_wr_if #(.DATA_WIDTH(DATA_WIDTH)) u_axis_wr (
        .axis_s     (axis_s_int.slave),
        .wr_full    (wr_full_m_s),
        .wr_en      (wr_en_m_s),
        .wdata      (wdata_m_s)
    );

    axis_rd_if #(.DATA_WIDTH(DATA_WIDTH)) u_axis_rd (
        .axis_m       (axis_m_int.master),
        .xfer_len_axi (xfer_len_axi),
        .rd_empty     (rd_empty_s_m),
        .rd_en        (rd_en_s_m),
        .rdata        (rdata_s_m)
    );
endmodule
