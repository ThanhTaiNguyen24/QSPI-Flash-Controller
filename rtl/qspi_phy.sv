`timescale 1ns/1ps
 
// The globally visible State Enum
typedef enum logic [2:0] {
    IDLE,
    SHIFT_CMD,
    SHIFT_ADD,
    SHIFT_DUMMY,
    SHIFT_DATA,
    DONE
} qspi_state_t;
 
module qspi_phy #(
    parameter DATA_WIDTH = 8,
    parameter TRANSFER_WIDTH = 16,
    // OPCODES
    parameter OPCODE_FAST_READ    = 8'h0B,
    parameter OPCODE_PAGE_PROGRAM = 8'h02,
    parameter OPCODE_SECTOR_ERASE = 8'h20,
    parameter OPCODE_BLOCK_ERASE  = 8'hD8,
    parameter OPCODE_WRITE_ENABLE = 8'h06,
    parameter OPCODE_READ_STATUS  = 8'h05
) (
    input  logic clk_ctrl,
    input  logic reset_n,
   
    output wire  sck,
    output logic CSn,
    inout  wire  [3:0] io,
   
    input  logic qspi_start,
    input  logic [DATA_WIDTH - 1 : 0] tx_payload,
    input  logic CSn_in,
    input  logic [TRANSFER_WIDTH - 1 : 0] xfer_len,
   
    output logic [DATA_WIDTH - 1 : 0] rx_payload,
    output logic qspi_byte_done
);
 
    // --- Internal Signals ---
    qspi_state_t current_state, next_state;
   
    logic [DATA_WIDTH - 1 : 0] op_reg;
    logic [2:0]  bit_cnt;  
    logic [15:0] byte_cnt;
    logic bit_cnt_done;    
    logic [DATA_WIDTH - 1 : 0] n_op_reg;
    logic [2:0]  n_bit_cnt;  
    logic [15:0] n_byte_cnt;
 
    logic mosi_pos, mosi_neg;
    logic [DATA_WIDTH - 1 : 0] tx_shift_pos;
    logic [DATA_WIDTH - 1 : 0] tx_shift_neg;
    logic n_mosi_pos, n_mosi_neg;
    logic [DATA_WIDTH - 1 : 0] n_tx_shift_pos;
    logic [DATA_WIDTH - 1 : 0] n_tx_shift_neg;
    logic io0_out;
 
    logic [DATA_WIDTH - 1 : 0] rx_shift_reg;
    logic [DATA_WIDTH - 1 : 0] n_rx_shift_reg;
    logic [DATA_WIDTH - 1 : 0] n_rx_payload;
    // Continuous Assignments
    assign sck = clk_ctrl;
    assign CSn = CSn_in;
    assign bit_cnt_done = (bit_cnt == 3'd7);
    assign qspi_byte_done = (bit_cnt == 3'd7);
 
    // =========================================================
    // FSM State & Counters (Posedge)
    // =========================================================
    always_comb begin
        next_state = current_state;
       
        case (current_state)
            IDLE: begin
                if (qspi_start) next_state = SHIFT_CMD;
            end
            SHIFT_CMD: begin
                if (bit_cnt_done) begin
                    if (op_reg == OPCODE_WRITE_ENABLE)
                        next_state = DONE;
                    else if (op_reg == OPCODE_READ_STATUS)
                        next_state = SHIFT_DATA;
                    else
                        next_state = SHIFT_ADD;
                end
            end
            SHIFT_ADD: begin
                // Exit after 3 bytes (Standard 24-bit address)
                if (bit_cnt_done && byte_cnt == 16'd2) begin
                    if (op_reg == OPCODE_FAST_READ)
                        next_state = SHIFT_DUMMY;
                    else if (op_reg == OPCODE_PAGE_PROGRAM)
                        next_state = SHIFT_DATA;
                    else
                        next_state = DONE;
                end
            end
            SHIFT_DUMMY: begin
                if (bit_cnt_done) next_state = SHIFT_DATA;
            end
            SHIFT_DATA: begin
                // Exit after xfer_len bytes
                if (bit_cnt_done && byte_cnt == (xfer_len - 1)) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
 
    // FSM State Register & qspi_done Lookahead
    always_ff @(posedge clk_ctrl or negedge reset_n) begin
        if (!reset_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
 
    // Unified Counters & Opcode Capture
    always_ff @(posedge clk_ctrl or negedge reset_n) begin
        if (!reset_n) begin
            bit_cnt     <= '0           ;
            byte_cnt    <= '0           ;
            op_reg      <= '0           ;
        end else begin
            bit_cnt     <=  n_bit_cnt   ;
            byte_cnt    <=  n_byte_cnt  ;
            op_reg      <=  n_op_reg    ;
        end
    end
 
    always_comb begin
        n_bit_cnt = bit_cnt;
        n_byte_cnt = byte_cnt;
        n_op_reg = op_reg;
        if (current_state == IDLE) begin
            n_bit_cnt = '0;
            n_byte_cnt = '0;
            n_op_reg = '0;
            if (qspi_start) n_op_reg = tx_payload;
        end
        else if (current_state != DONE) begin
            n_bit_cnt = bit_cnt + 1'b1;
            if (bit_cnt_done) begin
                if (current_state != next_state) n_byte_cnt = '0;
                else n_byte_cnt = byte_cnt + 1'b1;
            end
        end
    end
    // =========================================================
    // THE RIGHT HAND: Mixed-Edge Transmit Datapath (MOSI)
    // =========================================================
 
 
    // ODDR Clock Multiplexer
    assign io0_out = clk_ctrl ? mosi_pos : mosi_neg;
   
    // Drive io[0] only during active TX phases
    assign io[0] = (current_state == SHIFT_CMD || current_state == SHIFT_ADD ||
                   (current_state == SHIFT_DATA && op_reg == OPCODE_PAGE_PROGRAM)) ? io0_out : 1'bz;
 
    // --- POSEDGE DRIVER (Drives Command Phase) ---
    always_ff @(posedge clk_ctrl or negedge reset_n) begin
        if (!reset_n) begin
            tx_shift_pos <= '0;
            mosi_pos <= 1'b0;
        end else begin
            tx_shift_pos <= n_tx_shift_pos;
            mosi_pos <= n_mosi_pos;
        end
    end
   
    always_comb begin
        n_mosi_pos = mosi_neg;
        n_tx_shift_pos = tx_shift_pos;
        if (current_state == IDLE && qspi_start) begin
            n_tx_shift_pos = {tx_payload[DATA_WIDTH - 2 : 0], 1'b0};
            n_mosi_pos = tx_payload[DATA_WIDTH - 1];
        end
        else if (current_state == SHIFT_CMD) begin
            n_mosi_pos = tx_shift_pos[DATA_WIDTH - 1];
            n_tx_shift_pos = {tx_shift_pos[DATA_WIDTH - 2 : 0], 1'b0};
        end
        else begin
            n_mosi_pos = mosi_neg;
        end
    end
    // --- NEGEDGE DRIVER (Drives Address/Data Phases) ---
    always_ff @(negedge clk_ctrl or negedge reset_n) begin
        if (!reset_n) begin
            tx_shift_neg <= '0;
            mosi_neg <= 1'b0;
        end else begin
            tx_shift_neg <= n_tx_shift_neg;
            mosi_neg <= n_mosi_neg;
        end
    end
   
    always_comb begin
        n_mosi_neg = mosi_pos;
        n_tx_shift_neg = tx_shift_neg;
        if (current_state == SHIFT_CMD) begin
            if (bit_cnt == 7) begin
                n_mosi_neg = tx_payload[DATA_WIDTH - 1];
                n_tx_shift_neg = {tx_payload[DATA_WIDTH - 2 : 0], 1'b0};
            end
        end
        else if (current_state == SHIFT_ADD || current_state == SHIFT_DATA) begin
            if (bit_cnt == 7) begin
                n_mosi_neg = tx_payload[DATA_WIDTH - 1];
                n_tx_shift_neg = {tx_payload[DATA_WIDTH - 2 : 0], 1'b0};
            end else begin
                n_mosi_neg = tx_shift_neg[DATA_WIDTH - 1];
                n_tx_shift_neg = {tx_shift_neg[DATA_WIDTH - 2 : 0], 1'b0};
            end
        end
    end
    // =========================================================
    // THE LEFT HAND: Receive Datapath (MISO - Posedge)
    // =========================================================
 
    always_ff @(posedge clk_ctrl or negedge reset_n) begin
        if (!reset_n) begin
            rx_shift_reg <= '0;
            rx_payload <= '0;
        end else begin
            rx_shift_reg <= n_rx_shift_reg;
            rx_payload <= n_rx_payload;
        end
    end
   
    always_comb begin
        n_rx_shift_reg = rx_shift_reg;
        n_rx_payload = rx_payload;
        if (next_state == SHIFT_DATA &&
            (op_reg == OPCODE_FAST_READ || op_reg == OPCODE_READ_STATUS)) begin
           
            n_rx_shift_reg = {rx_shift_reg[DATA_WIDTH - 2 : 0], io[1]};
           
            if (bit_cnt == 3'd6) begin
                n_rx_payload = {rx_shift_reg[DATA_WIDTH - 2 : 0], io[1]};
            end
        end
    end
endmodule