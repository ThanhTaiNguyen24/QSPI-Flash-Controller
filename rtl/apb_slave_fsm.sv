`timescale 1ns/1ps

module apb_slave_fsm(
 
    input  logic  pclk,      
    input  logic  presetn,    
   
    input  logic  pready,
    input  logic  psel,      
    input  logic  penable,  
    // State Outputs
    output logic s_idle,    
    output logic s_setup,    
    output logic s_access    
);
    typedef enum logic [2:0] {
        STATE_IDLE   = 3'd0,
        STATE_SETUP  = 3'd1,
        STATE_ACCESS = 3'd2
    } fsm_state_t;
 
    // State Registers
    fsm_state_t state_curr;
    fsm_state_t state_next;
 
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            state_curr <= STATE_IDLE;
        else
            state_curr <= state_next;
    end
 
    always_comb begin
        state_next = state_curr;
 
        unique case (state_curr)
            STATE_IDLE: begin
                if (psel && !penable)
                    state_next = STATE_SETUP;
            end
 
            STATE_SETUP: begin
                if (psel && penable)
                    state_next = STATE_ACCESS;
            end
 
            STATE_ACCESS: begin
                if(pready) begin
                    state_next = STATE_IDLE;
                end
            end
 
            default:
                state_next = STATE_IDLE;
        endcase
    end
 
    always_comb begin
        s_idle   = 1'b0;
        s_setup  = 1'b0;
        s_access = 1'b0;
 
        unique case (state_curr)
            STATE_IDLE:    s_idle   = 1'b1;
            STATE_SETUP:   s_setup  = 1'b1;
            STATE_ACCESS:  s_access = 1'b1;
            default:       s_idle   = 1'b1;
        endcase
    end
 
endmodule : apb_slave_fsm