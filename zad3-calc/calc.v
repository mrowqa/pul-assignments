`default_nettype none

module calc(
    input wire [3:0] btn_raw,
    input wire [7:0] sw_raw,
    input wire clk, // mclk
    output wire [3:0] an,
    output wire [6:0] seg,
    output wire [7:0] led
    );

localparam BTN_PUSH   = 4'b0010;
localparam BTN_EXTEND = 4'b0100;
localparam BTN_EXEC   = 4'b1000;
localparam BTN_RESET  = 4'b1001;
localparam CMD_ADD = 3'b000;
localparam CMD_SUB = 3'b001;
localparam CMD_MUL = 3'b010;
localparam CMD_DIV = 3'b011;
localparam CMD_MOD = 3'b100;
localparam CMD_POP = 3'b101;
localparam CMD_DUP = 3'b110;
localparam CMD_SWP = 3'b111;

localparam MAX_ELEM_CNT = 512;

localparam STATE_IDLE = 0;
localparam STATE_CALC = 1;
localparam STATE_MEM_WAIT = 2;
localparam STATE_MEM_WAIT2 = 3;
localparam STATE_WAIT_NO_INPUT = 4;

localparam ST_NO_MOV = 0;
localparam ST_MOV_UP = 1;
localparam ST_MOV_DN = 2;

wire [3:0] btn;
wire [7:0] sw;
sync_input #(.BITS(4)) btn_sync(.clk(clk), .in(btn_raw), .out(btn));
sync_input #(.BITS(8)) sw_sync(.clk(clk), .in(sw_raw), .out(sw));

reg err_flag;
reg [2:0] state;

reg st_en;
reg st_reset;
reg [1:0] st_write_elems_cnt;
reg [31:0] st_write_elems [0:1];
reg [1:0] st_top_mov;
wire [9:0] st_elems_cnt;
wire [31:0] st_top [0:1];
wire st_ready;

stack stack_mem(
    .clk(clk),
    .en(st_en),
    .reset(st_reset),
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
    st_en <= 0;
    st_reset <= 0;
    case(state)
    STATE_IDLE: begin
        if (btn != 0) begin
            state <= STATE_WAIT_NO_INPUT; // might get overwritten
        end
        case(btn)
        BTN_PUSH: begin
            if (st_elems_cnt == MAX_ELEM_CNT) begin
                err_flag <= 1;
            end else begin
                st_en <= 1;
                st_write_elems_cnt <= 1;
                st_write_elems[0] <= {24'h0, sw[7:0]};
                st_top_mov <= ST_MOV_UP;
                state <= STATE_MEM_WAIT;
            end
        end
        BTN_EXTEND: begin
            st_en <= 1;
            st_write_elems_cnt <= 1;
            st_write_elems[0] <= {st_top[0][23:0], sw[7:0]};
            st_top_mov <= ST_NO_MOV;
            state <= STATE_MEM_WAIT;
        end
        BTN_EXEC: begin
            // todo
            case(sw[2:0])
            CMD_ADD: begin
            end
            CMD_SUB: begin
            end
            CMD_MUL: begin
            end
            CMD_DIV: begin
            end
            CMD_MOD: begin
            end
            CMD_POP: begin
            end
            CMD_DUP: begin
            end
            CMD_SWP: begin
            end
            endcase
        end
        BTN_RESET: begin
            st_reset <= 1;
            err_flag <= 0;
            state <= STATE_MEM_WAIT;
        end
        endcase
    end
    STATE_CALC: begin
        // doing calc? (todo)
    end
    STATE_MEM_WAIT: begin
        // memory works now and sets st_ready in next tick
        state <= STATE_MEM_WAIT2;
    end
    STATE_MEM_WAIT2: begin
        if (st_ready) begin
            state <= STATE_WAIT_NO_INPUT;
        end
    end
    STATE_WAIT_NO_INPUT: begin
        if (btn == 0 || btn == BTN_RESET) begin
            state <= STATE_IDLE;
        end
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
    input wire reset,
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
reg [9:0] tmp_write_idx;
reg [31:0] tmp_write_elem;
reg tmp_do_write;

initial begin
    elems_cnt <= 0;
    ready <= 1;
end

always @(posedge clk) begin
    ready <= 1; // might be changed
    if (reset) begin
        elems_cnt <= 0;
    end else begin
        tmp_do_write = 0;
        if (!ready) begin // two writes only if swapping two top elements
            // mem[elems_cnt - 2] <= top1;
            tmp_do_write = 1;
            tmp_write_idx = elems_cnt - 2;
            tmp_write_elem = top1;
        end else if (en) begin
            case(top_mov)
            ST_NO_MOV: begin
                if (write_elems_cnt >= 1) begin // should be always
                    // mem[elems_cnt - 1] <= write_elem0;
                    tmp_do_write = 1;
                    tmp_write_idx = elems_cnt - 1;
                    tmp_write_elem = write_elem0;
                    top0 <= write_elem0;
                end
                if (write_elems_cnt == 2) begin
                    ready <= 0;
                    top1 <= write_elem1;
                end
            end
            ST_MOV_UP: begin
                // always writing exactly one element
                elems_cnt <= elems_cnt + 1;
                // mem[elems_cnt] <= write_elem0;
                tmp_do_write = 1;
                tmp_write_idx = elems_cnt;
                tmp_write_elem = write_elem0;
                top0 <= write_elem0;
                top1 <= top0;
            end
            ST_MOV_DN: begin
                elems_cnt <= elems_cnt - 1;
                if (write_elems_cnt > 0) begin // cnt == 1
                    // mem[elems_cnt - 2] <= write_elem0;
                    tmp_do_write = 1;
                    tmp_write_idx = elems_cnt - 2;
                    tmp_write_elem = write_elem0;
                    top0 <= write_elem0;
                end else begin
                    top0 <= top1;
                end
                top1 <= mem[elems_cnt - 3];
            end
            endcase
        end

        if (tmp_do_write) begin
            mem[tmp_write_idx] <= tmp_write_elem;
        end
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

