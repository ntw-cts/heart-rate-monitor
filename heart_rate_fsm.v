`timescale 1ns / 1ps

module heart_rate_fsm (
    input  wire       clk,
    input  wire       reset,
    input  wire       din,
    output reg        pulse_detected,
    output reg  [7:0] bpm_out,
    output reg        is_bradycardia, // 1 = เต้นช้า (< 60 BPM)
    output reg        is_tachycardia, // 1 = เต้นเร็ว (> 100 BPM)
    output reg        is_afib_alert,  // 1 = แจ้งเตือน aFib (ผิดปกติ >= 3 ครั้ง)
    output reg  [7:0] irregular_count // ตัวนับความผิดปกติขนาด 8-bit
);

    // --- รีจิสเตอร์ขนาด 8-bit ทั้งหมด ---
    reg [7:0] timer_cnt;
    reg [7:0] interval;
    reg [7:0] prev_interval;
    reg [7:0] diff;
    reg [7:0] tolerance;
    reg       din_dly; // สำหรับ Edge Detection

    // ตรวจจับขอบขาขึ้น (Rising Edge) ของสัญญาณ pulse input
    wire pulse_edge = din & (~din_dly);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            din_dly         <= 1'b0;
            pulse_detected  <= 1'b0;
            timer_cnt       <= 8'd0;
            interval        <= 8'd0;
            prev_interval   <= 8'd0;
            diff            <= 8'd0;
            tolerance       <= 8'd0;
            bpm_out         <= 8'd0;
            irregular_count <= 8'd0;
            is_bradycardia  <= 1'b0;
            is_tachycardia  <= 1'b0;
            is_afib_alert   <= 1'b0;
        end else begin
            din_dly        <= din;
            pulse_detected <= pulse_edge;

            if (pulse_edge) begin
                // 1. บันทึกคาบเวลาของจังหวะนี้ แล้วรีเซ็ตตัวนับ
                interval  <= timer_cnt;
                timer_cnt <= 8'd0;

                // 2. คำนวณ BPM ขนาด 8-bit (สมมติสเกลตามตัวนับ: 8'd240 / interval)
                if (timer_cnt > 8'd0) begin
                    bpm_out <= 8'd240 / timer_cnt; 
                end

                // 3. ตรวจสอบ Bradycardia / Tachycardia
                if ((8'd240 / timer_cnt) < 8'd60) begin
                    is_bradycardia <= 1'b1;
                    is_tachycardia <= 1'b0;
                end else if ((8'd240 / timer_cnt) > 8'd100) begin
                    is_bradycardia <= 1'b0;
                    is_tachycardia <= 1'b1;
                end else begin
                    is_bradycardia <= 1'b0;
                    is_tachycardia <= 1'b0;
                end

                // 4. ตรวจสอบความสม่ำเสมอของจังหวะ (Rhythm & aFib Detection)
                if (prev_interval > 8'd0) begin
                    // หาผลต่าง (Absolute Difference)
                    if (timer_cnt > prev_interval)
                        diff = timer_cnt - prev_interval;
                    else
                        diff = prev_interval - timer_cnt;

                    // ค่า Tolerance ประมาณ 12.5% (เลื่อนบิตขวา 3 บิต: prev_interval >> 3)
                    tolerance = (prev_interval >> 3);

                    if (diff > tolerance) begin
                        // ผิดจังหวะ -> เพิ่มตัวนับ
                        if (irregular_count < 8'd255)
                            irregular_count <= irregular_count + 8'd1;
                        
                        // ถ้าผิดปกติสะสมครบ 3 ครั้งขึ้นไป
                        if (irregular_count >= 8'd2) // รอบนี้จะเป็นครั้งที่ 3
                            is_afib_alert <= 1'b1;
                    end else begin
                        // จังหวะปกติ -> รีเซ็ตตัวนับ aFib
                        irregular_count <= 8'd0;
                        is_afib_alert   <= 1'b0;
                    end
                end

                prev_interval <= timer_cnt;

            end else begin
                // ถ้าระหว่างรอบยังไม่เจอ pulse ให้เพิ่มค่านับเวลาขึ้นเรื่อยๆ (กัน overflow ที่ 255)
                if (timer_cnt < 8'd255)
                    timer_cnt <= timer_cnt + 8'd1;
            end
        end
    end

endmodule


module tb_heart_rate_fsm;
    reg clk;
    reg reset;
    reg din;
    wire       pulse_detected;
    wire [7:0] bpm_out;
    wire       is_bradycardia;
    wire       is_tachycardia;
    wire       is_afib_alert;
    wire [7:0] irregular_count;
    // ต่อวงจร 8-bit DUT
    heart_rate_fsm uut (
        .clk(clk),
        .reset(reset),
        .din(din),
        .pulse_detected(pulse_detected),
        .bpm_out(bpm_out),
        .is_bradycardia(is_bradycardia),
        .is_tachycardia(is_tachycardia),
        .is_afib_alert(is_afib_alert),
        .irregular_count(irregular_count)
    );
    // สร้าง Clock 10 ns
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    // มอนิเตอร์ผลลัพธ์ผ่านทางหน้าจอ Terminal
    always @(posedge pulse_detected) begin
        #1; // รอให้ output เซ็ตตัว
        $display("[Time: %0d ns] Pulse! -> BPM = %0d | Irregular Beats = %0d | aFib Alert = %b", 
                  $time, bpm_out, irregular_count, is_afib_alert);
    end
    initial begin
        reset = 1; din = 0;
        #20 reset = 0;
        $display("\n=== 1. จังหวะปกติ (Normal Rhythm) ===");
        din = 1; #10; din = 0; #30; // ส่ง pulse ห่างกัน 3 clock ticks (BPM = 240/3 = 80)
        din = 1; #10; din = 0; #30;
        din = 1; #10; din = 0; #30;
        $display("\n=== 2. สภาวะผิดจังหวะ aFib (Irregular Intervals) ===");
        din = 1; #10; din = 0; #50; // ผิดปกติ ครั้งที่ 1
        din = 1; #10; din = 0; #20; // ผิดปกติ ครั้งที่ 2
        din = 1; #10; din = 0; #60; // ผิดปกติ ครั้งที่ 3 -> aFib Alert จะกลายเป็น 1 !
        din = 1; #10; din = 0; #20; // ผิดปกติ ครั้งที่ 4
        $display("\n=== 3. กลับสู่จังหวะปกติ (Recovery) ===");
        din = 1; #10; din = 0; #30;
        din = 1; #10; din = 0; #30; // รีเซ็ต aFib Alert กลับเป็น 0
        #100;
        $display("\n=== End of Test ===");
        $stop;
    end
endmodule