module heart_rate_rms(
    input  wire       CLK,
    input  wire       reset,
    input  wire       Din,
    output wire       pulse_Detector,
    output wire [7:0] BPM_out,
    output wire       is_Bradycardia,
    output wire       is_Tachycardia,
    output wire       is_afib_alert,
    output wire [7:0] irregular_count
);
    reg  [7:0] timer_count;
    wire       pulse_edge;

    // Timer logic
    always @(posedge CLK or posedge reset) begin
        if (reset) begin
            timer_count <= 8'b0;
        end else if (pulse_edge) begin
            timer_count <= 8'b0;
        end else if (timer_count < 8'd255) begin
            timer_count <= timer_count + 8'b1;
        end
    end // <--- เพิ่ม end ที่ขาดไป

    assign pulse_Detector = pulse_edge;

    // Sub-module 1: Edge Detector
    heart_convert_pulse insl (
        .CLK(CLK),
        .reset(reset),
        .Din(Din),
        .pulse_edge(pulse_edge)
    );

    // Sub-module 2: BPM Calculator
    heart_BPM u_bpm_calc (
        .CLK(CLK),
        .reset(reset),
        .pulse_edge(pulse_edge),
        .timer_count(timer_count),
        .BPM_out(BPM_out),
        .is_Bradycardia(is_Bradycardia),
        .is_Tachycardia(is_Tachycardia)
    );

    // Sub-module 3: Rhythm / AFib Alert
    heart_alert u_rhythm_check (
        .CLK(CLK),
        .reset(reset),
        .pulse_edge(pulse_edge),
        .timer_count(timer_count),
        .irregular_count(irregular_count),
        .is_afib_alert(is_afib_alert)
    );

endmodule
// Module 1: Edge Detector
module heart_convert_pulse(
    input  wire CLK,
    input  wire reset,
    input  wire Din,
    output wire pulse_edge 
);
    reg Din_delay;

    always @(posedge CLK or posedge reset) begin
        if (reset)
            Din_delay <= 1'b0;
        else
            Din_delay <= Din;
    end

    assign pulse_edge = Din & (~Din_delay);

endmodule
// Module 2: BPM Logic
module heart_BPM(
    input  wire       CLK,
    input  wire       reset,
    input  wire       pulse_edge,
    input  wire [7:0] timer_count,
    output reg  [7:0] BPM_out,
    output reg        is_Bradycardia,
    output reg        is_Tachycardia
);
    wire [7:0] solved_BPM = (timer_count > 8'd0) ? (8'd240 / timer_count) : 8'd0;

    always @(posedge CLK or posedge reset) begin
        if (reset) begin
            BPM_out        <= 8'd0;
            is_Bradycardia <= 1'b0;
            is_Tachycardia <= 1'b0;
        end else if (pulse_edge) begin
            BPM_out <= solved_BPM;
            if (solved_BPM < 8'd60) begin
                is_Bradycardia <= 1'b1;
                is_Tachycardia <= 1'b0;
            end else if (solved_BPM > 8'd100) begin
                is_Bradycardia <= 1'b0;
                is_Tachycardia <= 1'b1;
            end else begin
                is_Bradycardia <= 1'b0;
                is_Tachycardia <= 1'b0;
            end
        end
    end

endmodule
// Module 3: Rhythm Alert Logic
module heart_alert(
    input  wire       CLK,
    input  wire       reset,
    input  wire       pulse_edge,
    input  wire [7:0] timer_count,
    output reg  [7:0] irregular_count,
    output reg        is_afib_alert // แก้จาก [7:0] เหลือ 1 บิต
);
    reg [7:0] prev_interval;

    wire [7:0] diff      = (timer_count > prev_interval) ? (timer_count - prev_interval) : (prev_interval - timer_count);
    wire [7:0] tolerance = (prev_interval >> 3); // 12.5%

    always @(posedge CLK or posedge reset) begin
        if (reset) begin
            prev_interval   <= 8'd0;
            irregular_count <= 8'd0;
            is_afib_alert   <= 1'b0;
        end else if (pulse_edge) begin
            if (prev_interval > 8'd0) begin
                if (diff > tolerance) begin
                    if (irregular_count < 8'd255)
                        irregular_count <= irregular_count + 8'd1;

                    if (irregular_count >= 8'd2)
                        is_afib_alert <= 1'b1;
                end else begin
                    irregular_count <= 8'd0;
                    is_afib_alert   <= 1'b0;
                end
            end
            prev_interval <= timer_count;
        end
    end
endmodule