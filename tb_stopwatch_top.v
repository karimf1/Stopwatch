`timescale 1ns/1ps
// Integration: button semantics, run/pause, lap capture and viewing, clear,
// divider re-phasing on start, and the seven-segment path end to end.
module tb_stopwatch_top;

    localparam CLK_HZ  = 10_000;      // 1000 clocks per tick, 200 per debounce
    localparam TICK_HZ = 10;
    localparam DB_MS   = 20;
    localparam DEPTH   = 5;
    localparam DIV     = CLK_HZ / TICK_HZ;
    localparam DB_CYC  = (CLK_HZ / 1000) * DB_MS;

    reg              clk = 1'b0;
    reg              reset = 1'b1;
    reg              btn_start_stop = 1'b0;
    reg              btn_lap = 1'b0;
    reg              clr = 1'b0;
    reg  [DEPTH-1:0] sw_view = {DEPTH{1'b0}};

    wire [6:0] s_h, s_mt, s_mo, s_st, s_so, s_t;
    wire       running, overflow, viewing_lap;
    wire [2:0] view_index;

    integer errors = 0;
    integer cyc = 0;

    stopwatch_top #(
        .CLK_HZ(CLK_HZ), .TICK_HZ(TICK_HZ), .DEBOUNCE_MS(DB_MS), .LAP_DEPTH(DEPTH)
    ) dut (
        .clk(clk), .reset(reset),
        .btn_start_stop(btn_start_stop), .btn_lap(btn_lap),
        .clr(clr), .sw_view(sw_view),
        .hrs_display(s_h), .mins_tens_display(s_mt), .mins_ones_display(s_mo),
        .secs_tens_display(s_st), .secs_ones_display(s_so), .tenths_display(s_t),
        .running(running), .overflow(overflow),
        .viewing_lap(viewing_lap), .view_index(view_index)
    );

    always #5 clk = ~clk;
    always @(posedge clk) cyc <= cyc + 1;

    // ---- helpers ---------------------------------------------------------

    // inverse of seg_decode, so the display path is checked end to end
    function [4:0] seg2dig;
        input [6:0] s;
        begin
            case (s)
                7'b1000000: seg2dig = 5'd0;
                7'b1111001: seg2dig = 5'd1;
                7'b0100100: seg2dig = 5'd2;
                7'b0110000: seg2dig = 5'd3;
                7'b0011001: seg2dig = 5'd4;
                7'b0010010: seg2dig = 5'd5;
                7'b0000010: seg2dig = 5'd6;
                7'b1111000: seg2dig = 5'd7;
                7'b0000000: seg2dig = 5'd8;
                7'b0010000: seg2dig = 5'd9;
                7'b1111111: seg2dig = 5'h1F;     // blank
                default:    seg2dig = 5'h1E;     // not a legal pattern
            endcase
        end
    endfunction

    task expect_display;                 // check all six digits at once
        input [3:0] h, mt, mo, st, so, t;
        input [800:0] what;
        begin
            if (seg2dig(s_h)  !== {1'b0,h}  || seg2dig(s_mt) !== {1'b0,mt} ||
                seg2dig(s_mo) !== {1'b0,mo} || seg2dig(s_st) !== {1'b0,st} ||
                seg2dig(s_so) !== {1'b0,so} || seg2dig(s_t)  !== {1'b0,t}) begin
                errors = errors + 1;
                $display("** FAIL %0s: display reads %0d:%0d%0d:%0d%0d.%0d, expected %0d:%0d%0d:%0d%0d.%0d",
                         what, seg2dig(s_h), seg2dig(s_mt), seg2dig(s_mo),
                         seg2dig(s_st), seg2dig(s_so), seg2dig(s_t),
                         h, mt, mo, st, so, t);
            end else $display("   ok: %0s", what);
        end
    endtask

    task expect_blank;
        input [800:0] what;
        begin
            if (s_h !== 7'b1111111 || s_mt !== 7'b1111111 || s_mo !== 7'b1111111 ||
                s_st !== 7'b1111111 || s_so !== 7'b1111111 || s_t  !== 7'b1111111) begin
                errors = errors + 1;
                $display("** FAIL %0s: display not blank", what);
            end else $display("   ok: %0s", what);
        end
    endtask

    task expect_live;
        input [23:0] exp;
        input [800:0] what;
        begin
            if (dut.live !== exp) begin
                errors = errors + 1;
                $display("** FAIL %0s: live=%h expected %h", what, dut.live, exp);
            end else $display("   ok: %0s", what);
        end
    endtask

    task chk;
        input cond;
        input [800:0] what;
        begin
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("** FAIL %0s", what);
            end else $display("   ok: %0s", what);
        end
    endtask

    task press_start;
        begin
            btn_start_stop <= 1'b1; repeat (DB_CYC + 20) @(posedge clk);
            btn_start_stop <= 1'b0; repeat (DB_CYC + 20) @(posedge clk);
        end
    endtask

    task press_lap;
        begin
            btn_lap <= 1'b1; repeat (DB_CYC + 20) @(posedge clk);
            btn_lap <= 1'b0; repeat (DB_CYC + 20) @(posedge clk);
        end
    endtask

    task wait_ticks;                    // wait for N tick strobes
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge dut.tick);
            @(posedge clk); #1;
        end
    endtask

    // ---- divider re-phasing measurement ----------------------------------
    integer run_cyc = -1;
    integer first_tick_cyc = -1;
    reg run_d = 1'b0;
    always @(posedge clk) begin
        run_d <= running;
        if (running && !run_d && run_cyc < 0) run_cyc <= cyc;
        if (dut.tick && run_cyc >= 0 && first_tick_cyc < 0) first_tick_cyc <= cyc;
    end

    reg [23:0] frozen;

    initial begin
        repeat (5) @(posedge clk);
        reset <= 1'b0;
        repeat (10) @(posedge clk); #1;

        // ---- reset state --------------------------------------------------
        chk(~running, "stopped after reset");
        expect_display(0,0,0,0,0,0, "reset shows 0:00:00.0");
        chk(~viewing_lap, "not viewing a lap after reset");
        chk(~overflow, "overflow clear after reset");

        // ---- a press starts it --------------------------------------------
        press_start;
        chk(running, "one press starts the count");

        // ---- counts at one tenth per tick ----------------------------------
        wait_ticks(7);
        expect_live(24'h000007, "seven ticks reads 0:00:00.7");
        expect_display(0,0,0,0,0,7, "display tracks the count");

        // ---- divider is re-phased by the start press -----------------------
        chk((first_tick_cyc - run_cyc) == DIV,
            "first tick lands exactly one divider period after start");
        if ((first_tick_cyc - run_cyc) != DIV)
            $display("      measured %0d cycles, DIV=%0d", first_tick_cyc - run_cyc, DIV);

        // ---- roll tenths into seconds ---------------------------------------
        wait_ticks(5);
        expect_live(24'h000012, "twelve ticks reads 0:00:01.2");
        expect_display(0,0,0,0,1,2, "tenths rolled into seconds on the display");

        // ---- second press stops it, value holds ------------------------------
        press_start;
        chk(~running, "second press stops the count");
        frozen = dut.live;
        repeat (DIV * 3) @(posedge clk); #1;
        expect_live(frozen, "value frozen while stopped");

        // ---- lap capture while stopped ---------------------------------------
        press_lap;
        chk(dut.u_laps.valid == 5'b00001, "lap 0 captured");
        sw_view <= 5'b00001;
        repeat (6) @(posedge clk); #1;
        chk(viewing_lap, "viewing_lap asserted");
        chk(view_index == 3'd0, "view_index reports slot 0");
        if (dut.dval !== frozen) begin
            errors = errors + 1;
            $display("** FAIL lap 0 shows %h, expected the frozen time %h", dut.dval, frozen);
        end else $display("   ok: lap 0 shows the time that was captured");

        // ---- an unwritten slot blanks instead of showing 0:00:00.0 ------------
        sw_view <= 5'b00100;
        repeat (6) @(posedge clk); #1;
        expect_blank("unwritten lap slot blanks the display");
        chk(view_index == 3'd2, "view_index reports slot 2");

        // ---- viewing a lap does not stop the counter --------------------------
        sw_view <= 5'b00001;
        press_start;                     // start it again, still viewing lap 0
        chk(running, "restarted while viewing a lap");
        wait_ticks(4);
        if (dut.dval !== frozen) begin
            errors = errors + 1;
            $display("** FAIL display moved while pinned to a lap");
        end else $display("   ok: display stays pinned to the lap while time runs on");
        if (dut.live === frozen) begin
            errors = errors + 1;
            $display("** FAIL live time did not advance behind the lap view");
        end else $display("   ok: live time advanced behind the lap view");

        // ---- dropping the switch snaps back to live ---------------------------
        sw_view <= 5'b00000;
        repeat (6) @(posedge clk); #1;
        chk(~viewing_lap, "viewing_lap clears");
        if (dut.dval !== dut.live) begin
            errors = errors + 1;
            $display("** FAIL display did not snap back to the live time");
        end else $display("   ok: display snaps back to the live time");

        // ---- more laps, and priority ------------------------------------------
        press_lap;                       // -> slot 0, old slot 0 shifts to 1
        wait_ticks(3);
        press_lap;                       // -> slot 0 again
        chk(dut.u_laps.valid == 5'b00111, "three laps stored");
        sw_view <= 5'b00011;             // both 0 and 1 asserted
        repeat (6) @(posedge clk); #1;
        chk(view_index == 3'd0, "lowest asserted switch wins");
        if (dut.dval !== dut.u_laps.mem[0]) begin
            errors = errors + 1;
            $display("** FAIL priority mux picked the wrong slot");
        end else $display("   ok: priority mux picked slot 0");

        // ---- clear zeroes the time and the laps, run state untouched ----------
        sw_view <= 5'b00000;
        repeat (4) @(posedge clk);
        chk(running, "still running before clear");
        clr <= 1'b1;
        repeat (10) @(posedge clk);
        clr <= 1'b0;
        repeat (6) @(posedge clk); #1;
        expect_live(24'h000000, "clear zeroes the time");
        chk(dut.u_laps.valid == 5'b00000, "clear drops every stored lap");
        chk(running, "clear leaves the stopwatch running");
        wait_ticks(2);
        expect_live(24'h000002, "counting continues from zero after clear");

        // ---- reset stops it as well as clearing --------------------------------
        reset <= 1'b1;
        repeat (6) @(posedge clk);
        reset <= 1'b0;
        repeat (6) @(posedge clk); #1;
        chk(~running, "reset stops the stopwatch");
        expect_live(24'h000000, "reset zeroes the time");

        $display("");
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED  (%0d errors)", errors);
        $finish;
    end

endmodule
