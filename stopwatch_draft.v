module stopwatch_draft(
    input wire clk,
    input wire reset,
    input wire sw_start,
    input wire sw_capture,
    input wire sw0, sw1, sw2, sw3, sw4,
    output [6:0] hrs_display,
    output [6:0] mins_tens_display,
    output [6:0] mins_ones_display,
    output [6:0] secs_tens_display,
    output [6:0] secs_ones_display,
    output [6:0] ms_display
);

    wire clk_10hz;
     
    clock_dividermain CD(
        .clk(clk),
        .reset(reset),
        .clk_10hz(clk_10hz)
    );

    wire enable = sw_start;

    wire [3:0] hrs;
    wire [5:0] mins, secs;
    wire [3:0] ms;
     
    wire [3:0] hrs_prev1, hrs_prev2, hrs_prev3, hrs_prev4, hrs_prev5;
    wire [5:0] mins_prev1, mins_prev2, mins_prev3, mins_prev4, mins_prev5;
    wire [5:0] secs_prev1, secs_prev2, secs_prev3, secs_prev4, secs_prev5;
    wire [3:0] ms_prev1, ms_prev2, ms_prev3, ms_prev4, ms_prev5;
     

    time_counter_dec TC(
        .clk(clk_10hz), 
        .reset(reset),
        .enable(enable),
        .hrs(hrs),
        .mins(mins),
        .secs(secs),
        .ms(ms)
    );

    storage_values STO(
        .clk(clk),
        .reset(reset),
        .in_hours(hrs),
        .in_minutes(mins),
        .in_seconds(secs),
        .in_tenths(ms),
        .sw_capture(sw_capture),
        .h0(hrs_prev1), .m0(mins_prev1), .s0(secs_prev1), .t0(ms_prev1),
        .h1(hrs_prev2), .m1(mins_prev2), .s1(secs_prev2), .t1(ms_prev2),
        .h2(hrs_prev3), .m2(mins_prev3), .s2(secs_prev3), .t2(ms_prev3),
        .h3(hrs_prev4), .m3(mins_prev4), .s3(secs_prev4), .t3(ms_prev4),
        .h4(hrs_prev5), .m4(mins_prev5), .s4(secs_prev5), .t4(ms_prev5)
    );

    display_stored DISP(
        .clk(clk),
        .sw0(sw0), .sw1(sw1), .sw2(sw2), .sw3(sw3), .sw4(sw4),
        .hrs(hrs), .mins(mins), .secs(secs), .ms(ms),
        
        .hrs_prev1(hrs_prev1), .hrs_prev2(hrs_prev2), .hrs_prev3(hrs_prev3), .hrs_prev4(hrs_prev4), .hrs_prev5(hrs_prev5),
        .mins_prev1(mins_prev1), .mins_prev2(mins_prev2), .mins_prev3(mins_prev3), .mins_prev4(mins_prev4), .mins_prev5(mins_prev5),
        .secs_prev1(secs_prev1), .secs_prev2(secs_prev2), .secs_prev3(secs_prev3), .secs_prev4(secs_prev4), .secs_prev5(secs_prev5),
        .ms_prev1(ms_prev1), .ms_prev2(ms_prev2), .ms_prev3(ms_prev3), .ms_prev4(ms_prev4), .ms_prev5(ms_prev5),
        
        .hrs_dis(hrs_display), 
        .mins_tens_dis(mins_tens_display), .mins_ones_dis(mins_ones_display), 
        .secs_tens_dis(secs_tens_display), .secs_ones_dis(secs_ones_display),
        .ms_dis(ms_display)
    );

endmodule


