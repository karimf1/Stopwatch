`timescale 1ns/1ps
// tick_gen -- one-clk-wide strobe at TICK_HZ, derived from CLK_HZ.
//
// This replaces the divided *clock* of the original design.  Emitting an enable
// pulse instead of a square wave keeps the entire stopwatch in a single clock
// domain, which removes the clock-domain crossing on lap capture, removes the
// need for a derived-clock timing constraint, and keeps every flop on the global
// clock network instead of a routed logic output.
//
// tick is high for exactly one clk cycle once every CLK_HZ/TICK_HZ cycles.
//
// restart zeroes the divider phase.  The top level pulses it when the stopwatch
// starts, so the first tenth is measured from the button press rather than from
// wherever a free-running divider happened to be -- otherwise the first 0.1 on
// the display represents somewhere between 0 and 100 ms of real elapsed time.

module tick_gen #(
    parameter CLK_HZ  = 50_000_000,
    parameter TICK_HZ = 10
)(
    input  wire clk,
    input  wire rst,        // synchronous, active high
    input  wire restart,    // synchronous: zero the divider phase
    output reg  tick
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1) clog2 = clog2 + 1;
        end
    endfunction

    localparam integer DIV_RAW = CLK_HZ / TICK_HZ;
    localparam integer DIV     = (DIV_RAW < 2) ? 2 : DIV_RAW;
    localparam integer CW      = (clog2(DIV) > 0) ? clog2(DIV) : 1;

    reg [CW-1:0] cnt = {CW{1'b0}};

    initial tick = 1'b0;

    always @(posedge clk) begin
        if (rst || restart) begin
            cnt  <= {CW{1'b0}};
            tick <= 1'b0;
        end else if (cnt == DIV - 1) begin
            cnt  <= {CW{1'b0}};
            tick <= 1'b1;
        end else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end

endmodule
