`timescale 1ns/1ps
// seg_decode -- BCD to active-low seven segment, bit order {g,f,e,d,c,b,a}.
//
// Active low because the HEX displays on Intel DE boards are common anode.
// The case is full (all sixteen input codes covered by 0-9 plus default) so no
// latch is inferred.  blank forces every segment off, which is how an unwritten
// lap slot is shown as nothing rather than as 0:00:00.0.

module seg_decode (
    input  wire [3:0] bcd,
    input  wire       blank,
    output reg  [6:0] seg
);

    localparam [6:0] OFF = 7'b1111111;

    always @(*) begin
        if (blank) begin
            seg = OFF;
        end else begin
            case (bcd)
                4'd0:    seg = 7'b1000000;
                4'd1:    seg = 7'b1111001;
                4'd2:    seg = 7'b0100100;
                4'd3:    seg = 7'b0110000;
                4'd4:    seg = 7'b0011001;
                4'd5:    seg = 7'b0010010;
                4'd6:    seg = 7'b0000010;
                4'd7:    seg = 7'b1111000;
                4'd8:    seg = 7'b0000000;
                4'd9:    seg = 7'b0010000;
                default: seg = OFF;
            endcase
        end
    end

endmodule
