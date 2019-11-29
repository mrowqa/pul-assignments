`default_nettype none

module stopwatch(
    input wire [3:0] btn_raw,
    input wire [7:0] sw_raw,
    input wire mclk,
    input wire uclk,
    output wire [3:0] an,
    output wire [6:0] seg,
    output reg [2:0] led
    );

localparam STATE_STOPPED = 0;
localparam STATE_UP = 1;
localparam STATE_DOWN = 2;

localparam CMD_DOWN =   4'b0001;
localparam CMD_UP =     4'b0010;
localparam CMD_STOP =   4'b0100;
localparam CMD_RESET =  4'b1000;

// same as in bcd_ops
localparam MIN_BCD_CTR = 0;
localparam MAX_BCD_CTR = 16'h9999;

wire clk;
wire [3:0] btn;
wire [4:0] sw;
wire which_clk;
sync_input #(.BITS(4)) btn_sync(.clk(clk), .in(btn_raw), .out(btn));
sync_input #(.BITS(5)) sw_sync(.clk(clk), .in(sw_raw[4:0]), .out(sw));
sync_input sw_clk_sync(.clk(clk), .in(sw_raw[7]), .out(which_clk));
BUFGMUX clk_buf(.I0(mclk), .I1(uclk), .S(which_clk), .O(clk));

reg [15:0] bcd_ctr;
wire [15:0] bcd_ctr_add1;
wire [15:0] bcd_ctr_sub1;
wire bcd_ctr_add_oflw;
wire bcd_ctr_sub_oflw;
bcd_ops bcd_ops_(
    .ctr(bcd_ctr),
    .ctr_add1(bcd_ctr_add1),
    .ctr_sub1(bcd_ctr_sub1),
    .ctr_add_oflw(bcd_ctr_add_oflw),
    .ctr_sub_oflw(bcd_ctr_sub_oflw));
display_7seg disp(.clk(clk), .bcd_num(bcd_ctr), .an(an), .seg(seg));

reg [1:0] state;
reg hit_extremum;
reg [32:0] wait_; // 2**0b11111

initial begin
    state <= STATE_STOPPED;
    bcd_ctr <= 0;
    wait_ <= 0;
    hit_extremum <= 0;
end

always @* begin
    case(state)
    STATE_STOPPED: begin
        led <= {hit_extremum, 2'b00};
    end
    STATE_UP: begin
        led <= 3'b010;
    end
    STATE_DOWN: begin
        led <= 3'b001;
    end
    default: begin
        led <= 3'bxxx;
    end
    endcase
end

always @(posedge clk) begin
    if (btn == CMD_DOWN && state != STATE_DOWN) begin
        if (bcd_ctr == MIN_BCD_CTR) begin
            state <= STATE_STOPPED;
            wait_ <= 0;
            hit_extremum <= 0; // well, as assignment reads
        end else begin
            state <= STATE_DOWN;
            wait_ <= 1 << sw[4:0];
            hit_extremum <= 0;
        end
    end else if (btn == CMD_UP && state != STATE_UP) begin
        if (bcd_ctr == MAX_BCD_CTR) begin
            state <= STATE_STOPPED;
            wait_ <= 0;
            hit_extremum <= 0; // well, as assignment reads
        end else begin
            state <= STATE_UP;
            wait_ <= 1 << sw[4:0];
            hit_extremum <= 0;
        end
    end else if (btn == CMD_STOP) begin
        state <= STATE_STOPPED;
        wait_ <= 0;
        hit_extremum <= 0;
    end else if (btn == CMD_RESET) begin
        state <= STATE_STOPPED;
        bcd_ctr <= 0;
        wait_ <= 0;
        hit_extremum <= 0;
    end else begin // clk tick
        if (wait_ != 0) begin
            wait_ <= wait_ - 1;
        end else case(state) // ctr tick
            STATE_STOPPED: begin
            end
            STATE_UP: begin
                bcd_ctr <= bcd_ctr_add1;
                if (bcd_ctr_add_oflw) begin
                    state <= STATE_STOPPED;
                    hit_extremum <= 1;
                end else begin
                    wait_ <= 1 << sw[4:0];
                end
            end
            STATE_DOWN: begin
                bcd_ctr <= bcd_ctr_sub1;
                if (bcd_ctr_sub_oflw) begin
                    state <= STATE_STOPPED;
                    hit_extremum <= 1;
                end else begin
                    wait_ <= 1 << sw[4:0];
                end
            end
        endcase
    end
end

endmodule

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
module sync_input(clk, in, out);

parameter BITS = 1;
input wire clk;
input wire [BITS-1:0] in;
output reg [BITS-1:0] out;

reg [BITS-1:0] tmp;
always @(posedge clk) begin
    tmp <= in;
    out <= tmp;
end

endmodule


//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
module bcd_ops(
    input wire [15:0] ctr,
    output wire [15:0] ctr_add1,
    output wire [15:0] ctr_sub1,
    output wire ctr_add_oflw,
    output wire ctr_sub_oflw
    );

localparam MIN_BCD_CTR = 0;
localparam MAX_BCD_CTR = 16'h9999;

assign ctr_add1[3:0]   = ctr[3:0]  == 4'h9    ? 0 : ctr[3:0] + 1;
assign ctr_add1[7:4]   = ctr[3:0]  == 4'h9    ? (ctr[7:4]   == 4'h9 ? 0 : ctr[7:4] + 1)   : ctr[7:4];
assign ctr_add1[11:8]  = ctr[7:0]  == 8'h99   ? (ctr[11:8]  == 4'h9 ? 0 : ctr[11:8] + 1)  : ctr[11:8];
assign ctr_add1[15:12] = ctr[11:0] == 12'h999 ? (ctr[15:12] == 4'h9 ? 0 : ctr[15:12] + 1) : ctr[15:12];

assign ctr_sub1[3:0]   = ctr[3:0]  == 4'h0    ? 9 : ctr[3:0] - 1;
assign ctr_sub1[7:4]   = ctr[3:0]  == 4'h0    ? (ctr[7:4]   == 4'h0 ? 9 : ctr[7:4] - 1)   : ctr[7:4];
assign ctr_sub1[11:8]  = ctr[7:0]  == 8'h00   ? (ctr[11:8]  == 4'h0 ? 9 : ctr[11:8] - 1)  : ctr[11:8];
assign ctr_sub1[15:12] = ctr[11:0] == 12'h000 ? (ctr[15:12] == 4'h0 ? 9 : ctr[15:12] - 1) : ctr[15:12];

// note: be wary if changing this +1/-1: it still should be valid bcd number!
assign ctr_add_oflw = ctr == MAX_BCD_CTR - 1;
assign ctr_sub_oflw = ctr == MIN_BCD_CTR + 1;

endmodule

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
module display_7seg(
    input wire clk,
    input wire [15:0] bcd_num,
    output reg [3:0] an,
    output reg [6:0] seg
    );

localparam CYCLE = 1024 * 16;
localparam MARGIN = 1024;

reg [15:0] buf_num;
reg [13:0] ctr;
reg [2:0] digit_idx;

initial begin
    buf_num <= 0;
    ctr <= 0;
    digit_idx <= 0;
end

// counter
always @(posedge clk) begin
    ctr <= ctr + 1;
    if (ctr == CYCLE - 1) begin
        digit_idx <= digit_idx + 1;
        if (digit_idx == 3) begin
            buf_num <= bcd_num;
        end
    end
end

// segment
always @(posedge clk) begin
    case (buf_num[{digit_idx, 2'b11}-:4])
    0: seg <= 7'h40;
    1: seg <= 7'h79;
    2: seg <= 7'h24;
    3: seg <= 7'h30;
    4: seg <= 7'h19;
    5: seg <= 7'h12;
    6: seg <= 7'h02;
    7: seg <= 7'h78;
    8: seg <= 7'h00;
    9: seg <= 7'h10;
    endcase
end

// anode
always @(posedge clk) begin
    if (ctr < MARGIN || ctr >= CYCLE - MARGIN) begin
        an <= 4'b1111;
    end else begin
        case (digit_idx)
        0: an <= 4'b1110;
        1: an <= 4'b1101;
        2: an <= 4'b1011;
        3: an <= 4'b0111;
        endcase
    end
end

endmodule

