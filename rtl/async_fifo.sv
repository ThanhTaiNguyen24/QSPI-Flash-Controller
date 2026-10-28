`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 16,            
    parameter ADDR_WIDTH = $clog2(DEPTH) // 4 for DEPTH=16
)(
    // Write Domain (100MHz AXI)
    input  wire                     wclk,    
    input  wire                     wrst_n,
    input  wire  [DATA_WIDTH-1:0]   wdata,
    input  wire                     wr_en,
    output wire                     wr_full,
   
    // Read Domain (133MHz CTRL/Flash)
    input  wire                     rclk,    
    input  wire                     rrst_n,
    output wire  [DATA_WIDTH-1:0]   rdata,
    input  wire                     rd_en,
    output wire                     rd_empty
);
   
    // Pointer Registers (addition wrap-around bit)
    logic [ADDR_WIDTH:0] c_wptr;
    logic [ADDR_WIDTH:0] n_wptr;
    logic [ADDR_WIDTH:0] c_rptr;
    logic [ADDR_WIDTH:0] n_rptr;
    
    logic [ADDR_WIDTH:0] wptr_gray;
    logic [ADDR_WIDTH:0] rptr_gray;
    
    // CDC Synchronization
    logic [ADDR_WIDTH:0] rptr_gray_synced;
    logic [ADDR_WIDTH:0] wptr_gray_synced;
    
    // Write Pointer
    always_comb begin
        if (wr_en && !wr_full) begin
            n_wptr = c_wptr + 1'b1;
        end else begin
            n_wptr = c_wptr;
        end
    end
 
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            c_wptr <= '0;
        end else begin
            c_wptr <= n_wptr;
        end
    end
    
    // Read Pointer
    always_comb begin
        if (rd_en && !rd_empty) begin
            n_rptr = c_rptr + 1'b1;
        end else begin
            n_rptr = c_rptr;
        end
    end
 
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            c_rptr <= '0;
        end else begin
            c_rptr <= n_rptr;
        end
    end
    
    // Binary to Gray 
    assign wptr_gray = c_wptr ^ (c_wptr >> 1);
    assign rptr_gray = c_rptr ^ (c_rptr >> 1);
 
    sync_2ff #(.WIDTH(ADDR_WIDTH + 1)) u_rptr_sync (
        .clk_dst(wclk),
        .rst_n_dst(wrst_n),
        .d_in(rptr_gray),
        .d_out(rptr_gray_synced)
    );
   
    sync_2ff #(.WIDTH(ADDR_WIDTH + 1)) u_wptr_sync (
        .clk_dst(rclk),
        .rst_n_dst(rrst_n),
        .d_in(wptr_gray),
        .d_out(wptr_gray_synced)
    );
  
    // Status Logic
    // Empty
    assign rd_empty = (wptr_gray_synced == rptr_gray);

    // Full: NOT first 2 MSB bits, last 3 bits are equal
    assign wr_full = (wptr_gray == {~rptr_gray_synced[ADDR_WIDTH:ADDR_WIDTH-1], 
                                     rptr_gray_synced[ADDR_WIDTH-2:0]});
   
    // Flip-Flop Based Memory
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
 
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin

        end else begin
            // Write operation
            if (wr_en && !wr_full) begin
                mem[c_wptr[ADDR_WIDTH-1:0]] <= wdata;
            end
        end
    end
    
    assign rdata = mem[c_rptr[ADDR_WIDTH-1:0]];
    
endmodule : async_fifo