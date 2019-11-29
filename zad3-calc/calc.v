`default_nettype none

module calc(
    input wire [3:0] btn_raw,
    input wire [7:0] sw_raw,
    input wire clk, // mclk
    output wire [3:0] an,
    output wire [6:0] seg,
    output wire [7:0] led
    );

localparam STATE_IDLE = 0;
localparam STATE_CALC = 1;
localparam STATE_MEM_IO = 2; // todo (disable stack op)

wire [3:0] btn;
wire [7:0] sw;
sync_input #(.BITS(4)) btn_sync(.clk(clk), .in(btn_raw), .out(btn));
sync_input #(.BITS(8)) sw_sync(.clk(clk), .in(sw_raw), .out(sw));

reg err_flag;
reg [1:0] state;

reg st_en;
reg [1:0] st_write_elems_cnt;
reg [31:0] st_write_elems [0:1];
reg [1:0] st_top_mov;
wire [9:0] st_elems_cnt;
wire [31:0] st_top [0:1];
wire st_ready;

stack stack_mem(
    .clk(clk),
    .en(st_en),
    .write_elems_cnt(st_write_elems_cnt),
    .write_elem0(st_write_elems[0]),
    .write_elem1(st_write_elems[1]),
    .top_mov(st_top_mov),
    .elems_cnt(st_elems_cnt),
    .top0(st_top[0]),
    .top1(st_top[1]),
    .ready(st_ready)
    );

display_7seg disp(
    .clk(clk),
    .en(st_elems_cnt != 0),
    .num(st_top[0][(btn[0] ? 31 : 15)-:16]),
    .an(an),
    .seg(seg)
    );

initial begin
    err_flag <= 0;
    state <= STATE_IDLE;
end

assign led = {err_flag, st_elems_cnt[6:0]};

// todo the whole logic...
always @(posedge clk) begin
    case(state)
    STATE_IDLE: begin
    end
    STATE_CALC: begin
    end
    STATE_MEM_IO: begin
    end
    endcase
end

endmodule


//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
module stack(
    input wire clk,
    input wire en,
    input wire [1:0] write_elems_cnt, // 0, 1 or 2 (counting from top)
    input wire [31:0] write_elem0,
    input wire [31:0] write_elem1,
    input wire [1:0] top_mov,
    output reg [9:0] elems_cnt,
    output reg [31:0] top0,
    output reg [31:0] top1,
    output reg ready
    );

localparam ST_NO_MOV = 0;
localparam ST_MOV_UP = 1;
localparam ST_MOV_DN = 2;

reg [31:0] mem [0:511];

reg [31:0] extra_elem;
reg extra_elem_present;

initial begin
    elems_cnt <= 0;
    ready <= 1;
end

always @(posedge clk) begin
    if (extra_elem_present) begin // two writes only if swapping two top elements
        // todo: probably refactor it
        mem[elems_cnt - 1] <= extra_elem;
        top1 <= extra_elem;
        ready <= 1;
    end else if (en) begin
        // todo
    end

    // mem_io_write_idx <= mem_io_write_idx - 1;
    // stack[elems_cnt - 1 - mem_io_write_idx] <= mem_io_write_buf[mem_io_write_idx];
    // if (mem_io_write_idx) begin
    //     top1_num <= mem_io_write_buf[1]; // only for swapping two top elems
    // end else begin
    //     state <= STATE_IDLE;
    //     case (mem_io_mov)
    //     MEM_IO_NO_MOV: begin
    //         top0_num <= mem_io_write_buf[0];
    //     end
    //     MEM_IO_MOV_UP: begin
    //         top0_num <= mem_io_write_buf[0];
    //         top1_num <= top0_num;
    //         top2_num <= top1_num;
    //     end
    //     MEM_IO_MOV_DN: begin
    //         top0_num <= top1_num;
    //         top1_num <= top2_num;
    //         top2_num <= stack[elems_cnt - 3];
    //     end
    //     endcase
    // end
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
module display_7seg(
    input wire clk,
    input wire en,
    input wire [15:0] num,
    output reg [3:0] an,
    output reg [6:0] seg
    );

localparam CYCLE = 1024 * 16;
localparam MARGIN = 1024;

reg buf_en;
reg [15:0] buf_num;
reg [13:0] ctr;
reg [2:0] digit_idx;

initial begin
    buf_en <= 0;
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
            buf_en <= en;
            buf_num <= num;
        end
    end
end

// segment
always @(posedge clk) begin
    if (buf_en == 0) begin
        seg <= 7'h3f;  // '-'
    end else case (buf_num[{digit_idx, 2'b11}-:4])
    0:  seg <= 7'h40;
    1:  seg <= 7'h79;
    2:  seg <= 7'h24;
    3:  seg <= 7'h30;
    4:  seg <= 7'h19;
    5:  seg <= 7'h12;
    6:  seg <= 7'h02;
    7:  seg <= 7'h78;
    8:  seg <= 7'h00;
    9:  seg <= 7'h10;
    10: seg <= 7'h08;
    11: seg <= 7'h03;
    12: seg <= 7'h27;
    13: seg <= 7'h21;
    14: seg <= 7'h06;
    15: seg <= 7'h0e;
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

