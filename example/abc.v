module abc(
    input [7:0] sw,
    output [7:0] led
    );

assign led = sw[3:0] * sw[7:4];

endmodule
