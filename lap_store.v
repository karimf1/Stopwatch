`timescale 1ns/1ps
// lap_store -- depth-DEPTH shift stack of captured times, newest in slot 0.
//
// Same idea as the original's hand-written five-slot shift register, but as an
// indexed array behind a flat port.  Verilog-2001 cannot pass an unpacked array
// through a port, so the stack is flattened to one vector and sliced with a
// constant-width part select; that is the portable alternative to writing out
// twenty individual ports.
//
// valid[i] marks a slot that has actually been written, so the display can blank
// an empty slot instead of showing a plausible-looking 0:00:00.0.

module lap_store #(
    parameter DEPTH = 5,
    parameter TW    = 24
)(
    input  wire                clk,
    input  wire                rst,     // synchronous, active high
    input  wire                clr,     // synchronous: drop all stored laps
    input  wire                push,    // one-clk capture strobe
    input  wire [TW-1:0]       din,
    output wire [DEPTH*TW-1:0] laps,    // slot i occupies laps[i*TW +: TW]
    output reg  [DEPTH-1:0]    valid
);

    reg [TW-1:0] mem [0:DEPTH-1];

    integer i;

    initial begin
        valid = {DEPTH{1'b0}};
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = {TW{1'b0}};
    end

    always @(posedge clk) begin
        if (rst || clr) begin
            for (i = 0; i < DEPTH; i = i + 1) mem[i] <= {TW{1'b0}};
            valid <= {DEPTH{1'b0}};
        end else if (push) begin
            // Every RHS reads the pre-edge value, so all DEPTH slots move at once.
            mem[0] <= din;
            for (i = 1; i < DEPTH; i = i + 1) mem[i] <= mem[i-1];
            valid <= {valid[DEPTH-2:0], 1'b1};
        end
    end

    genvar g;
    generate
        for (g = 0; g < DEPTH; g = g + 1) begin : pack
            assign laps[g*TW +: TW] = mem[g];
        end
    endgenerate

endmodule
