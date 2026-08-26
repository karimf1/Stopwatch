`timescale 1ns/1ps
// Exhaustive: walks the counter through all 360,000 tenths of its 10-hour range
// and compares every single one against an independent model.
module tb_time_counter;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         tick = 1'b0;
    reg         run = 1'b0;
    reg         clr = 1'b0;
    wire [23:0] tval;
    wire        ovf;

    integer errors = 0;
    integer checks = 0;

    time_counter dut (
        .clk(clk), .rst(rst), .tick(tick), .run(run), .clr(clr),
        .tval(tval), .ovf(ovf)
    );

    always #5 clk = ~clk;

    // Independent model: elapsed tenths -> packed BCD word.
    function [23:0] model;
        input integer e;
        integer s, m, h;
        reg [3:0] nh, nmt, nmo, nst, nso, nt;
        begin
            s   = (e / 10)    % 60;
            m   = (e / 600)   % 60;
            h   = (e / 36000) % 10;
            nh  = h[3:0];
            nmt = (m / 10);
            nmo = (m % 10);
            nst = (s / 10);
            nso = (s % 10);
            nt  = (e % 10);
            model = { nh, nmt, nmo, nst, nso, nt };
        end
    endfunction

    task check;
        input [23:0] got, exp;
        input [800:0] what;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("** FAIL %0s: got %h expected %h at t=%0t",
                             what, got, exp, $time);
            end
        end
    endtask

    integer i;
    reg [23:0] snapshot;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        // --- reset state -------------------------------------------------
        check(tval, 24'h000000, "reset clears the count");
        if (ovf !== 1'b0) begin errors = errors + 1; $display("** FAIL ovf set after reset"); end

        // --- paused: ticks must not advance anything ---------------------
        run <= 1'b0; tick <= 1'b1;
        repeat (50) @(posedge clk);
        check(tval, 24'h000000, "ticks ignored while run is low");

        // --- exhaustive walk over the whole 10-hour range ----------------
        run <= 1'b1; tick <= 1'b1;
        for (i = 1; i <= 360000; i = i + 1) begin
            @(posedge clk);
            #1;
            check(tval, model(i % 360000), "counting");
            // ovf must stay clear until the wrap, then latch high
            if (i < 360000 && ovf !== 1'b0) begin
                errors = errors + 1;
                if (errors <= 10) $display("** FAIL ovf early at tick %0d", i);
            end
            if (i == 360000 && ovf !== 1'b1) begin
                errors = errors + 1;
                $display("** FAIL ovf did not latch on wrap");
            end
        end
        $display("   walked 360000 tenths: 0:00:00.0 -> 9:59:59.9 -> wrap");

        // --- ovf is sticky ------------------------------------------------
        repeat (100) @(posedge clk);
        if (ovf !== 1'b1) begin errors = errors + 1; $display("** FAIL ovf not sticky"); end

        // --- tick gating: a tick every 3rd cycle advances once per tick ---
        run <= 1'b0; tick <= 1'b0; @(posedge clk);
        clr <= 1'b1; @(posedge clk); clr <= 1'b0; @(posedge clk); #1;
        check(tval, 24'h000000, "clr zeroes the count");
        if (ovf !== 1'b0) begin errors = errors + 1; $display("** FAIL clr did not clear ovf"); end

        run <= 1'b1; tick <= 1'b0;
        for (i = 1; i <= 25; i = i + 1) begin
            @(posedge clk); tick <= 1'b1;
            @(posedge clk); tick <= 1'b0;
            @(posedge clk);
            @(posedge clk);
            #1;
            check(tval, model(i), "one advance per tick, not per clock");
        end

        // --- pause holds the value across many clocks --------------------
        snapshot = tval;
        run <= 1'b0;
        repeat (200) begin @(posedge clk); tick <= ~tick; end
        #1;
        check(tval, snapshot, "value frozen while paused");

        // --- resume continues from where it stopped ----------------------
        run <= 1'b1; tick <= 1'b1;
        @(posedge clk); #1;
        check(tval, model(26), "resumes from the paused value");

        $display("");
        if (errors == 0) $display("TEST PASSED  (%0d checks)", checks);
        else             $display("TEST FAILED  (%0d errors / %0d checks)", errors, checks);
        $finish;
    end

endmodule
