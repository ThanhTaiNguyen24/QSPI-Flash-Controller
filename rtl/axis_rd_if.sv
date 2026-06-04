`timescale 1ns/1ps

module axis_rd_if #(
    parameter DATA_WIDTH = 32
)(
    axis_if.master                  axis_m, // Dùng modport master
    
    // Control & Config
    input  logic [31:0]             xfer_len_axi, 
    
    // FIFO Interface
    input  logic                    rd_empty,      
    output logic                    rd_en,      
    input  logic [DATA_WIDTH-1:0]   rdata    
);

    logic [15:0] total_words;
    assign total_words = xfer_len_axi[15:0] >> 2; 

    logic [15:0] c_cnt, n_cnt;

    assign axis_m.tvalid = ~rd_empty;
    assign rd_en         = axis_m.tvalid & axis_m.tready;
    assign axis_m.tdata  = rdata;
    assign axis_m.tkeep  = '1; 

    always_comb begin
        n_cnt = c_cnt;
        if (axis_m.tvalid & axis_m.tready) begin
            if (c_cnt >= total_words - 1)
                n_cnt = 16'd0;
            else
                n_cnt = c_cnt + 1'b1;
        end
    end

    always_ff @(posedge axis_m.clk or negedge axis_m.reset_n) begin
        if (!axis_m.reset_n) 
            c_cnt <= 16'd0;
        else               
            c_cnt <= n_cnt;
    end

    assign axis_m.tlast = (c_cnt == total_words - 1) && axis_m.tvalid;

endmodule : axis_rd_if