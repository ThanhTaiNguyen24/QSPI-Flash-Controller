`timescale 1ns/1ps

module rst_sync #(parameter STAGES = 2)( 
    input  logic clk_dst,      
    input  logic rst_in_n,    
    output logic rst_out_n
);
    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] rst_pipe;
    
    always_ff @(posedge clk_dst or negedge rst_in_n) begin
        if (!rst_in_n) rst_pipe <= '0;
        else           rst_pipe <= {rst_pipe[STAGES-2:0], 1'b1};
    end
    
    assign rst_out_n = rst_pipe[STAGES - 1];
 
endmodule: rst_sync