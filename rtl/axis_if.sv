`timescale 1ns/1ps

interface axis_if #(parameter DATA_WIDTH = 32) (
    input logic clk,
    input logic reset_n
);
    localparam KEEP_WIDTH = DATA_WIDTH / 8;

    logic [DATA_WIDTH-1:0]  tdata;
    logic [KEEP_WIDTH-1:0]  tkeep;
    logic                   tvalid;
    logic                   tready;
    logic                   tlast;

    modport master (
        input  clk, reset_n, tready,
        output tdata, tkeep, tvalid, tlast
    );

    modport slave (
        input  clk, reset_n, tdata, tkeep, tvalid, tlast,
        output tready
    );
endinterface