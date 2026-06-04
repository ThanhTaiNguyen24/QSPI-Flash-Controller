`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/03/2026 04:39:03 PM
// Design Name: 
// Module Name: latch_on_start
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns/1ps

module latch_on_start #(
    parameter WIDTH = 32
)(
    input  wire             clk_ctrl,  
    input  wire             rst_n_ctrl,
   
    input  wire [WIDTH-1:0] reg_apb,        
    input  wire             start_pulse_cdc,
   
    output logic [WIDTH-1:0] reg_ctrl
);
 
    always_ff @(posedge clk_ctrl or negedge rst_n_ctrl) begin
        if (!rst_n_ctrl)
            reg_ctrl <= '0;
        else if (start_pulse_cdc)
            reg_ctrl <= reg_apb;  
    end
 
endmodule : latch_on_start
