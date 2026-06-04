`timescale 1ns/1ps

module reg_file #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32,
    parameter MAX_REG_ADDR = 8'h18,
    parameter MIN_REG_ADDR = 8'h00
)(
    input   logic                       pclk,          
    input   logic                       presetn,          
    input   logic                       pwrite,
    input   logic                       s_idle,
    input   logic                       s_setup,
    input   logic                       s_access,  
    input   logic                       status_busy_cdc,
    input   logic                       status_done_cdc,
    input   logic                       status_error_cdc,
    input   logic                       status_flash_busy_cdc,  
    input   logic  [ADDR_WIDTH - 1:0]   paddr,        
    input   logic  [DATA_WIDTH - 1:0]   pwdata,        
    output  logic  [DATA_WIDTH - 1:0]   prdata,        
    output  logic                       pready,        
    output  logic                       pslverr,
    output  logic                       start,
    output  logic  [DATA_WIDTH - 1:0]   ctrl_reg,          
    output  logic  [DATA_WIDTH - 1:0]   flash_addr_reg,
    output  logic  [DATA_WIDTH - 1:0]   xfer_len_reg
);
      localparam ADDR_CTRL        = 8'h00;
      localparam ADDR_STATUS      = 8'h04;
      localparam ADDR_FLASH_ADDR  = 8'h08;
      localparam ADDR_XFER_LEN    = 8'h0C;
      localparam ADDR_INTR_EN     = 8'h10;
      localparam ADDR_INTR_STATUS = 8'h14;
      localparam ADDR_FLASH_SR1   = 8'h18;
      localparam CTRL_POS_START   = 0;
      localparam CTRL_MASK_START = (1 << CTRL_POS_START);
    // =========================================================
    // Internal Register Storage
    // =========================================================
    // logic           [DATA_WIDTH - 1:0]  ctrl_reg;          
    logic           [DATA_WIDTH - 1:0]  status_reg;  
    // logic           [DATA_WIDTH - 1:0]  flash_addr_reg;
    // logic           [DATA_WIDTH - 1:0]  xfer_len_reg;
    logic           [DATA_WIDTH - 1:0]  intr_en_reg;
    logic           [DATA_WIDTH - 1:0]  intr_status_reg;
    logic           [DATA_WIDTH - 1:0]  setup_reg;
 
    logic           [DATA_WIDTH - 1:0]  n_ctrl_reg;          
    logic           [DATA_WIDTH - 1:0]  n_status_reg;  
    logic           [DATA_WIDTH - 1:0]  n_flash_addr_reg;
    logic           [DATA_WIDTH - 1:0]  n_xfer_len_reg;
    logic           [DATA_WIDTH - 1:0]  n_intr_en_reg;
    logic           [DATA_WIDTH - 1:0]  n_intr_status_reg;
    logic           [DATA_WIDTH - 1:0]  n_setup_reg;
 
    logic  [DATA_WIDTH - 1:0]   n_prdata;        
    logic                       n_pready;        
    logic                       n_pslverr;
    logic                       n_start;
 
    logic   [1:0]               cycle_count;
    logic                       ctrl_start_prev;
    // =========================================================
    // Address Validation
    // =========================================================
    logic xfer_len_reg_err;
    logic addr_valid;
 
    assign addr_valid = (paddr >= MIN_REG_ADDR && paddr <= MAX_REG_ADDR)
                      && (paddr[1:0] == 2'b00);
    //Xfer_len must be multiple of 4
    assign xfer_len_reg_err = !pwrite || (paddr != ADDR_XFER_LEN) || (pwdata[1:0] == 2'b00);
 
    // =========================================================
    // Setup Phase: Check Address and Prepare Register
    // =========================================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            setup_reg <= '0;
        end else begin
            setup_reg <= n_setup_reg;
        end
    end
 
    always_comb begin
        if (s_setup && !pwrite) begin
            unique case (paddr)
                ADDR_CTRL:
                    n_setup_reg = ctrl_reg;
                ADDR_STATUS:
                    n_setup_reg = status_reg;
                ADDR_FLASH_ADDR:
                    n_setup_reg = flash_addr_reg;
                ADDR_XFER_LEN:
                    n_setup_reg = xfer_len_reg;
                ADDR_INTR_EN:
                    n_setup_reg = intr_en_reg;
                ADDR_INTR_STATUS:
                    n_setup_reg = intr_status_reg;
                default: n_setup_reg = '0;
            endcase
        end
    end
 
    // =========================================================
    // Read Phase
    // =========================================================
    always_comb begin
        prdata   = '0;
        pready   = 1'b0;
        pslverr  = 1'b0;
       
        if (s_access) begin
            if(cycle_count >= 2) begin
                pready = 1'b1;
            end
            if (!addr_valid) begin
                pslverr = 1'b1;  
            end else if (pwrite && paddr == ADDR_XFER_LEN) begin
                if (pwdata[1:0] != 2'b00 || pwdata == 32'd0) begin
                    pslverr = 1'b1;
                end
            end
            if (addr_valid && !pwrite) begin
                prdata = setup_reg;
            end
        end
    end
 
    // =========================================================
    // Write Phase: Register Storage
    // =========================================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl_reg         <= '0;
            flash_addr_reg   <= '0;
            xfer_len_reg     <= '0;
            intr_en_reg      <= '0;
            intr_status_reg  <= '0;
            status_reg       <= '0;
        end else begin
            ctrl_reg         <= n_ctrl_reg;
            flash_addr_reg   <= n_flash_addr_reg;
            xfer_len_reg     <= n_xfer_len_reg;
            intr_en_reg      <= n_intr_en_reg;
            intr_status_reg  <= n_intr_status_reg;
            status_reg       <= n_status_reg;
        end
    end
 
    always_comb begin
        n_ctrl_reg          = ctrl_reg;
        if (status_busy_cdc) begin
            n_ctrl_reg[CTRL_POS_START] = '0;
        end
        n_flash_addr_reg    = flash_addr_reg;
        n_xfer_len_reg      = xfer_len_reg;
        n_intr_en_reg       = intr_en_reg;
        n_intr_status_reg   = intr_status_reg;
        n_status_reg        = {28'd0, status_flash_busy_cdc, status_error_cdc, status_done_cdc, status_busy_cdc};
        if (pwrite && s_access && addr_valid) begin
            unique case (paddr)
                ADDR_CTRL:
                    if(pwdata[0]) begin
                        n_ctrl_reg = (ctrl_reg & ~CTRL_MASK_START) | (pwdata & CTRL_MASK_START);
                    end else begin
                        n_ctrl_reg = pwdata;
                    end
               
                ADDR_FLASH_ADDR:
                    n_flash_addr_reg = pwdata;
               
                ADDR_XFER_LEN:
                    if (pwdata[1:0] == 2'b00 && pwdata != 0)
                        n_xfer_len_reg = pwdata;
                ADDR_INTR_EN:
                    n_intr_en_reg = pwdata;
               
                ADDR_INTR_STATUS: begin
                    n_intr_status_reg = intr_status_reg & ~pwdata;
                end  
                default: ;
            endcase
        end
    end
 
 
    // =========================================================
    // Start Pulse
    // =========================================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            start           <= 1'b0;
            ctrl_start_prev <= 1'b0;
            cycle_count     <= 2'd0;
        end else begin
            ctrl_start_prev <= ctrl_reg[0];  
            cycle_count     <= (cycle_count == 2'd2) ? 2'd0 : cycle_count + 2'd1;
           
            start <= (ctrl_reg[0] && !ctrl_start_prev);
        end
    end
endmodule
