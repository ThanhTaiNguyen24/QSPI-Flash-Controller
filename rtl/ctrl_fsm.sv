`timescale 1ns/1ps
 
module ctrl_fsm #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 24,
    parameter TRANSFER_WIDTH = 16,
    parameter PAYLOAD_WIDTH = 8,
    // Flash Command Opcodes
    parameter OPCODE_FAST_READ       = 8'h0B,
    parameter OPCODE_PAGE_PROGRAM    = 8'h02,
    parameter OPCODE_SECTOR_ERASE    = 8'h20,
    parameter OPCODE_BLOCK_ERASE     = 8'hD8,
    parameter OPCODE_WRITE_ENABLE    = 8'h06,
    parameter OPCODE_READ_STATUS     = 8'h05,
   
    // Timing Parameters (at 133MHz)
    parameter NS_10_USR_CTRL_FREQ      = 2,   // For tSHSL1 ≥ 10ns (~13 cycles)
    parameter NS_50_USR_CTRL_FREQ      = 7,   // For tSHSL2 ≥ 50ns (~67 cycles)
    parameter POLL_TIMEOUT_MAX         = 16'h1F40 // ~5ms timeout
)(
    input  logic                        clk_ctrl,
    input  logic                        reset_n,
    // =========================================================
    // Latched Signal on Start Pulse
    // =========================================================
    input  logic [DATA_WIDTH-1:0]       ctrl_reg,
    input  logic [DATA_WIDTH-1:0]       flash_addr_in,
    input  logic [DATA_WIDTH-1:0]       xfer_len_in,
   
    // Control Signals APB CLK <-> CTRL_CLK
    input  logic                        start_pulse,
    output logic                        busy_out,
    output logic                        done_out,
    output logic                        error_out,
    output logic                        flash_busy_poll,
   
    // Handshake to qspi_ctrl/phy
    output logic                        qspi_start,
    output logic  [PAYLOAD_WIDTH-1:0]   tx_payload,
    output logic                        CSn,
    input  logic [PAYLOAD_WIDTH-1:0]    rx_payload,
   
    // Status Feedback
    input  logic                        qspi_byte_done,
    //Data length
    output logic [TRANSFER_WIDTH-1:0]   xfer_len,
    // Read FIFO (to get data for FLASH_WRITE)
    input  logic  [DATA_WIDTH-1:0]      wr_fifo_rdata,        // Data ready from wr_dc_fifo
    output logic                        wr_fifo_rd_en,        // Enable read from FIFO
    input  logic                        wr_fifo_empty,        // FIFO empty flag
   
    // Write FIFO (to push data from FLASH_READ)  
    output logic  [DATA_WIDTH-1:0]      rd_fifo_wdata,        // Data to write into FIFO
    output logic                        rd_fifo_wr_en,        // Enable write to FIFO
    input  logic                        rd_fifo_full    
);
    typedef enum logic [3:0] {
        ST_IDLE          = 4'd0,
        ST_ISSUE_WEL     = 4'd1,
        ST_WAIT_WEL_CS   = 4'd2,
        ST_SEND_CMD      = 4'd3,
        ST_SEND_ADDR     = 4'd4,
        ST_SEND_DUMMY    = 4'd5,
        ST_DATA_READ     = 4'd6,
        ST_DATA_WRITE    = 4'd7,
        ST_DEASSERT_CS   = 4'd8,
        ST_POLL_STATUS   = 4'd9,
        ST_DONE          = 4'd10,
        ST_ERROR         = 4'd11
    } state_t;
 
    state_t state_curr, state_next;
   
    // Internal Signal Storage
    logic                           op_mode_read;
    logic                           op_mode_write;
    logic                           erase_op;
    logic                           erase_type;
    logic                           quad_en;
    logic                           addr_4b;
    logic   [ADDR_WIDTH-1:0]        flash_addr;
    logic                           needs_wel;
    logic   [PAYLOAD_WIDTH-1:0]     cmd_opcode;
    logic                           start_valid;
    //Counters
    logic   [2:0]                   c_addr_byte_cnt;      // For address bytes (max 3)
    logic   [2:0]                   n_addr_byte_cnt;
    logic   [TRANSFER_WIDTH-1:0]    c_data_byte_cnt;      // For data bytes (max XFER_LEN)
    logic   [TRANSFER_WIDTH-1:0]    n_data_byte_cnt;
 
    //Timers
    logic   [7:0]                   c_timer_counter;      // For tSHSL1/tSHSL2
    logic   [7:0]                   n_timer_counter;
    logic                           c_timer_valid;        // Timer run flag
    logic                           n_timer_valid;
    logic   [15:0]                  c_poll_timeout_cnt;   // For polling timeout
    logic   [15:0]                  n_poll_timeout_cnt;
    logic                           timer_done_flag;
    logic                           poll_timeout_done_flag;
    logic                           cmd_flag;
   
    //Byte Offset for FIFO Data
    logic   [1:0]                   c_wr_byte_offset;
    logic   [1:0]                   n_wr_byte_offset;
 
    logic   [1:0]                   c_rd_byte_offset;
    logic   [1:0]                   n_rd_byte_offset;
 
    logic   [31:0]                  c_rx_word_buffer;
    logic   [31:0]                  n_rx_word_buffer;
    
    logic                           n_rd_fifo_wr_en;
    logic                           c_rd_fifo_wr_en;
    //CDC Latch Parameters Capture
    // always_ff @(posedge clk_ctrl or negedge reset_n) begin
    //     if (!reset_n) begin
    //         op_mode_read <= 1'b0;
    //         op_mode_write <= 1'b0;
    //         erase_op     <= 1'b0;
    //         erase_type   <= 1'b0;
    //         quad_en      <= 1'b0;
    //         addr_4b      <= 1'b0;
    //         flash_addr   <= 24'd0;
    //         xfer_len     <= 16'd0;
    //     end else if (start_pulse) begin
    //         op_mode_read  <= ~ctrl_reg[1];
    //         op_mode_write <= ctrl_reg[1];
    //         erase_op     <= ctrl_reg[2];
    //         erase_type   <= ctrl_reg[3];
    //         quad_en      <= ctrl_reg[4];
    //         addr_4b      <= ctrl_reg[5];
    //         flash_addr   <= flash_addr_in[23:0];
    //         xfer_len     <= xfer_len_in;
       
    //     end
    // end
    assign op_mode_read = ~ctrl_reg[1];
    assign op_mode_write = ctrl_reg[1];
    assign erase_op = ctrl_reg[2];
    assign erase_type = ctrl_reg[3];
    assign quad_en = ctrl_reg[4];
    assign addr_4b = ctrl_reg[5];
    assign flash_addr = flash_addr_in[ADDR_WIDTH-1:0];
    assign xfer_len = xfer_len_in[TRANSFER_WIDTH-1:0];
 
    always_comb begin
        if (erase_op) begin
            cmd_opcode = erase_type ? OPCODE_BLOCK_ERASE : OPCODE_SECTOR_ERASE;
        end else if (op_mode_write) begin
            cmd_opcode = OPCODE_PAGE_PROGRAM;
        end else begin
            cmd_opcode = OPCODE_FAST_READ;
        end
    end
 
    assign needs_wel = (cmd_opcode != OPCODE_FAST_READ);
 
    always_ff @(posedge clk_ctrl or negedge reset_n) begin
        if (!reset_n) begin
            state_curr <= ST_IDLE;
            start_valid <= 1'b0;
        end else begin
            state_curr <= state_next;
            start_valid <= start_pulse;
        end
    end
    assign busy_out = (state_curr != ST_IDLE && state_curr != ST_DONE && state_curr != ST_ERROR);
 
    //FSM Next State Logic
    always_comb begin
        state_next = state_curr;
       
        unique case (state_curr)
            ST_IDLE: begin
                if (start_valid) begin
                    if (needs_wel)
                        state_next = ST_ISSUE_WEL;
                    else
                        state_next = ST_SEND_CMD;
                end
            end
           
            ST_ISSUE_WEL: begin
                if (qspi_byte_done)
                    state_next = ST_WAIT_WEL_CS;
            end
           
            ST_WAIT_WEL_CS: begin
                if (timer_done_flag)
                    state_next = ST_SEND_CMD;
            end
           
            ST_SEND_CMD: begin
                if (qspi_byte_done)
                    state_next = ST_SEND_ADDR;
            end
           
            ST_SEND_ADDR: begin
                if (qspi_byte_done) begin
                    if (c_addr_byte_cnt >= 2) begin
                        if (erase_op)
                            state_next = ST_DEASSERT_CS;
                        else if (op_mode_read)
                            state_next = ST_SEND_DUMMY;
                        else
                            state_next = ST_DATA_WRITE;
                    end
                end
            end
           
            ST_SEND_DUMMY: begin
                if (qspi_byte_done)
                    state_next = ST_DATA_READ;
            end
           
            ST_DATA_READ: begin
                if (qspi_byte_done) begin
                    if (c_data_byte_cnt >= xfer_len - 1)
                        state_next = ST_DEASSERT_CS;
                end
            end
           
            ST_DATA_WRITE: begin
                if (qspi_byte_done) begin
                    if (c_data_byte_cnt >= xfer_len - 1)
                        state_next = ST_DEASSERT_CS;
                end
            end
           
            ST_DEASSERT_CS: begin
                if (timer_done_flag) begin
                    if (needs_wel)
                        state_next = ST_POLL_STATUS;
                    else
                        state_next = ST_DONE;
                end
            end
           
            ST_POLL_STATUS: begin
                if (!flash_busy_poll)
                    state_next = ST_DONE;
                else if (poll_timeout_done_flag)
                    state_next = ST_ERROR;
            end
           
            ST_DONE: begin
                if (start_pulse) begin
                    state_next = ST_IDLE;
                end
            end
           
            ST_ERROR: begin
                if (start_pulse) begin
                    state_next = ST_IDLE;
                end
            end
           
            default: begin
                state_next = ST_IDLE;
            end
        endcase
    end
     
    //FSM Output Logic
    always_comb begin
        error_out               = '0    ;
        done_out                = '0    ;
        qspi_start              = '0    ;
        CSn                     = 1'b1  ;
        timer_done_flag         = '0    ;
        poll_timeout_done_flag  = '0    ;
        flash_busy_poll         = '0    ;
        unique case (state_curr)    
            ST_ISSUE_WEL: begin
                qspi_start  = 1'b1;
                CSn         = 1'b0;
            end
           
            ST_WAIT_WEL_CS: begin
                CSn = 1'b1;
                timer_done_flag = (c_timer_counter >= NS_10_USR_CTRL_FREQ);
            end
           
            ST_SEND_CMD: begin
                CSn          = 1'b0;
                qspi_start   = 1'b1;
            end
           
            ST_SEND_ADDR: begin
                CSn = 1'b0;
            end
           
            ST_SEND_DUMMY: begin
                CSn = 1'b0;
     
            end
           
            ST_DATA_READ: begin
                CSn          = 1'b0;
            end
           
            ST_DATA_WRITE: begin
                CSn        = 1'b0;
            end
           
            ST_DEASSERT_CS: begin
                CSn = 1'b1;
                timer_done_flag = (c_timer_counter >= NS_50_USR_CTRL_FREQ);
               
            end
           
            ST_POLL_STATUS: begin
                CSn = 1'b0;
                qspi_start = 1'b1;
                poll_timeout_done_flag = (c_poll_timeout_cnt >= POLL_TIMEOUT_MAX);
                flash_busy_poll = rx_payload[0];
            end
           
            ST_DONE: begin
                done_out = 1'b1;
            end
           
            ST_ERROR: begin
                error_out = 1'b1;
            end
           
            default: begin
                ;
            end
        endcase
    end
     
    always_comb begin
        tx_payload   = 8'h00;
        unique case (state_next)  
            ST_ISSUE_WEL: begin
                tx_payload  = OPCODE_WRITE_ENABLE;
            end
            ST_SEND_CMD: begin
                tx_payload   = cmd_opcode;
            end
           
            ST_SEND_ADDR: begin
                case (n_addr_byte_cnt)
                    0: tx_payload = flash_addr[23:16];
                    1: tx_payload = flash_addr[15:8];
                    2: tx_payload = flash_addr[7:0];
                endcase
            end
            ST_DATA_WRITE: begin
                if (!wr_fifo_empty) begin
                    case (n_wr_byte_offset)
                        2'd0: tx_payload = wr_fifo_rdata[7:0];    
                        2'd1: tx_payload = wr_fifo_rdata[15:8];    
                        2'd2: tx_payload = wr_fifo_rdata[23:16];    
                        2'd3: tx_payload = wr_fifo_rdata[31:24];    
                        default: tx_payload = 8'h00;
                    endcase
                end
            end
            ST_POLL_STATUS: begin
                tx_payload = OPCODE_READ_STATUS;
            end
            default: begin
                ;
            end
        endcase
    end
     
    always_ff @(posedge clk_ctrl or negedge reset_n) begin
        if (!reset_n) begin
            c_addr_byte_cnt     <= 3'd0;
            c_data_byte_cnt     <= 16'd0;
            c_timer_counter     <= 8'd0;
            c_timer_valid       <= 1'b0;
            c_poll_timeout_cnt  <= 16'd0;
            c_wr_byte_offset    <= 2'd0;
            c_rd_byte_offset    <= 2'd0;
            c_rx_word_buffer    <= 32'd0;
            c_rd_fifo_wr_en     <= 1'b0;
        end else begin
            c_addr_byte_cnt     <= n_addr_byte_cnt;
            c_data_byte_cnt     <= n_data_byte_cnt;
            c_timer_counter     <= n_timer_counter;
            c_timer_valid       <= n_timer_valid;
            c_poll_timeout_cnt  <= n_poll_timeout_cnt;
            c_wr_byte_offset    <= n_wr_byte_offset;
            c_rd_byte_offset    <= n_rd_byte_offset;
            c_rx_word_buffer    <= n_rx_word_buffer;
            c_rd_fifo_wr_en    <= n_rd_fifo_wr_en;
        end
    end
     
    always_comb begin
        n_addr_byte_cnt = c_addr_byte_cnt;
        n_data_byte_cnt = c_data_byte_cnt;
        n_wr_byte_offset = c_wr_byte_offset;
        n_rd_byte_offset = c_rd_byte_offset;
        n_rx_word_buffer = c_rx_word_buffer;
        n_rd_fifo_wr_en = c_rd_fifo_wr_en;
        //Address Count
        if (state_next == ST_IDLE) begin
            n_addr_byte_cnt = 3'd0;
        end else if (state_curr == ST_SEND_ADDR && qspi_byte_done) begin
            if (c_addr_byte_cnt < 2) begin
                n_addr_byte_cnt = c_addr_byte_cnt + 1;
            end
        end
        //Data Count
        if (start_pulse || state_next == ST_IDLE) begin
            n_data_byte_cnt = 16'd0;
        end else if (qspi_byte_done) begin
            //READ
            if (state_curr == ST_DATA_READ && !rd_fifo_full) begin
                if (c_data_byte_cnt < xfer_len - 1) begin
                    n_data_byte_cnt = c_data_byte_cnt + 1;
                end
            end 
            //WRITE
            else if (state_curr == ST_DATA_WRITE && !wr_fifo_empty) begin
                if (c_data_byte_cnt < xfer_len - 1) begin
                    n_data_byte_cnt = c_data_byte_cnt + 1;
                end
            end
        end else begin
            n_data_byte_cnt = c_data_byte_cnt;
        end
        //Write Offset
        if (start_pulse || state_next == ST_IDLE) begin
            n_wr_byte_offset = 2'd0;
        end else if (state_curr == ST_DATA_WRITE && qspi_byte_done && !wr_fifo_empty) begin
            if (c_wr_byte_offset < 3)
                n_wr_byte_offset = c_wr_byte_offset + 1;
            else
                n_wr_byte_offset = 2'd0;
        end else begin
            n_wr_byte_offset = c_wr_byte_offset;
        end
        // RD byte offset + rx_word_buffer packing
        if (start_pulse || state_next == ST_IDLE) begin
            n_rd_byte_offset = 2'd0;
            n_rx_word_buffer = 32'd0;
        end else if (state_curr == ST_DATA_READ && qspi_byte_done && !rd_fifo_full) begin
            n_rd_byte_offset = c_rd_byte_offset;
            n_rx_word_buffer = c_rx_word_buffer;
           
            case (c_rd_byte_offset)
                2'd0: n_rx_word_buffer[31:24]   = rx_payload;
                2'd1: n_rx_word_buffer[23:16]  = rx_payload;
                2'd2: n_rx_word_buffer[15:8] = rx_payload;
                2'd3: n_rx_word_buffer[7:0] = rx_payload;
                default: ;
            endcase
       
            if (c_rd_byte_offset < 3)
                n_rd_byte_offset = c_rd_byte_offset + 1;
            else
                n_rd_byte_offset = 2'd0;
        end
        n_rd_fifo_wr_en = (state_curr == ST_DATA_READ &&
                            qspi_byte_done &&
                            c_rd_byte_offset == 2'd3 &&
                            !rd_fifo_full);
    end
     
    // TIMER counter
    always_comb begin
        n_timer_counter = c_timer_counter;
        n_timer_valid   = c_timer_valid;
        n_poll_timeout_cnt = c_poll_timeout_cnt;
        if (start_pulse || state_next == ST_IDLE || state_curr == ST_DONE || state_curr == ST_ERROR) begin
            n_timer_counter = 8'd0;
            n_timer_valid   = 1'b0;
        end else if (!c_timer_valid && state_next == ST_WAIT_WEL_CS) begin
            n_timer_counter = 8'd0;
            n_timer_valid   = 1'b1;
        end else if (!c_timer_valid && state_next == ST_DEASSERT_CS) begin
            n_timer_counter = 8'd0;
            n_timer_valid   = 1'b1;
        end else if (c_timer_valid && c_timer_counter < NS_10_USR_CTRL_FREQ && state_curr == ST_WAIT_WEL_CS) begin
            n_timer_counter = c_timer_counter + 1;
            if(c_timer_counter >= NS_10_USR_CTRL_FREQ) begin
                n_timer_valid = 1'b0;
            end
        end else if (c_timer_valid && c_timer_counter < NS_50_USR_CTRL_FREQ && state_curr == ST_DEASSERT_CS) begin
            n_timer_counter = c_timer_counter + 1;
            if(c_timer_counter >= NS_50_USR_CTRL_FREQ) begin
                n_timer_valid = 1'b0;
            end
        end
        //Polling
        if (start_pulse || state_next == ST_IDLE) begin
            n_poll_timeout_cnt = 16'd0;
        end else if (state_curr == ST_POLL_STATUS && flash_busy_poll) begin
            if (c_poll_timeout_cnt < POLL_TIMEOUT_MAX)
                n_poll_timeout_cnt = c_poll_timeout_cnt + 1;
            else
                n_poll_timeout_cnt = c_poll_timeout_cnt;
        end else begin
            n_poll_timeout_cnt = c_poll_timeout_cnt;
        end
    end
 
    assign rd_fifo_wr_en = c_rd_fifo_wr_en;
    assign rd_fifo_wdata = c_rx_word_buffer;
    assign wr_fifo_rd_en = (state_curr == ST_DATA_WRITE) && qspi_byte_done && (!wr_fifo_empty) && (c_wr_byte_offset == 2'd2);
    
endmodule : ctrl_fsm
