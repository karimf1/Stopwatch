`timescale 1ns/1ps
// sync2 -- N-flop synchronizer for an asynchronous input.
//
// Deliberately has no reset.  The debouncer downstream loads its steady-state
// value out of reset, which is what stops a button already held down at reset
// release from looking like a fresh press.  A reset here would defeat that.
//
// Declaration initialisers give a defined value at time 0 in simulation and set
// the power-up state on FPGAs that support it.

module sync2 #(
    parameter STAGES = 2,
    parameter INIT   = 1'b0
)(
    input  wire clk,
    input  wire din,        // asynchronous
    output wire dout        // synchronous to clk
);

    reg [STAGES-1:0] q = {STAGES{INIT}};

    always @(posedge clk)
        q <= {q[STAGES-2:0], din};

    assign dout = q[STAGES-1];

endmodule
