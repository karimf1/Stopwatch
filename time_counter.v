`timescale 1ns/1ps
// time_counter -- h:mm:ss.t held directly as BCD digits.
//
// The original stored seconds and minutes as 0..59 binary and split them for
// display with "/ 10" and "% 10".  Counting in BCD in the first place deletes
// that arithmetic: each digit is already what its seven-segment decoder wants.
//
// Ripple is avoided -- the carries are combinational ANDs off the digit-at-max
// comparisons, so every digit updates on the same clock edge and the whole
// chain is one clk cycle deep, not six.
//
// Word layout, MSB first: { h, m_tens, m_ones, s_tens, s_ones, tenths }

module time_counter (
    input  wire        clk,
    input  wire        rst,        // synchronous, active high
    input  wire        tick,       // one-clk strobe at the display resolution
    input  wire        run,        // count only while high
    input  wire        clr,        // synchronous zero, does not affect run
    output wire [23:0] tval,
    output reg         ovf         // sticky: has wrapped past 9:59:59.9
);

    reg [3:0] d_t  = 4'd0;      // tenths   0..9
    reg [3:0] d_so = 4'd0;      // secs     0..9
    reg [3:0] d_st = 4'd0;      //          0..5
    reg [3:0] d_mo = 4'd0;      // mins     0..9
    reg [3:0] d_mt = 4'd0;      //          0..5
    reg [3:0] d_h  = 4'd0;      // hours    0..9

    initial ovf = 1'b0;

    wire en = tick & run;

    wire t_max  = (d_t  == 4'd9);
    wire so_max = (d_so == 4'd9);
    wire st_max = (d_st == 4'd5);
    wire mo_max = (d_mo == 4'd9);
    wire mt_max = (d_mt == 4'd5);
    wire h_max  = (d_h  == 4'd9);

    wire c_t  = en;
    wire c_so = c_t  & t_max;
    wire c_st = c_so & so_max;
    wire c_mo = c_st & st_max;
    wire c_mt = c_mo & mo_max;
    wire c_h  = c_mt & mt_max;
    wire wrap = c_h  & h_max;

    always @(posedge clk) begin
        if (rst || clr) begin
            d_t  <= 4'd0;
            d_so <= 4'd0;
            d_st <= 4'd0;
            d_mo <= 4'd0;
            d_mt <= 4'd0;
            d_h  <= 4'd0;
            ovf  <= 1'b0;
        end else begin
            if (c_t)  d_t  <= t_max  ? 4'd0 : d_t  + 4'd1;
            if (c_so) d_so <= so_max ? 4'd0 : d_so + 4'd1;
            if (c_st) d_st <= st_max ? 4'd0 : d_st + 4'd1;
            if (c_mo) d_mo <= mo_max ? 4'd0 : d_mo + 4'd1;
            if (c_mt) d_mt <= mt_max ? 4'd0 : d_mt + 4'd1;
            if (c_h)  d_h  <= h_max  ? 4'd0 : d_h  + 4'd1;
            if (wrap) ovf  <= 1'b1;     // sticky until rst or clr
        end
    end

    assign tval = {d_h, d_mt, d_mo, d_st, d_so, d_t};

endmodule
