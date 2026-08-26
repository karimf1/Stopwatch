`timescale 1ns/1ps
// No reset is ever asserted.  v1 sat at X forever; v2 must power up defined.
module tb_no_reset;
    localparam CLK_HZ = 10_000;
    reg clk = 1'b0, btn_ss = 1'b0, btn_lap = 1'b0, clr = 1'b0;
    reg [4:0] sw = 5'b0;
    wire [6:0] a,b,c,d,e,f; wire run, ovf, vl; wire [2:0] vi;
    integer errors = 0;

    stopwatch_top #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .reset(1'b0), .btn_start_stop(btn_ss), .btn_lap(btn_lap),
        .clr(clr), .sw_view(sw),
        .hrs_display(a), .mins_tens_display(b), .mins_ones_display(c),
        .secs_tens_display(d), .secs_ones_display(e), .tenths_display(f),
        .running(run), .overflow(ovf), .viewing_lap(vl), .view_index(vi));

    always #5 clk = ~clk;

    initial begin
        #1;
        $display("at time 0, with reset tied low the whole time:");
        $display("  live=%h  tick=%b  running=%b  hrs_seg=%b", dut.live, dut.tick, run, a);
        if (^{dut.live, dut.tick, run, a, b, c, d, e, f} === 1'bx) begin
            errors = errors + 1;
            $display("** FAIL something is X at time 0");
        end
        // run it and confirm it actually counts without ever seeing a reset
        btn_ss <= 1'b1; repeat (220) @(posedge clk);
        btn_ss <= 1'b0; repeat (220) @(posedge clk);
        repeat (5) @(posedge dut.tick); @(posedge clk); #1;
        $display("  after start + 5 ticks: live=%h running=%b", dut.live, run);
        if (dut.live !== 24'h000005) begin
            errors = errors + 1;
            $display("** FAIL counted %h, expected 000005", dut.live);
        end
        $display("");
        if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
