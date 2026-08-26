`timescale 1ns/1ps
// Debouncer: bounce rejection, edge-pulse shape, and the "button already held at
// reset release" case that made the original design capture a phantom lap.
module tb_debounce;

    localparam CLK_HZ = 1000;      // 1 ms per cycle -> DEBOUNCE_MS 20 = 20 cycles
    localparam MS     = 20;
    localparam TICKS  = 20;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    reg  din = 1'b0;
    wire level, rise, fall;

    integer errors = 0;
    integer n_rise = 0, n_fall = 0;
    integer rise_run = 0, max_rise_run = 0;

    debounce #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(MS)) dut (
        .clk(clk), .rst(rst), .din(din),
        .level(level), .rise(rise), .fall(fall)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rise) n_rise <= n_rise + 1;
        if (fall) n_fall <= n_fall + 1;
        // pulses must never be wider than one cycle
        if (rise) rise_run <= rise_run + 1; else rise_run <= 0;
        if (rise_run > max_rise_run) max_rise_run = rise_run;
    end

    task expect_counts;
        input integer er, ef;
        input [800:0] what;
        begin
            if (n_rise !== er || n_fall !== ef) begin
                errors = errors + 1;
                $display("** FAIL %0s: rise=%0d fall=%0d, expected rise=%0d fall=%0d",
                         what, n_rise, n_fall, er, ef);
            end else begin
                $display("   ok: %0s", what);
            end
        end
    endtask

    task clear_counts; begin n_rise = 0; n_fall = 0; end endtask

    integer i;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        repeat (4) @(posedge clk);
        clear_counts;

        // 1. clean press ---------------------------------------------------
        din <= 1'b1;
        repeat (TICKS + 8) @(posedge clk);
        expect_counts(1, 0, "clean press gives exactly one rise");
        if (level !== 1'b1) begin errors = errors + 1; $display("** FAIL level did not follow press"); end

        // 2. clean release -------------------------------------------------
        clear_counts;
        din <= 1'b0;
        repeat (TICKS + 8) @(posedge clk);
        expect_counts(0, 1, "clean release gives exactly one fall");

        // 3. glitch shorter than the window is rejected ---------------------
        clear_counts;
        din <= 1'b1;
        repeat (TICKS - 5) @(posedge clk);   // not long enough
        din <= 1'b0;
        repeat (TICKS + 10) @(posedge clk);
        expect_counts(0, 0, "glitch shorter than the window is ignored");

        // 4. bounce train, then settle high ---------------------------------
        clear_counts;
        for (i = 0; i < 12; i = i + 1) begin
            din <= 1'b1; repeat (3) @(posedge clk);
            din <= 1'b0; repeat (2) @(posedge clk);
        end
        din <= 1'b1;                          // finally settles
        repeat (TICKS + 8) @(posedge clk);
        expect_counts(1, 0, "bounce train then settle gives exactly one rise");

        // 5. bounce on release ---------------------------------------------
        clear_counts;
        for (i = 0; i < 12; i = i + 1) begin
            din <= 1'b0; repeat (4) @(posedge clk);
            din <= 1'b1; repeat (2) @(posedge clk);
        end
        din <= 1'b0;
        repeat (TICKS + 8) @(posedge clk);
        expect_counts(0, 1, "bounce train on release gives exactly one fall");

        // 6. THE FIX: button already held down when reset is released -------
        //    v1 reset stable to 0, so the held button looked like a fresh
        //    press once the debounce interval expired, and captured a lap.
        din <= 1'b1;
        repeat (TICKS + 8) @(posedge clk);    // let it settle high
        rst <= 1'b1;
        repeat (6) @(posedge clk);
        clear_counts;
        rst <= 1'b0;                          // release with the button still down
        repeat (TICKS * 3) @(posedge clk);
        expect_counts(0, 0, "button held across reset release makes no phantom edge");
        if (level !== 1'b1) begin
            errors = errors + 1;
            $display("** FAIL level should already read the held button after reset");
        end

        // 7. and a real press after that still works ------------------------
        clear_counts;
        din <= 1'b0;
        repeat (TICKS + 8) @(posedge clk);
        din <= 1'b1;
        repeat (TICKS + 8) @(posedge clk);
        expect_counts(1, 1, "a genuine press after that is still detected");

        // 8. pulse width -----------------------------------------------------
        if (max_rise_run > 1) begin
            errors = errors + 1;
            $display("** FAIL rise pulse was %0d cycles wide, expected 1", max_rise_run);
        end else begin
            $display("   ok: rise is a single-cycle pulse");
        end

        $display("");
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED  (%0d errors)", errors);
        $finish;
    end

endmodule