module clock_dividermain(
	input wire clk,
	input wire reset,
	output reg clk_10hz
);
	reg [22:0] counter_10hz = 0;

	always @(posedge clk or posedge reset) 
		begin
			if(reset) 
				begin
					counter_10hz <= 0;
					clk_10hz <= 0;
				end 
			else 
				begin
					if(counter_10hz == 23'd2499999) 
						begin
							counter_10hz <= 0;
							clk_10hz <= ~clk_10hz;
						end 
					else
						counter_10hz <= counter_10hz + 1;
				end
		end
endmodule
module time_counter_dec(
    input wire clk,
    input wire reset,
    input wire enable,      
    output reg [3:0] hrs,
    output reg [5:0] mins,
    output reg [5:0] secs,
    output reg [3:0] ms
);
    always @(posedge clk or posedge reset) 
		begin
        if(reset) 
				begin
					hrs <= 0;
					mins <= 0;
					secs <= 0;
					ms  <= 0;
				end 
        else if(enable) 
				begin  
					if(ms < 9)
						ms <= ms + 1;
					else 
						begin
							ms <= 0;
								if(secs < 59)
									secs <= secs + 1;
								else 
									begin
										secs <= 0;
										if(mins < 59)
											mins <= mins + 1;
										else 
											begin
												mins <= 0;
												if(hrs < 9)
													hrs <= hrs + 1;
												else
													hrs <= 0;
											end
									end
						end
				end
		end
endmodule


module storage_values(
	input  wire clk,
	input  wire reset,

	input  wire [3:0] in_hours,
	input  wire [5:0] in_minutes,
	input  wire [5:0] in_seconds,
	input  wire [3:0] in_tenths,

	input  wire sw_capture,

	output reg [3:0] h0, output reg [5:0] m0, output reg [5:0] s0, output reg [3:0] t0,
	output reg [3:0] h1, output reg [5:0] m1, output reg [5:0] s1, output reg [3:0] t1,
	output reg [3:0] h2, output reg [5:0] m2, output reg [5:0] s2, output reg [3:0] t2,
	output reg [3:0] h3, output reg [5:0] m3, output reg [5:0] s3, output reg [3:0] t3,
	output reg [3:0] h4, output reg [5:0] m4, output reg [5:0] s4, output reg [3:0] t4
);
    
   reg [19:0] db_count;
   reg sw_stable;
   reg sw_stable_prev;
	wire capture_pulse;

	always @(posedge clk or posedge reset) 
		begin
			if(reset) 
				begin
					db_count <= 0;
					sw_stable <= 0;
					sw_stable_prev <= 0;
				end 
			else 
				begin
					if(sw_capture == sw_stable) 
						begin
							db_count <= 0;
						end 
					else 
						begin
							db_count <= db_count + 1;
							if(db_count == 20'd999999) 
								begin
									sw_stable <= sw_capture;
									db_count <= 0;
								end
						end
					sw_stable_prev <= sw_stable;
				end
		end
	assign capture_pulse = (sw_stable && !sw_stable_prev);

	always @(posedge clk or posedge reset) 
		begin
			if (reset) 
				begin
					h0<=0; m0<=0; s0<=0; t0<=0;
					h1<=0; m1<=0; s1<=0; t1<=0;
					h2<=0; m2<=0; s2<=0; t2<=0;
					h3<=0; m3<=0; s3<=0; t3<=0;
					h4<=0; m4<=0; s4<=0; t4<=0;
				end
			else if (capture_pulse) 
				begin
					h0<=in_hours; m0<=in_minutes; s0<=in_seconds; t0<=in_tenths; 
            
            
					h1<=h0;       m1<=m0;         s1<=s0;         t1<=t0; 
            
					h2<=h1;       m2<=m1;         s2<=s1;         t2<=t1; 
            
					h3<=h2;       m3<=m2;         s3<=s2;         t3<=t2; 
            
					h4<=h3;       m4<=m3;         s4<=s3;         t4<=t3;
				end
		end
endmodule


module display_stored(
    input  wire clk,
    input  wire sw0, sw1, sw2, sw3, sw4,

    input  wire [3:0]  hrs,
    input  wire [5:0]  mins,
    input  wire [5:0]  secs,
    input  wire [3:0]  ms,
    input  wire [3:0]  hrs_prev1, 
    input  wire [3:0]  hrs_prev2, 
    input  wire [3:0]  hrs_prev3, 
    input  wire [3:0]  hrs_prev4, 
    input  wire [3:0]  hrs_prev5,
    
    input  wire [5:0]  mins_prev1, 
    input  wire [5:0]  mins_prev2, 
    input  wire [5:0]  mins_prev3, 
    input  wire [5:0]  mins_prev4, 
    input  wire [5:0]  mins_prev5,
    
    input  wire [5:0]  secs_prev1, 
    input  wire [5:0]  secs_prev2, 
    input  wire [5:0]  secs_prev3, 
    input  wire [5:0]  secs_prev4, 
    input  wire [5:0]  secs_prev5,
    
    input  wire [3:0]  ms_prev1, 
    input  wire [3:0]  ms_prev2,   
    input  wire [3:0]  ms_prev3,   
    input  wire [3:0]  ms_prev4,   
    input  wire [3:0]  ms_prev5,

    output wire [6:0]  hrs_dis,
    output wire [6:0]  mins_tens_dis,
    output wire [6:0]  mins_ones_dis,
    output wire [6:0]  secs_tens_dis,
    output wire [6:0]  secs_ones_dis,
    output wire [6:0]  ms_dis
);
    
    reg [3:0]  hrs_out;
    reg [5:0]  mins_out;
    reg [5:0]  secs_out;
    reg [3:0]  ms_out;
    
    always @(*) begin
        if (sw0) begin
            hrs_out  = hrs_prev1;
            mins_out = mins_prev1;
            secs_out = secs_prev1;
            ms_out   = ms_prev1;
        end
        else if (sw1) begin
            hrs_out  = hrs_prev2;
            mins_out = mins_prev2;
            secs_out = secs_prev2;
            ms_out   = ms_prev2;
        end
        else if (sw2) begin
            hrs_out  = hrs_prev3;
            mins_out = mins_prev3;
            secs_out = secs_prev3;
            ms_out   = ms_prev3;
        end
        else if (sw3) begin
            hrs_out  = hrs_prev4;
            mins_out = mins_prev4;
            secs_out = secs_prev4;
            ms_out   = ms_prev4;
        end
        else if (sw4) begin
            hrs_out  = hrs_prev5;
            mins_out = mins_prev5;
            secs_out = secs_prev5;
            ms_out   = ms_prev5;
        end
        else begin
            hrs_out  = hrs;
            mins_out = mins;
            secs_out = secs;
            ms_out   = ms;
        end
    end

    wire [3:0] mins_tens = mins_out / 10;
    wire [3:0] mins_ones = mins_out % 10;
    wire [3:0] secs_tens = secs_out / 10;
    wire [3:0] secs_ones = secs_out % 10;
     
    bcd_display H  (hrs_out,  hrs_dis);
    bcd_display MT (mins_tens, mins_tens_dis);
    bcd_display MO (mins_ones, mins_ones_dis);
    bcd_display ST (secs_tens, secs_tens_dis);
    bcd_display SO (secs_ones, secs_ones_dis);
    bcd_display MS (ms_out, ms_dis);
    
endmodule


module bcd_display(
    input [3:0] bcd,
    output reg [6:0] seg
);
    always @(*) begin
        case(bcd)
            0: seg = 7'b1000000;
            1: seg = 7'b1111001;
            2: seg = 7'b0100100;
            3: seg = 7'b0110000;
            4: seg = 7'b0011001;
            5: seg = 7'b0010010;
            6: seg = 7'b0000010;
            7: seg = 7'b1111000;
            8: seg = 7'b0000000;
            9: seg = 7'b0010000;
            default: seg = 7'b1111111;
        endcase
    end
endmodule
