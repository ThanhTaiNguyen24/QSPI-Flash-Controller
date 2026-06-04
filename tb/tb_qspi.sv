`timescale 1ns/1ps
 
module tb_qspi;
 
    // ---------------------------------------------------------
    // 1. Khai báo Parameters & Tín hiệu
    // ---------------------------------------------------------
    localparam OPCODE_FAST_READ    = 8'h0B;
    localparam OPCODE_PAGE_PROGRAM = 8'h02;
    localparam OPCODE_SECTOR_ERASE = 8'h20;
    localparam OPCODE_BLOCK_ERASE  = 8'hD8;
    localparam OPCODE_WRITE_ENABLE = 8'h06;
    localparam OPCODE_READ_STATUS  = 8'h05;

    // APB & Control Interface
    logic                        pclk;          // 50MHz
    logic                        presetn;
    logic                        clk_ctrl;      // 133MHz
    logic                        clk_axi;       // 100MHz (Cho AXI Stream)
    
    logic                        psel;
    logic                        penable;
    logic                        pwrite;
    logic [11:0]                 paddr;
    logic [31:0]                 pwdata;
    logic [31:0]                 prdata;
    logic                        pready;
    logic                        pslverr;

    // AXI-Stream Interface (SLAVE - Giả lập DMA đẩy data vào IP)
    logic                        s_axis_tvalid;
    logic                        s_axis_tready;
    logic [31:0]                 s_axis_tdata;
    logic [3:0]                  s_axis_tkeep;
    logic                        s_axis_tlast;

    // AXI-Stream Interface (MASTER - Giả lập IP đẩy data về DMA)
    logic                        m_axis_tvalid;
    logic                        m_axis_tready;
    logic [31:0]                 m_axis_tdata;
    logic [3:0]                  m_axis_tkeep;
    logic                        m_axis_tlast;

    // Flash SPI Interface
    logic                        flash_sck;
    logic                        flash_csn;
    wire  [3:0]                  io;

    // ---------------------------------------------------------
    // VCD Dump
    // ---------------------------------------------------------
    initial begin
        $dumpfile("top_wave.vcd");
        $dumpvars(0, tb_qspi);
    end
 
    // ---------------------------------------------------------
    // 2. Instantiate DUT (Device Under Test)
    // ---------------------------------------------------------
    qspi_flash_top u_dut (
        // Clocks & Resets
        .clk_apb        (pclk),
        .clk_ctrl       (clk_ctrl),
        .clk_axi        (clk_axi),
        .pclk_reset_n   (presetn),
        
        // APB
        .psel           (psel),
        .penable        (penable),
        .pwrite         (pwrite),
        .paddr          (paddr),
        .pwdata         (pwdata),
        .prdata         (prdata),
        .pready         (pready),
        .pslverr        (pslverr),
       
        // AXI Stream Slave (Write to Flash)
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tkeep   (s_axis_tkeep),
        .s_axis_tlast   (s_axis_tlast),

        // AXI Stream Master (Read from Flash)
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tkeep   (m_axis_tkeep),
        .m_axis_tlast   (m_axis_tlast),
     
        // Flash SPI
        .sck            (flash_sck),
        .CSn            (flash_csn),
        .io             (io)
    );

    // ---------------------------------------------------------
    // 3. Khởi tạo Clock & Reset
    // ---------------------------------------------------------
    initial begin
        pclk = 0;
        forever #10 pclk = ~pclk;       // 50MHz cho APB
    end

    initial begin
        clk_ctrl = 0;
        forever #3.75 clk_ctrl = ~clk_ctrl; // ~133MHz cho logic Core QSPI
    end

    initial begin
        clk_axi = 0;
        forever #5 clk_axi = ~clk_axi;  // 100MHz cho miền AXI
    end
 
    // ---------------------------------------------------------
    // 4. Tasks Giao tiếp APB & AXI
    // ---------------------------------------------------------
    task apb_write(input [11:0] addr, input [31:0] wdata);
        begin
            @(posedge pclk); #1;
            psel    = 1'b1;
            pwrite  = 1'b1;
            paddr   = addr;
            pwdata  = wdata;
            penable = 1'b0;
            
            @(posedge pclk); #1;
            penable = 1'b1;
           
            wait (pready === 1'b1);
            @(posedge pclk); #1;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask
 
    task apb_read(input [11:0] addr, output logic [31:0] rdata);
        begin
            @(posedge pclk); #1;
            psel    = 1'b1;
            pwrite  = 1'b0;
            paddr   = addr;
            penable = 1'b0;
           
            @(posedge pclk); #1;
            penable = 1'b1;
           
            wait (pready === 1'b1);
            rdata = prdata;
           
            @(posedge pclk); #1;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    // Task đẩy data vào IP qua chuẩn AXI-Stream
    task axis_write_burst(input int num_words);
        begin
            @(posedge clk_axi); #1;
            s_axis_tvalid = 1'b1;
            s_axis_tkeep  = 4'hF; // Giữ lại cả 4 bytes
            for (int i = 0; i < num_words; i++) begin
                s_axis_tdata = 32'hAAAA_0000 + i; // Tạo data giả (VD: AAAA0000, AAAA0001...)
                s_axis_tlast = (i == num_words - 1) ? 1'b1 : 1'b0;
                
                // Chờ IP sẵn sàng nhận
                wait(s_axis_tready === 1'b1);
                @(posedge clk_axi); #1;
            end
            // Kết thúc burst
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    // Theo dõi luồng AXI-Stream IP phát ra (để in log)
    initial begin
        m_axis_tready = 1'b1; // Luôn sẵn sàng nhận data từ IP
        forever begin
            @(posedge clk_axi);
            if (m_axis_tvalid && m_axis_tready) begin
                $display("[%0t] [AXI-STREAM M] Received Data: 0x%h | TLAST: %b", $time, m_axis_tdata, m_axis_tlast);
            end
        end
    end

    // ---------------------------------------------------------
    // 5. Mô phỏng dữ liệu MISO từ bộ nhớ Flash
    // ---------------------------------------------------------
    logic        flash_drive_miso;
    logic        flash_miso_bit;
    
    // Khai báo mảng chứa 16 words (64 Bytes) dữ liệu giả lập của Flash
    logic [31:0] flash_mem [0:15];
    integer      read_bit_idx  = 31;
    integer      read_word_idx = 0;

    // Thanh ghi trạng thái (Status Register) mô phỏng của Flash
    // Bit 0 = WIP (Write In Progress). 0: Sẵn sàng, 1: Đang bận
    logic [7:0]  mock_status_reg = 8'h00; 

    initial begin
        // Khởi tạo data sinh động
        flash_mem[0] = 32'h11223344; flash_mem[1] = 32'h55667788;
        flash_mem[2] = 32'h99AABBCC; flash_mem[3] = 32'hDDEEFF00;
        flash_mem[4] = 32'h12345678; flash_mem[5] = 32'h87654321;
        flash_mem[6] = 32'hFACECAFE; flash_mem[7] = 32'hDEADBEEF;
        for (int i = 8; i < 16; i++) flash_mem[i] = 32'hB00B0000 + i;
    end

    assign io[1] = flash_drive_miso ? flash_miso_bit : 1'bz;
 
    always @(negedge flash_sck) begin
        // Giả lập Flash trả data về theo MISO (io[1]) vào các chu kỳ thích hợp
        if ( (u_dut.u_qspi_phy.current_state == 3 /*SHIFT_DUMMY*/ && u_dut.u_qspi_phy.bit_cnt == 7) ||
             (u_dut.u_qspi_phy.current_state == 1 /*SHIFT_CMD*/   && u_dut.u_qspi_phy.bit_cnt == 7 && u_dut.u_qspi_phy.op_reg == OPCODE_READ_STATUS) ||
             (u_dut.u_qspi_phy.current_state == 4 /*SHIFT_DATA*/  && (u_dut.u_qspi_phy.op_reg == OPCODE_FAST_READ || u_dut.u_qspi_phy.op_reg == OPCODE_READ_STATUS)) ) begin
           
            flash_drive_miso <= 1;
            
            // =========================================================
            // Trả lời lệnh ĐỌC TRẠNG THÁI (READ STATUS - 8 bit)
            // =========================================================
            if (u_dut.u_qspi_phy.op_reg == OPCODE_READ_STATUS) begin
                // read_bit_idx[2:0] sẽ giúp quét từ 7 xuống 0 (truyền MSB trước)
                flash_miso_bit <= mock_status_reg[read_bit_idx[2:0]];
                
                if (read_bit_idx > 0) begin
                    read_bit_idx <= read_bit_idx - 1;
                end else begin
                    read_bit_idx <= 31; // Đọc xong 1 byte, reset lại counter
                end
            end 
            // =========================================================
            // Trả lời lệnh ĐỌC DỮ LIỆU (FAST READ - 32 bit)
            // =========================================================
            else begin
                flash_miso_bit <= flash_mem[read_word_idx][read_bit_idx];
                
                if (read_bit_idx > 0) begin
                    read_bit_idx <= read_bit_idx - 1;
                end else begin
                    // Đọc xong 1 Word (32 bits), nhảy sang Word tiếp theo
                    read_bit_idx <= 31;
                    if (read_word_idx < 15) read_word_idx <= read_word_idx + 1;
                end
            end
            
        end
        else begin
            flash_drive_miso <= 0;
            read_bit_idx     <= 31;
            read_word_idx    <= 0; // Reset con trỏ khi CSn kéo lên cao
        end
    end

    // ---------------------------------------------------------
    // 6. Test Scenario Mạch chính
    // ---------------------------------------------------------
    logic [31:0] rdata;

    initial begin
        // Khởi tạo các tín hiệu AXI Slave
        s_axis_tvalid = 0; s_axis_tdata = 0; s_axis_tkeep = 0; s_axis_tlast = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        
        // Reset hệ thống
        presetn = 0;
        #100 presetn = 1;
        
        $display("\n[%0t] ========================================", $time);
        $display("[%0t] BẮT ĐẦU TEST MODULE QSPI VỚI AXI-STREAM", $time);
        $display("[%0t] ========================================\n", $time);

        // ---------------------------------------------------------
        // TEST 1: FLASH READ (IP kéo data từ Flash đẩy ra AXI-M)
        // ---------------------------------------------------------
        $display("[%0t] --- TEST 1: FLASH READ Operation ---", $time);
        apb_write(12'h008, 32'h0010_0000); // FLASH_ADDR = 0x00100000
        apb_write(12'h00C, 32'd32);        // XFER_LEN = 32 bytes (tương đương 8 words)
        apb_write(12'h000, 32'h0000_0010); // Cấu hình READ mode
        apb_write(12'h000, 32'h0000_0011); // Bật cờ START
        
        // Chờ IP đọc xong (Có thể check tín hiệu done hoặc chờ thời gian cứng)
        wait(u_dut.status_done_cdc == 1'b1);
        $display("[%0t] TEST 1 Hoàn thành! Check log AXI-STREAM phía trên.\n", $time);
        
        #1000;

        // ---------------------------------------------------------
        // TEST 2: FLASH WRITE (AXI-S đẩy data vào IP để ghi xuống Flash)
        // ---------------------------------------------------------
        $display("[%0t] --- TEST 2: FLASH WRITE Operation ---", $time);
        
        // Bước 2.1: Zynq đẩy 8 words qua AXI-Stream vào FIFO của IP trước
        $display("[%0t] Gửi 8 words qua s_axis...", $time);
        axis_write_burst(8); 

        // Bước 2.2: Cấu hình APB để ra lệnh Write
        apb_write(12'h008, 32'h0020_0000); // FLASH_ADDR = 0x00200000
        apb_write(12'h00C, 32'd32);        // XFER_LEN = 32 bytes (8 words)
        apb_write(12'h000, 32'h0000_0002); // Cấu hình WRITE mode
        apb_write(12'h000, 32'h0000_0003); // Bật cờ START
        
        wait(u_dut.status_done_cdc == 1'b1);
        $display("[%0t] TEST 2 Hoàn thành! Quan sát waveform chân MOSI (io[0]).\n", $time);

        // -----------------------------------------------
        $display("[%0t] ========================================", $time);
        $display("[%0t] TẤT CẢ TEST ĐÃ HOÀN TẤT!", $time);
        $display("[%0t] ========================================", $time);
       
        #1000;
        $finish;
    end
 
endmodule