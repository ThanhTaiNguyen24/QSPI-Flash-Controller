`timescale 1ns/1ps

module pulse_sync (
    input logic clk_src, rst_n_src,
    input logic clk_dst, rst_n_dst,
    input logic pulse_in,
    output logic pulse_out
);
 
    logic toggle_src, sync_dst, sync_dst_d;
 
    always_ff @(posedge clk_src or negedge rst_n_src) begin
        if (!rst_n_src) toggle_src <= 1'b0;
        else if (pulse_in) toggle_src <= ~toggle_src;
    end
 
    sync_2ff u_sync (.clk_dst, .rst_n_dst, .d_in(toggle_src), .d_out (sync_dst) );
 
    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) sync_dst_d <= 1'b0;
        else sync_dst_d <= sync_dst;
    end
    
    assign pulse_out = sync_dst ^ sync_dst_d;
    
endmodule
