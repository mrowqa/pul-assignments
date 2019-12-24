`default_nettype none

module gpu(
    input wire uclk,
    // input wire mclk,
    // debug
    output reg [7:0] led,
    //input wire [0:0] btn,
    // VGA
    output reg hsync,
    output reg vsync,
    output reg [7:0] rgb,
    // EPP
    inout wire [7:0] EppDB,
    input wire EppAstb,
    input wire EppDstb,
    input wire EppWR,
    output reg EppWait
    );

localparam WIDTH = 320;
localparam HEIGHT = 200;

wire vga_clk;
wire clk_fb;

DCM_SP #(
    .CLKFX_DIVIDE(32),
    .CLKFX_MULTIPLY(25)
) dcm (
    .CLKFX(vga_clk), // pixel clock: 25 MHz
    .CLKIN(uclk),
    .CLK0(clk_fb),
    .CLKFB(clk_fb),
    .RST(0)
);

// main logic, fwd decl
localparam STATE_IDLE = 0;
localparam STATE_BLIT = 1;
localparam STATE_FILL = 2;
reg [7:0] state;
reg start_blit;
reg start_fill;
reg fill_color;
// ---------------------------


// frame buffer stuff
reg [7:0] frame_buffer [0:7999];
integer i;
initial begin
    for (i=0; i<8000; i=i+1) begin
        frame_buffer[i] <= i;
    end
    led <= 0;
end

reg fb_write;
reg [7:0] fb_write_data;
reg [19:3] fb_addr;
reg [7:0] fb_read_data;

initial begin
    fb_write <= 0;
    fb_write_data <= 0;
    fb_addr <= 0;
    fb_read_data <= 0;
end

always @(posedge uclk) begin
    if (fb_write) begin
        frame_buffer[fb_addr] <= fb_write_data;
    end else begin
        fb_read_data <= frame_buffer[fb_addr];
    end
end
// todo analyze latencies of reads...


//////////////////////////////////////////////////////////////////////////////
////////////////////       VGA           /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////

// http://tinyvga.com/vga-timing/640x400@70Hz
localparam H_ACTIVE = 640;
localparam H_FRONT_PORCH = H_ACTIVE + 16;
localparam H_SYNC_PULSE = H_FRONT_PORCH + 96;
localparam H_BACK_PORCH = H_SYNC_PULSE + 48;
localparam HS_ACTIVE = 1;
localparam V_ACTIVE = 400;
localparam V_FRONT_PORCH = V_ACTIVE + 12;
localparam V_SYNC_PULSE = V_FRONT_PORCH + 2;
localparam V_BACK_PORCH = V_SYNC_PULSE + 35;
localparam VS_ACTIVE = 0;

reg [9:0] pos_x;
reg [9:0] pos_y;
reg [19:0] pos_buf;

reg [9:0] next_pos_x;
reg [9:0] next_pos_y;
reg [19:0] next_pos_buf;
reg next_hsync;
reg next_vsync;
reg next_color_out;

initial begin
    pos_x <= 0;
    pos_y <= 0;
    pos_buf <= 0;
end

always @* begin
    // pos
    if (pos_x == H_BACK_PORCH - 1) begin
        next_pos_x = 0;
        next_pos_y = pos_y == V_BACK_PORCH - 1 ? 0 : pos_y + 1;
    end else begin
        next_pos_x = pos_x + 1;
        next_pos_y = pos_y;
    end
    next_pos_buf = (next_pos_y>>1) * WIDTH + (next_pos_x>>1);

    // outs
    next_hsync = H_FRONT_PORCH <= pos_x && pos_x < H_SYNC_PULSE ? HS_ACTIVE : ~HS_ACTIVE; // kinda xor
    next_vsync = V_FRONT_PORCH <= pos_y && pos_y < V_SYNC_PULSE ? VS_ACTIVE : ~VS_ACTIVE;
end

always @(posedge vga_clk) begin
    // pos
    pos_x <= next_pos_x;
    pos_y <= next_pos_y;
    pos_buf <= next_pos_buf;

    // out
    // note: there's a bug in ISE: you can't use @* with arrays, so the next_color_out is here :/
    //       there's unhandy workaround:
    //           You must have all the elements of the array in the two-dimensional array
    //           that is read in the sensitivity list.
    next_color_out = pos_x < H_ACTIVE && pos_y < V_ACTIVE ?
        (frame_buffer[pos_buf >> 3] >> (pos_buf & 3'b111)) : 0;
    rgb <= {8{next_color_out}};
    hsync <= next_hsync;
    vsync <= next_vsync;
end


//////////////////////////////////////////////////////////////////////////////
////////////////////       EPP           /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////

localparam EPP_REG_X1_L = 0;
localparam EPP_REG_X1_H = 1;
localparam EPP_REG_Y1_L = 2;
localparam EPP_REG_Y1_H = 3;
localparam EPP_REG_X2_L = 4;
localparam EPP_REG_X2_H = 5;
localparam EPP_REG_Y2_L = 6;
localparam EPP_REG_Y2_H = 7;
localparam EPP_REG_OP_WDT_L = 8;
localparam EPP_REG_OP_WDT_H = 9;
localparam EPP_REG_OP_HGT_L = 10;
localparam EPP_REG_OP_HGT_H = 11;
localparam EPP_REG_RUN_BLIT = 12;
localparam EPP_REG_RUN_FILL = 13;
localparam EPP_REG_FRM_BUF = 14;
localparam EPP_REG_STATUS = 15;

localparam EPP_WRITE = 0; // PC writes to FPGA
localparam EPP_READ = 1;

localparam EPP_ADDR_STB = 0;
localparam EPP_DATA_STB = 1;

localparam EPP_STATE_IDLE = 0;
localparam EPP_STATE_WAIT_FOR_PC = 1;

reg [7:0] epp_regs [0:11];
reg [2:0] epp_state;
reg [3:0] epp_addr;

reg [7:0] epp_data_buf;
reg epp_stb_buf;
reg epp_wr_buf;

integer j;
initial begin
    for (j=0; j<12; j=j+1) begin
        epp_regs[j] <= 8'h00;
    end
    epp_state <= EPP_STATE_IDLE;
    epp_addr <= 4'h0;
end

wire [15:0] reg_x1 = {epp_regs[EPP_REG_X1_H], epp_regs[EPP_REG_X1_L]};
wire [15:0] reg_y1 = {epp_regs[EPP_REG_Y1_H], epp_regs[EPP_REG_Y1_L]};
wire [15:0] reg_x2 = {epp_regs[EPP_REG_X2_H], epp_regs[EPP_REG_X2_L]};
wire [15:0] reg_y2 = {epp_regs[EPP_REG_Y2_H], epp_regs[EPP_REG_Y2_L]};
wire [15:0] op_width = {epp_regs[EPP_REG_OP_WDT_H], epp_regs[EPP_REG_OP_WDT_L]};
wire [15:0] op_height = {epp_regs[EPP_REG_OP_HGT_H], epp_regs[EPP_REG_OP_HGT_L]};

assign EppDB = epp_state == EPP_STATE_WAIT_FOR_PC && epp_wr_buf == EPP_READ ? epp_data_buf : 8'hzz;

// sync regs
reg [7:0] EppDB1;
reg EppAstb1;
reg EppDstb1;
reg EppWR1;
reg [7:0] EppDB2;
reg EppAstb2;
reg EppDstb2;
reg EppWR2;

// for main logic
reg [19:3] dst_x; // iterator
reg [19:0] dst_y;
reg read_waits;

initial begin
    state <= STATE_IDLE;
    start_blit <= 0;
    start_fill <= 0;
    fill_color <= 0;
    read_waits <= 0;
end

wire [19:3] dst_addr = (dst_y * WIDTH + {dst_x, 3'b000}) >> 3;
wire [7:0] dst_covered_bits = {
    (({dst_x, 3'b111} >= reg_x1) && ({dst_x, 3'b111} < (reg_x1 + op_width))),
    (({dst_x, 3'b110} >= reg_x1) && ({dst_x, 3'b110} < (reg_x1 + op_width))),
    (({dst_x, 3'b101} >= reg_x1) && ({dst_x, 3'b101} < (reg_x1 + op_width))),
    (({dst_x, 3'b100} >= reg_x1) && ({dst_x, 3'b100} < (reg_x1 + op_width))),
    (({dst_x, 3'b011} >= reg_x1) && ({dst_x, 3'b011} < (reg_x1 + op_width))),
    (({dst_x, 3'b010} >= reg_x1) && ({dst_x, 3'b010} < (reg_x1 + op_width))),
    (({dst_x, 3'b001} >= reg_x1) && ({dst_x, 3'b001} < (reg_x1 + op_width))),
    (({dst_x, 3'b000} >= reg_x1) && ({dst_x, 3'b000} < (reg_x1 + op_width)))
    };

always @(posedge uclk) begin
    // sync inputs
    EppDB1 <= EppDB;
    EppDB2 <= EppDB1;
    EppAstb1 <= EppAstb;
    EppAstb2 <= EppAstb1;
    EppDstb1 <= EppDstb;
    EppDstb2 <= EppDstb1;
    EppWR1 <= EppWR;
    EppWR2 <= EppWR1;

    fb_addr <= (reg_y1 * WIDTH + reg_x1) >> 3;
    fb_write <= 0;
    start_blit <= 0;
    start_fill <= 0;

    case (epp_state)
    EPP_STATE_IDLE: begin
        EppWait <= 0;
        if (!EppAstb2) begin
            if (EppWR2 == EPP_WRITE) begin
                epp_addr <= EppDB2;
            end else begin // read
                epp_data_buf <= epp_addr;
            end
            epp_stb_buf <= EPP_ADDR_STB;
            epp_wr_buf <= EppWR;
            epp_state <= EPP_STATE_WAIT_FOR_PC;
        end else if (!EppDstb2) begin
            if (EppWR2 == EPP_WRITE) begin
                case (epp_addr)
                EPP_REG_RUN_BLIT: begin
                    start_blit <= 1;
                end
                EPP_REG_RUN_FILL: begin
                    start_fill <= 1;
                    fill_color <= EppDB2[0];
                end
                EPP_REG_FRM_BUF: begin
                    if (reg_x1[2:0] == 0 && reg_x1 < WIDTH && reg_y1 < HEIGHT && state == STATE_IDLE) begin
                        fb_write <= 1;
                        fb_write_data <= EppDB2;
                        {epp_regs[EPP_REG_X1_H], epp_regs[EPP_REG_X1_L]} <= reg_x1 + 8 >= WIDTH ? 0 : reg_x1 + 8;
                    end
                end
                EPP_REG_STATUS: begin end
                default: begin
                    epp_regs[epp_addr] <= EppDB2;
                end
                endcase
            end else begin // EPP_READ
                case (epp_addr)
                EPP_REG_RUN_BLIT: begin end
                EPP_REG_RUN_FILL: begin end
                EPP_REG_FRM_BUF: begin
                    if (reg_x1[2:0] == 0 && reg_x1 < WIDTH && reg_y1 < HEIGHT && state == STATE_IDLE) begin
                        epp_data_buf <= fb_read_data;
                        {epp_regs[EPP_REG_X1_H], epp_regs[EPP_REG_X1_L]} <= reg_x1 + 8 >= WIDTH ? 0 : reg_x1 + 8;
                    end
                end
                EPP_REG_STATUS: begin
                    epp_data_buf <= state;
                end
                default: begin
                    epp_data_buf <= epp_regs[epp_addr];
                end
                endcase
            end
            epp_stb_buf <= EPP_DATA_STB;
            epp_wr_buf <= EppWR2;
            epp_state <= EPP_STATE_WAIT_FOR_PC;
        end
    end
    EPP_STATE_WAIT_FOR_PC: begin
        EppWait <= 1;
        if (epp_stb_buf == EPP_ADDR_STB && EppAstb2 ||
                epp_stb_buf == EPP_DATA_STB && EppDstb2) begin
            epp_state <= EPP_STATE_IDLE;
        end
    end
    default: begin
    end
    endcase

    ///////////////////////////////////////////////////////
    /////////////////// Main logic ////////////////////////
    ///////////////////////////////////////////////////////
    // single process, so ISE can notice it can use RAM

    read_waits <= 0;

    case (state)
    STATE_IDLE: begin
        if (start_blit) begin
            state <= STATE_BLIT; // todo...
        end else if (start_fill) begin
            if (reg_x1 + op_width < WIDTH && reg_y1 + op_height < HEIGHT) begin
                state <= STATE_FILL;
                dst_x <= reg_x1 >> 3;
                dst_y <= reg_y1;
            end
        end
    end
    STATE_BLIT: begin
        state <= STATE_IDLE; // todo
    end
    STATE_FILL: begin
        if (dst_y >= reg_y1 + op_height) begin // finished
            state <= STATE_IDLE;
        end else begin
            fb_addr <= dst_addr;
            if (dst_covered_bits != 8'hff && !read_waits) begin
                read_waits <= 1;
            end else begin
                fb_write <= 1;
                fb_write_data <= dst_covered_bits; // todo // looks like shift rotate on these masks...
                    //({8{fill_color}} & dst_covered_bits) |
                    //(fb_read_data & (~dst_covered_bits));

                // inc pos
                if ({dst_x + 1, 3'b000} >= reg_x1 + op_width) begin
                    dst_x <= reg_x1 >> 3;
                    dst_y <= dst_y + 1;
                    led <= led + 16;
                end else begin
                    dst_x <= dst_x + 1;
                    led <= led + 1;
                end
            end
        end
    end
    default: begin end
    endcase
end


//////////////////////////////////////////////////////////////////////////////
////////////////////       Main logic    /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////

endmodule

