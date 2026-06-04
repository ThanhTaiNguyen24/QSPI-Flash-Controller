`timescale 1ns/1ps

module apb_slave #(
    parameter APB_CLK = 20,
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32,
    parameter REG_NUM = 7
    )
    (
    input  logic                        pclk,        
    input  logic                        presetn,      
    input  logic                        psel,          
    input  logic                        penable,      
    input  logic                        pwrite,        
    input  logic  [ADDR_WIDTH - 1:0]    paddr,        
    input  logic  [DATA_WIDTH - 1:0]    pwdata,        // Write Data
    output logic  [DATA_WIDTH - 1:0]    prdata,        // Read Data
    output logic                        pready,        // Ready
    output logic                        pslverr,       // Error
    output logic                        start,
    output logic  [DATA_WIDTH - 1:0]    ctrl_reg,          
    output logic  [DATA_WIDTH - 1:0]    flash_addr_reg,
    output logic  [DATA_WIDTH - 1:0]    xfer_len_reg,
    input logic                         status_busy_cdc,
    input logic                         status_done_cdc,
    input logic                         status_error_cdc,
    input logic                         status_flash_busy_cdc
);
 
    logic s_idle;
    logic s_setup;
    logic s_access;
 
    apb_slave_fsm u_fsm (
        .pclk,
        .presetn,
        .psel,
        .pready,
        .penable,
        .s_idle,
        .s_setup,
        .s_access
    );
    reg_file u_regfile (
        .pclk,
        .presetn,
        .pwrite,
        .s_idle,
        .s_setup,
        .s_access,
        .status_busy_cdc,
        .status_done_cdc,
        .status_error_cdc,
        .status_flash_busy_cdc,
        .paddr,
        .pwdata,
        .prdata,
        .pready,
        .pslverr,
        .start,
        .ctrl_reg,
        .flash_addr_reg,
        .xfer_len_reg
    );
 
   
endmodule : apb_slave