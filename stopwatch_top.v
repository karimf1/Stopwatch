`timescale 1ns/1ps
// stopwatch_top -- h:mm:ss.t stopwatch with a lap stack.
//
// Single clock domain.  The only asynchronous things in the design are the pins
// themselves, and every one of them is synchronised before it reaches a flop.
//
//   reset          async, active high.  Everything, including run state.
//   btn_start_stop momentary.  Each press toggles running.
//   btn_lap        momentary.  Each press pushes the current time onto the stack.
//   clr            level.      Holds the time and the lap stack at zero.
//                              Does not change running -- this is "restart",
//                              not "stop".
//   sw_view[i]     level.      Show stored lap i instead of the live time.
//                              Lowest asserted index wins.  Viewing a lap does
//                              not stop the count.
//
// Set CLK_HZ to the real board frequency; every derived interval follows from
// it.  A testbench can drop it to something small to make a tick cheap.

module stopwatch_top #(
    parameter CLK_HZ      = 50_000_000,
    parameter TICK_HZ     = 10,
    parameter DEBOUNCE_MS = 20,
    parameter LAP_DEPTH   = 5,
    parameter LZ_BLANK    = 0    // 1 = blank leading zero hours / minutes-tens
)(
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 btn_start_stop,
    input  wire                 btn_lap,
    input  wire                 clr,
    input  wire [LAP_DEPTH-1:0] sw_view,

    output wire [6:0]           hrs_display,
    output wire [6:0]           mins_tens_display,
    output wire [6:0]           mins_ones_display,
    output wire [6:0]           secs_tens_display,
    output wire [6:0]           secs_ones_display,
    output wire [6:0]           tenths_display,

    output wire                 running,
    output wire                 overflow,
    output wire                 viewing_lap,
    output wire [2:0]           view_index
);

    localparam TW = 24;         // { h, m_tens, m_ones, s_tens, s_ones, tenths }

    initial begin
        if (LAP_DEPTH > 8) begin
            $display("stopwatch_top: LAP_DEPTH %0d exceeds the 3-bit view_index",
                     LAP_DEPTH);
            $finish;
        end
    end

    // ---------------------------------------------------------------- reset

    wire rst;                   // sync-deassert, used synchronously downstream

    reset_sync u_rst (
        .clk     (clk),
        .arst_in (reset),
        .rst_out (rst)
    );

    // ------------------------------------------------------ input conditioning

    wire start_rise, lap_rise;
    wire clr_s;
    wire [LAP_DEPTH-1:0] sw_view_s;

    debounce #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS)) u_db_start (
        .clk   (clk),
        .rst   (rst),
        .din   (btn_start_stop),
        .level (),
        .rise  (start_rise),
        .fall  ()
    );

    debounce #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS)) u_db_lap (
        .clk   (clk),
        .rst   (rst),
        .din   (btn_lap),
        .level (),
        .rise  (lap_rise),
        .fall  ()
    );

    sync2 u_sync_clr (.clk(clk), .din(clr), .dout(clr_s));

    genvar gi;
    generate
        for (gi = 0; gi < LAP_DEPTH; gi = gi + 1) begin : sw_sync
            sync2 u_sync_sw (
                .clk  (clk),
                .din  (sw_view[gi]),
                .dout (sw_view_s[gi])
            );
        end
    endgenerate

    // ------------------------------------------------------------ run control

    reg running_q = 1'b0;

    always @(posedge clk) begin
        if (rst)             running_q <= 1'b0;
        else if (start_rise) running_q <= ~running_q;
    end

    // The press that turns the stopwatch ON also zeroes the divider phase, so
    // the first tenth is timed from the press instead of from wherever a
    // free-running divider happened to be.
    wire tick_restart = (start_rise & ~running_q) | clr_s;

    // -------------------------------------------------------------- timebase

    wire tick;

    tick_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(TICK_HZ)) u_tick (
        .clk     (clk),
        .rst     (rst),
        .restart (tick_restart),
        .tick    (tick)
    );

    // ---------------------------------------------------------------- counter

    wire [TW-1:0] live;

    time_counter u_count (
        .clk  (clk),
        .rst  (rst),
        .tick (tick),
        .run  (running_q),
        .clr  (clr_s),
        .tval (live),
        .ovf  (overflow)
    );

    // -------------------------------------------------------------- lap stack

    wire [LAP_DEPTH*TW-1:0] laps;
    wire [LAP_DEPTH-1:0]    lap_valid;

    lap_store #(.DEPTH(LAP_DEPTH), .TW(TW)) u_laps (
        .clk   (clk),
        .rst   (rst),
        .clr   (clr_s),
        .push  (lap_rise),
        .din   (live),
        .laps  (laps),
        .valid (lap_valid)
    );

    // ---------------------------------------------------------------- display

    wire [TW-1:0] dval;
    wire          blank_all;

    display_mux #(.DEPTH(LAP_DEPTH), .TW(TW)) u_mux (
        .sel         (sw_view_s),
        .valid       (lap_valid),
        .live        (live),
        .laps        (laps),
        .dout        (dval),
        .viewing_lap (viewing_lap),
        .view_index  (view_index),
        .blank       (blank_all)
    );

    wire [3:0] dig_h  = dval[23:20];
    wire [3:0] dig_mt = dval[19:16];
    wire [3:0] dig_mo = dval[15:12];
    wire [3:0] dig_st = dval[11:8];
    wire [3:0] dig_so = dval[7:4];
    wire [3:0] dig_t  = dval[3:0];

    // Optional leading-zero suppression.  Off by default: a stopwatch is easier
    // to read in a fixed H:MM:SS.T field than with digits appearing and
    // disappearing, so this is offered rather than assumed.
    wire lz    = (LZ_BLANK != 0);
    wire bl_h  = blank_all | (lz & (dig_h == 4'd0));
    wire bl_mt = blank_all | (lz & (dig_h == 4'd0) & (dig_mt == 4'd0));

    seg_decode u_h  (.bcd(dig_h),  .blank(bl_h),      .seg(hrs_display));
    seg_decode u_mt (.bcd(dig_mt), .blank(bl_mt),     .seg(mins_tens_display));
    seg_decode u_mo (.bcd(dig_mo), .blank(blank_all), .seg(mins_ones_display));
    seg_decode u_st (.bcd(dig_st), .blank(blank_all), .seg(secs_tens_display));
    seg_decode u_so (.bcd(dig_so), .blank(blank_all), .seg(secs_ones_display));
    seg_decode u_t  (.bcd(dig_t),  .blank(blank_all), .seg(tenths_display));

    assign running = running_q;

endmodule
