`timescale 1ns/1ps

module axis_wr_if #(
    parameter DATA_WIDTH = 32
)(
    axis_if.slave                   axis_s, // Dùng modport slave
    
    // FIFO Interface
    input  logic                    wr_full,        
    output logic                    wr_en,          
    output logic [DATA_WIDTH-1:0]   wdata    
);
    localparam KEEP_WIDTH = DATA_WIDTH / 8;

    // Handshake
    assign axis_s.tready = ~wr_full;
    assign wr_en         = axis_s.tvalid & axis_s.tready;

    // Tkeep Base
    always_comb begin
        wdata = '0;
        for (int i = 0; i < KEEP_WIDTH; i++) begin
            if (axis_s.tkeep[i]) 
                wdata[i*8 +: 8] = axis_s.tdata[i*8 +: 8];
        end
    end
endmodule : axis_wr_if