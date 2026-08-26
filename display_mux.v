`timescale 1ns/1ps
// display_mux -- pick the live time or one stored lap.
//
// Replaces the original's six-way if/else-if chain over five separate switch
// inputs.  Same priority (lowest-numbered asserted switch wins, live time as the
// fall-through) but driven off a bus, so adding lap depth costs no source.
//
// The loop runs downwards so slot 0 is assigned last and therefore wins.

module display_mux #(
    parameter DEPTH = 5,
    parameter TW    = 24
)(
    input  wire [DEPTH-1:0]    sel,
    input  wire [DEPTH-1:0]    valid,
    input  wire [TW-1:0]       live,
    input  wire [DEPTH*TW-1:0] laps,
    output reg  [TW-1:0]       dout,
    output reg                 viewing_lap,
    output reg  [2:0]          view_index,
    output reg                 blank        // selected slot was never written
);

    integer i;

    always @(*) begin
        dout        = live;
        viewing_lap = 1'b0;
        view_index  = 3'd0;
        blank       = 1'b0;
        for (i = DEPTH - 1; i >= 0; i = i - 1) begin
            if (sel[i]) begin
                dout        = laps[i*TW +: TW];
                viewing_lap = 1'b1;
                view_index  = i[2:0];
                blank       = ~valid[i];
            end
        end
    end

endmodule
