`default_nettype none

module calc(
    input [3:0] btn,
    input [7:0] sw,
    output [7:0] led
    );

// tmp wires
wire [3:0] a = sw[7:4];
wire [3:0] b = sw[3:0];

wire [3:0] sum = a + b;
wire [3:0] diff = a - b;

wire [3:0] min = a < b ? a : b;
wire [3:0] max = a < b ? b : a;

wire [7:0] prod = a * b;

wire [3:0] quot;
wire [3:0] rem;
idiv idiv1(.a(a), .b(b), .quot(quot), .rem(rem));


reg [7:0] tmp_led;
assign led = tmp_led;

always @* begin
    case (btn)
    4'b0000: begin
        tmp_led <= 0;
    end
    4'b0001: begin
        tmp_led <= {sum, diff};
    end
    4'b0010: begin
        tmp_led <= {min, max};
    end
    4'b0100: begin
        tmp_led <= prod;
    end
    4'b1000: begin
        tmp_led <= {quot, rem};
    end
    default: begin
        tmp_led <= 8'hxx;
    end
    endcase
end

endmodule


module idiv(a, b, quot, rem);

parameter BITS = 4;

input wire [BITS-1:0] a;
input wire [BITS-1:0] b;
output wire [BITS-1:0] quot;
output wire [BITS-1:0] rem;

wire [BITS-1:0] tmp_var [0:BITS];
assign tmp_var[0] = a;
assign rem = tmp_var[BITS];

genvar i;
generate
    for (i = 0; i < BITS; i = i + 1) begin: gen_div
        wire [BITS*2-1:0] shifted_b = b << (BITS-i-1);
        wire [BITS*2-1:0] tmp_var_ext = tmp_var[i];
        assign quot[BITS-i-1] = tmp_var_ext >= shifted_b;
        assign tmp_var[i+1] = quot[BITS-i-1] ? tmp_var[i] - shifted_b[BITS-1:0] : tmp_var[i];
    end
endgenerate

endmodule

