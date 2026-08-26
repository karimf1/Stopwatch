`timescale 1ns/1ps
// Side by side: the v1 lap store and the v2 debouncer, both handed a capture
// button that is already held down when reset is released.
//
// v1 forces sw_stable to 0 on reset, so a held button reads as a 0->1 edge once
// the debounce interval expires and a lap nobody asked for lands on the stack.
// v2 loads the synchronised pin instead, so there is no edge to detect.
//
// PASSES when v1 shows the bug and v2 does not.  If v1 ever stops showing it,
// this testbench is lying about the history and should be looked at.
module tb_v1_phantom_lap;

    localparam CLK_HZ = 50_000_000;
    localparam DB_MS  = 20;
    localparam WINDOW = (CLK_HZ / 1000) * DB_MS;   // 1,000,000 cycles

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg btn = 1'b1;                 // held down the whole time

    // a recognisable time so a phantom capture is visible
    wire [3:0] in_h = 4'd3;
    wire [5:0] in_m = 6'd25;
    wire [5:0] in_s = 6'd45;
    wire [3:0] in_t = 4'd6;

    integer errors = 0;

    always #10 clk = ~clk;

    // ---- v1 -------------------------------------------------------------
    wire [3:0] h0_v1, h1_v1, h2_v1, h3_v1, h4_v1;
    wire [5:0] m0_v1, m1_v1, m2_v1, m3_v1, m4_v1;
    wire [5:0] s0_v1, s1_v1, s2_v1, s3_v1, s4_v1;
    wire [3:0] t0_v1, t1_v1, t2_v1, t3_v1, t4_v1;

    storage_values v1 (
        .clk(clk), .reset(rst),
        .in_hours(in_h), .in_minutes(in_m), .in_seconds(in_s), .in_tenths(in_t),
        .sw_capture(btn),
        .h0(h0_v1), .m0(m0_v1), .s0(s0_v1), .t0(t0_v1),
        .h1(h1_v1), .m1(m1_v1), .s1(s1_v1), .t1(t1_v1),
        .h2(h2_v1), .m2(m2_v1), .s2(s2_v1), .t2(t2_v1),
        .h3(h3_v1), .m3(m3_v1), .s3(s3_v1), .t3(t3_v1),
        .h4(h4_v1), .m4(m4_v1), .s4(s4_v1), .t4(t4_v1)
    );

    // ---- v2 -------------------------------------------------------------
    wire v2_rise;
    integer v2_rises = 0;

    debounce #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DB_MS)) v2 (
        .clk(clk), .rst(rst), .din(btn),
        .level(), .rise(v2_rise), .fall()
    );

    always @(posedge clk) if (v2_rise) v2_rises <= v2_rises + 1;

    initial begin
        $display("Capture button held down across reset release.");
        $display("Nobody presses anything after that.\n");

        repeat (20) @(posedge clk);
        rst <= 1'b0;                      // release reset, button still down

        repeat (WINDOW * 2 + 100) @(posedge clk);
        #1;

        $display("v1 storage_values : lap slot 0 = %0d:%0d:%0d.%0d",
                 h0_v1, m0_v1, s0_v1, t0_v1);
        $display("v2 debounce       : rise pulses = %0d", v2_rises);
        $display("");

        if ({h0_v1, m0_v1, s0_v1, t0_v1} === {4'd0, 6'd0, 6'd0, 4'd0}) begin
            errors = errors + 1;
            $display("** v1 did NOT store a phantom lap -- this demo no longer");
            $display("   reproduces the bug it claims to.");
        end else begin
            $display("   v1 stored a lap nobody asked for.  Bug reproduced.");
        end

        if (v2_rises != 0) begin
            errors = errors + 1;
            $display("** FAIL v2 produced %0d edge(s); the fix is not working.", v2_rises);
        end else begin
            $display("   v2 produced no edge.  Fix confirmed.");
        end

        $display("");
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED  (%0d errors)", errors);
        $finish;
    end

endmodule
