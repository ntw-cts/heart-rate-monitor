`timescale 1ns / 1ps

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
        // Test 1: Noise Glitch (1 clock cycle: 10ns) -> Filtered
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 1: 1-cycle noise glitch", $time);
        Din = 1;
        #10;
        Din = 0;
        #30;

        // ----------------------------------------------------
        // Test 2: Noise Glitch (2 clock cycles: 20ns) -> Filtered
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 2: 2-cycle noise glitch", $time);
        Din = 1;
        #20;
        Din = 0;
        #30;

        // ----------------------------------------------------
        // Test 3: Valid Pulse (3 clock cycles: 30ns) -> 1 beat detected
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 3: Valid 3-cycle pulse (Beat 1)", $time);
        Din = 1;
        #30;
        Din = 0;
        #40;

        // ----------------------------------------------------
        // Test 4: Wide Pulse (6 clock cycles: 60ns) -> Debounced
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 4: Wide pulse (Beat 2)", $time);
        Din = 1;
        #60;
        Din = 0;
        #40;

        // ----------------------------------------------------
        // Test 5 & 6: Active Heartbeats with Irregular Intervals (AFib Check)
        // ----------------------------------------------------
        $display("[Time %0t ns] Test 5 & 6: Continuous heartbeats with AFib arrhythmia...", $time);

        // Beat 3 (baseline interval = 40ns)
        Din = 1; #30; Din = 0; #40;

        // Beat 4 (regular interval = 40ns)
        Din = 1; #30; Din = 0; #40;

        // Beat 5 (Long irregular interval = 90ns -> AFib Trigger 1)
        #90;
        Din = 1; #30; Din = 0; #30;

        // Beat 6 (Short irregular interval = 30ns -> AFib Trigger 2: Alert ON!)
        #30;
        Din = 1; #30; Din = 0; #80;

        // Beat 7 (Long irregular interval = 80ns -> AFib Trigger 3: Alert stays ON!)
        #80;
        Din = 1; #30; Din = 0; #30;

        // Beat 8 (Active pulse right into final window -> BPM > 0 and AFib stays ON!)
        #30;
        Din = 1; #30; Din = 0; #30;

        // Latch final calculation
        #40;

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
