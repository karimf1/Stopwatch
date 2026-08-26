`timescale 1ns/1ps
// debounce -- synchroniser + integrating debouncer + edge detector.
//
// The counter only runs while the raw input disagrees with the currently
// accepted level, and any bounce back to that level restarts it from zero.  So
// the input must hold its new state *continuously* for DEBOUNCE_MS before it is
// believed.  A plain "wait N ms then sample" timer can be fooled by a bounce
// train that happens to be settled at the sampling instant; this cannot.
//
// Out of reset, level loads the synchronised pin rather than 0.  That is what
// stops a button that is already held down at reset release from producing a
// phantom 0->1 edge once the debounce interval expires.

module debounce #(
    parameter CLK_HZ      = 50_000_000,
    parameter DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,        // synchronous, active high
    input  wire din,        // raw asynchronous pin
    output reg  level,      // debounced level
    output wire rise,       // one-clk pulse on 0 -> 1
    output wire fall        // one-clk pulse on 1 -> 0
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1) clog2 = clog2 + 1;
        end
    endfunction

    localparam integer TICKS_RAW = (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer TICKS     = (TICKS_RAW < 2) ? 2 : TICKS_RAW;
    localparam integer CW        = (clog2(TICKS) > 0) ? clog2(TICKS) : 1;

    wire din_s;

    sync2 u_sync (
        .clk  (clk),
        .din  (din),
        .dout (din_s)
    );

    reg [CW-1:0] cnt  = {CW{1'b0}};
    reg          prev = 1'b0;

    initial level = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            cnt   <= {CW{1'b0}};
            level <= din_s;     // adopt the pin as-is: no phantom edge at release
            prev  <= din_s;
        end else begin
            prev <= level;      // non-blocking: prev gets the pre-update level
            if (din_s == level) begin
                cnt <= {CW{1'b0}};
            end else if (cnt == TICKS - 1) begin
                cnt   <= {CW{1'b0}};
                level <= din_s;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

    assign rise =  level & ~prev;
    assign fall = ~level &  prev;

endmodule
