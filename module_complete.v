// Top Module: Heart Rate Monitoring System
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

    // Timer logic: measures interval between consecutive beats for rhythm/AFib detection
    always @(posedge CLK or posedge reset) begin
        if (reset) begin
            timer_count <= 8'b0;
        end else if (pulse_edge) begin
            timer_count <= 8'b0;
        end else if (timer_count < 8'd255) begin
            timer_count <= timer_count + 8'b1;
        end
    end

    assign pulse_Detector = pulse_edge;

    // Sub-module 1: Mealy FSM Noise Filter (State Table Step 3)
    heart_convert_pulse insl (
        .CLK(CLK),
        .reset(reset),
        .Din(Din),
        .pulse_edge(pulse_edge)
    );

    // Sub-module 2: BPM Calculator (10-second observation window multiplied by 6)
    heart_BPM u_bpm_calc (
        .CLK(CLK),
        .reset(reset),
        .pulse_edge(pulse_edge),
        .BPM_out(BPM_out),
        .is_Bradycardia(is_Bradycardia),
        .is_Tachycardia(is_Tachycardia)
    );

    // Sub-module 3: Rhythm / AFib Alert Logic
    heart_alert u_rhythm_check (
        .CLK(CLK),
        .reset(reset),
        .pulse_edge(pulse_edge),
        .timer_count(timer_count),
        .irregular_count(irregular_count),
        .is_afib_alert(is_afib_alert)
    );

endmodule


// Module 1: Mealy-based FSM Noise Filter (Step 2 & Step 3 in Proposal)
// Requires Din=1 for 3 consecutive clock cycles to detect a valid beat
module heart_convert_pulse(
    input  wire CLK,
    input  wire reset,
    input  wire Din,
    output wire pulse_edge 
);
    // State definitions (Q1Q0)
    localparam IDLE     = 2'b00;
    localparam COUNT1   = 2'b01;
    localparam COUNT2   = 2'b10;
    localparam WAIT_LOW = 2'b11;

    reg [1:0] state, next_state;

    // State Register (2 D Flip-Flops)
    always @(posedge CLK or posedge reset) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next State Combinational Logic
    always @(*) begin
        case (state)
            IDLE: begin
                if (Din)
                    next_state = COUNT1;
                else
                    next_state = IDLE;
            end
            COUNT1: begin
                if (Din)
                    next_state = COUNT2;
                else
                    next_state = IDLE;
            end
            COUNT2: begin
                if (Din)
                    next_state = WAIT_LOW;
                else
                    next_state = IDLE;
            end
            WAIT_LOW: begin
                if (Din)
                    next_state = WAIT_LOW;
                else
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Mealy Output Logic: Y = 1 only in COUNT2 when Din = 1
    assign pulse_edge = (state == COUNT2) & Din;

endmodule


// Module 2: BPM Calculator Logic (10-second window observation)
module heart_BPM #(
    parameter WINDOW_LIMIT = 8'd10 // 10-second observation window (configurable)
)(
    input  wire       CLK,
    input  wire       reset,
    input  wire       pulse_edge,
    output reg  [7:0] BPM_out,
    output reg        is_Bradycardia,
    output reg        is_Tachycardia
);
    reg  [7:0] window_timer;
    reg  [7:0] beat_count;
    wire [7:0] current_total_beats = beat_count + (pulse_edge ? 8'd1 : 8'd0);
    wire [7:0] calc_bpm            = current_total_beats * 8'd6;

    always @(posedge CLK or posedge reset) begin
        if (reset) begin
            window_timer   <= 8'd0;
            beat_count     <= 8'd0;
            BPM_out        <= 8'd0;
            is_Bradycardia <= 1'b0;
            is_Tachycardia <= 1'b0;
        end else begin
            if (window_timer >= WINDOW_LIMIT - 8'd1) begin
                window_timer   <= 8'd0;
                BPM_out        <= calc_bpm;
                is_Bradycardia <= (calc_bpm < 8'd60);
                is_Tachycardia <= (calc_bpm > 8'd100);
                beat_count     <= 8'd0;
            end else begin
                window_timer <= window_timer + 8'd1;
                if (pulse_edge) begin
                    beat_count <= beat_count + 8'd1;
                end
            end
        end
    end

endmodule


// Module 3: Rhythm Alert Logic (Arrhythmia / AFib Detection)
module heart_alert(
    input  wire       CLK,
    input  wire       reset,
    input  wire       pulse_edge,
    input  wire [7:0] timer_count,
    output reg  [7:0] irregular_count,
    output reg        is_afib_alert
);
    reg [7:0] prev_interval;

    wire [7:0] diff      = (timer_count > prev_interval) ? (timer_count - prev_interval) : (prev_interval - timer_count);
    wire [7:0] tolerance = (prev_interval >> 3); // 12.5% tolerance threshold

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