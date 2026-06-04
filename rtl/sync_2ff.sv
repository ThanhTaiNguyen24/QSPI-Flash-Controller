`timescale 1ns/1ps

module sync_2ff #(parameter WIDTH = 1) (
    input  logic          clk_dst,
    input  logic          rst_n_dst,
    input  logic [WIDTH-1:0] d_in,
    output logic [WIDTH-1:0] d_out
);
 
    // CDC internal registers
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] ff1;
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] ff2;
 
    // First Flip-Flop Stage (Input Capture)
    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) begin
            ff1 <= {WIDTH{1'b0}};
            ff2 <= {WIDTH{1'b0}};
        end else begin
            ff1 <= d_in;
            ff2 <= ff1;
        end
    end
 
    // Output Assignment
    assign d_out = ff2;
 
endmodule : sync_2ff