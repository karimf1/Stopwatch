`timescale 1ns/1ps
// reset_sync -- asynchronous assert, synchronous deassert.
//
// The raw board reset is asynchronous to clk, so releasing it can violate
// setup/hold on any flop it feeds and leave different flops leaving reset on
// different cycles.  This asserts immediately (async) and releases only on a
// clock edge, STAGES cycles later, so the whole design comes out of reset
// together.  It is the one place in the design that uses an async reset; every
// other module takes rst_out as a *synchronous* reset.
//
// Also guarantees a minimum reset width: an arst_in glitch shorter than a clock
// period is stretched to STAGES clocks.

module reset_sync #(
    parameter STAGES = 2
)(
    input  wire clk,
    input  wire arst_in,    // active high, asynchronous
    output wire rst_out     // active high, sync deassert
);

    reg [STAGES-1:0] sync = {STAGES{1'b1}};

    always @(posedge clk or posedge arst_in) begin
        if (arst_in) sync <= {STAGES{1'b1}};
        else         sync <= {sync[STAGES-2:0], 1'b0};
    end

    assign rst_out = sync[STAGES-1];

endmodule
