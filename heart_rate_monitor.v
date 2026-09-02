`timescale 1ns / 1ps

// ============================================================================
// File: heart_rate_monitor.v
// Description: Complete Heart Rate Monitoring System with Mealy FSM Noise Filter,
//              10-second Window BPM Calculation, Arrhythmia/AFib Alert,
//              and ModelSim Testbench.
// ============================================================================

// ============================================================================
// TOP MODULE: heart_rate_rms
// ============================================================================
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


// ============================================================================
// SUB-MODULE 1: heart_convert_pulse (Mealy-based FSM Noise Filter)
// ============================================================================
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


// ============================================================================
// SUB-MODULE 2: heart_BPM (BPM Calculator Logic)
// ============================================================================
module heart_BPM #(
    parameter WINDOW_LIMIT = 8'd10 // 10-second observation window
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


// ============================================================================
// SUB-MODULE 3: heart_alert (Arrhythmia / AFib Detection)
// ============================================================================
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


// ============================================================================
// TESTBENCH: tb_heart_rate (Tailored for ModelSim)
// ============================================================================
module tb_heart_rate;

    // Inputs (reg)
    reg CLK;
    reg reset;
    reg Din;

    // Outputs (wire)
    wire       pulse_Detector;
    wire [7:0] BPM_out;
    wire       is_Bradycardia;
    wire       is_Tachycardia;
    wire       is_afib_alert;
    wire [7:0] irregular_count;

    // Instantiate Unit Under Test (UUT)
    heart_rate_rms uut (
        .CLK(CLK),
        .reset(reset),
        .Din(Din),
        .pulse_Detector(pulse_Detector),
        .BPM_out(BPM_out),
        .is_Bradycardia(is_Bradycardia),
        .is_Tachycardia(is_Tachycardia),
        .is_afib_alert(is_afib_alert),
        .irregular_count(irregular_count)
    );

    // Clock Generation: 10ns period (100MHz)
    always begin
        #5 CLK = ~CLK;
    end

    // Stimulus Process
    initial begin
        // ----------------------------------------------------
        // Step 0: Initialize and Reset
        // ----------------------------------------------------
        CLK   = 0;
        reset = 1;
        Din   = 0;
        #20;
        reset = 0;
        #10;
        $display("[Time %0t ns] Reset released. Starting simulation...", $time);

        // ----------------------------------------------------
        // Test 1: Noise Glitch (1 clock cycle) -> Should be filtered
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 1: 1-cycle noise glitch", $time);
        Din = 1;
        #10;
        Din = 0;
        #30;

        // ----------------------------------------------------
        // Test 2: Noise Glitch (2 clock cycles) -> Should be filtered
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 2: 2-cycle noise glitch", $time);
        Din = 1;
        #20;
        Din = 0;
        #30;

        // ----------------------------------------------------
        // Test 3: Valid Pulse (3 clock cycles) -> Should detect 1 beat
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 3: Valid 3-cycle pulse (Beat 1)", $time);
        Din = 1;
        #30;
        Din = 0;
        #40;

        // ----------------------------------------------------
        // Test 4: Wide Pulse (6 clock cycles) -> Debounce check
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 4: Wide pulse (Beat 2)", $time);
        Din = 1;
        #60;
        Din = 0;
        #40;

        // ----------------------------------------------------
        // Test 5: Simulating multiple beats and irregular intervals
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 5: Beat train and AFib check", $time);

        // Beat 3
        Din = 1; #30; Din = 0; #40;

        // Beat 4
        Din = 1; #30; Din = 0; #40;

        // Beat 5 (Long interval)
        #80;
        Din = 1; #30; Din = 0; #40;

        // Beat 6 (Irregular interval)
        #120;
        Din = 1; #30; Din = 0; #40;

        // Beat 7 (Short interval)
        #30;
        Din = 1; #30; Din = 0; #40;

        #200;

        $display("--------------------------------------------------");
        $display("Simulation Finished Successfully");
        $display("BPM_out         = %d", BPM_out);
        $display("is_Bradycardia  = %b", is_Bradycardia);
        $display("is_Tachycardia  = %b", is_Tachycardia);
        $display("irregular_count = %d", irregular_count);
        $display("is_afib_alert   = %b", is_afib_alert);
        $display("--------------------------------------------------");

        // Use $stop for ModelSim to keep waveform window open
        $stop;
    end

endmodule
