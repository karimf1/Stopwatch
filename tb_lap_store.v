`timescale 1ns/1ps
// Lap stack: shift order, depth overflow, the valid bitmap, and clear.
module tb_lap_store;

    localparam DEPTH = 5;
    localparam TW    = 24;

    reg                clk = 1'b0;
    reg                rst = 1'b1;
    reg                clr = 1'b0;
    reg                push = 1'b0;
    reg  [TW-1:0]      din = {TW{1'b0}};
    wire [DEPTH*TW-1:0] laps;
    wire [DEPTH-1:0]    valid;

    integer errors = 0;

    lap_store #(.DEPTH(DEPTH), .TW(TW)) dut (
        .clk(clk), .rst(rst), .clr(clr), .push(push),
        .din(din), .laps(laps), .valid(valid)
    );

    always #5 clk = ~clk;

    function [TW-1:0] slot;
        input integer i;
        begin
            slot = laps[i*TW +: TW];
        end
    endfunction

    task expect_slot;
        input integer i;
        input [TW-1:0] exp;
        begin
            if (slot(i) !== exp) begin
                errors = errors + 1;
                $display("** FAIL slot %0d: got %h expected %h", i, slot(i), exp);
            end
        end
    endtask

    task expect_valid;
        input [DEPTH-1:0] exp;
        input [800:0] what;
        begin
            if (valid !== exp) begin
                errors = errors + 1;
                $display("** FAIL %0s: valid=%b expected %b", what, valid, exp);
            end
        end
    endtask

    task do_push;
        input [TW-1:0] v;
        begin
            din <= v; push <= 1'b1;
            @(posedge clk);
            push <= 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    integer i;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk); #1;

        for (i = 0; i < DEPTH; i = i + 1) expect_slot(i, {TW{1'b0}});
        expect_valid(5'b00000, "nothing valid after reset");

        // fill one at a time -------------------------------------------------
        do_push(24'h000011);
        expect_slot(0, 24'h000011);
        expect_valid(5'b00001, "one lap stored");

        do_push(24'h000022);
        expect_slot(0, 24'h000022);
        expect_slot(1, 24'h000011);
        expect_valid(5'b00011, "two laps stored");

        do_push(24'h000033);
        do_push(24'h000044);
        do_push(24'h000055);
        expect_slot(0, 24'h000055);
        expect_slot(1, 24'h000044);
        expect_slot(2, 24'h000033);
        expect_slot(3, 24'h000022);
        expect_slot(4, 24'h000011);
        expect_valid(5'b11111, "stack full");
        $display("   ok: five pushes fill the stack newest-first");

        // sixth push drops the oldest ---------------------------------------
        do_push(24'h000066);
        expect_slot(0, 24'h000066);
        expect_slot(1, 24'h000055);
        expect_slot(2, 24'h000044);
        expect_slot(3, 24'h000033);
        expect_slot(4, 24'h000022);
        expect_valid(5'b11111, "valid saturates at full");
        $display("   ok: sixth push drops the oldest lap, all five shift together");

        // no push, no change --------------------------------------------------
        repeat (20) @(posedge clk); #1;
        expect_slot(0, 24'h000066);
        expect_slot(4, 24'h000022);
        $display("   ok: stack holds when push is low");

        // clear ---------------------------------------------------------------
        clr <= 1'b1; @(posedge clk); clr <= 1'b0; @(posedge clk); #1;
        for (i = 0; i < DEPTH; i = i + 1) expect_slot(i, {TW{1'b0}});
        expect_valid(5'b00000, "clear empties the stack");
        $display("   ok: clear empties the stack and the valid bitmap");

        // clear has priority over a simultaneous push --------------------------
        din <= 24'h000077; push <= 1'b1; clr <= 1'b1;
        @(posedge clk);
        push <= 1'b0; clr <= 1'b0;
        @(posedge clk); #1;
        expect_slot(0, {TW{1'b0}});
        expect_valid(5'b00000, "clear wins over a simultaneous push");
        $display("   ok: clear wins over a simultaneous push");

        $display("");
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED  (%0d errors)", errors);
        $finish;
    end

endmodule
