`default_nettype none

module gpu(
    input wire uclk,
    // input wire mclk,
    // debug
    // output reg [7:0] led,
    // input wire [3:0] btn0,
    // input wire [7:0] sw,
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

// reg [3:0] btn1;
// reg [3:0] btn;
// 
// always @(posedge uclk) begin
//     btn1 <= btn0;
//     btn <= btn1;
// end

localparam WIDTH = 320;
localparam HEIGHT = 200;

`ifndef SIM
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
`endif

// main logic, fwd decl
localparam STATE_IDLE = 0;
localparam STATE_BLIT = 1;
localparam STATE_FILL = 2;
localparam STATE_FILL_INC_POS = 3;
localparam STATE_BLIT_INC_POS = 4;
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
    // led <= 0;
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


//////////////////////////////////////////////////////////////////////////////
////////////////////       VGA           /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
`ifndef SIM
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
`endif


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
reg [19:3] dst_x; // iterators
reg [19:0] dst_y;
reg [19:3] src_x;
reg [19:0] src_y;
reg [7:0] read_waits;
reg blit_stage;
reg [7:0] blit_buffer [0:WIDTH/8-1]; // line buffer for blit

localparam BLIT_STAGE_READ = 0;
localparam BLIT_STAGE_WRITE = 1;
localparam BLIT_DIR_UP = 0;
localparam BLIT_DIR_DN = 1;

initial begin
    state <= STATE_IDLE;
    start_blit <= 0;
    start_fill <= 0;
    fill_color <= 0;
    read_waits <= 0;
end

wire blit_dir = reg_y1 <= reg_y2 ? BLIT_DIR_DN : BLIT_DIR_UP;

wire [19:3] dst_addr = (dst_y * WIDTH + {dst_x, 3'b000}) >> 3;
wire [19:3] src_addr = (src_y * WIDTH + {src_x, 3'b000}) >> 3;
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
wire [23:0] blit_bits = {
    src_x == WIDTH/8-1 ? 8'h00 : blit_buffer[src_x + 1],
    blit_buffer[src_x],
    src_x == 0 ? 8'h00 : blit_buffer[src_x - 1]
    };
wire [7:0] blit_bits_idx = 8 - (reg_x1 & 3'b111) + (reg_x2 & 3'b111); // +8=base
wire [7:0] dst_blit_bits = blit_bits[blit_bits_idx + 7 -: 8];

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
    `ifndef SIM
    start_fill <= 0;
    `endif

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
            if (reg_x1 + op_width <= WIDTH && reg_y1 + op_height <= HEIGHT &&
                reg_x2 + op_width <= WIDTH && reg_y2 + op_height <= HEIGHT)
            begin
                state <= STATE_BLIT;
                blit_stage <= BLIT_STAGE_READ;
                dst_x <= reg_x1 >> 3;
                dst_y <= reg_y1 <= reg_y2 ? reg_y1 : reg_y1 + op_height - 1;
                src_x <= reg_x2 >> 3;
                src_y <= reg_y1 <= reg_y2 ? reg_y2 : reg_y2 + op_height - 1;
            end
        end else if (start_fill) begin
            if (reg_x1 + op_width <= WIDTH && reg_y1 + op_height <= HEIGHT) begin
                state <= STATE_FILL;
                dst_x <= reg_x1 >> 3;
                dst_y <= reg_y1;
            end
        end
    end
    STATE_FILL: begin
        if (dst_y >= reg_y1 + op_height) begin // finished
            state <= STATE_IDLE;
        end else begin
            fb_addr <= dst_addr;
            if (dst_covered_bits != 8'hff && read_waits < 2) begin
                read_waits <= read_waits + 1; // =0 set addr, =1 reads, =2 data ready
            end else begin
                fb_write <= 1;
                fb_write_data <=
                    ({8{fill_color}} & dst_covered_bits) |
                    (fb_read_data & (~dst_covered_bits));
                state <= STATE_FILL_INC_POS;
            end
        end
    end
    STATE_FILL_INC_POS: begin
        // for some reason it can't happen in STATE_FILL...
        // it works in simulation, but not on real hardware
        // (the memory behaves in a weird way)
        fb_addr <= dst_addr; // for some reason, memory uses address from this tick, not previous
        if ({dst_x + 17'h1, 3'b000} >= reg_x1 + op_width) begin
            dst_x <= reg_x1 >> 3;
            dst_y <= dst_y + 1;
        end else begin
            dst_x <= dst_x + 1;
        end
        state <= STATE_FILL;
    end
    STATE_BLIT: begin
        // idea: for each line: read all needed bytes from current line, then write pixels in dst line
        // this way we don't have to care about horizontal direction, and it takes same
        // number of cycles; it requires line buffer, though
        case (blit_stage)
        BLIT_STAGE_READ: begin
            if (blit_dir == BLIT_DIR_DN ?
                dst_y >= reg_y1 + op_height :
                dst_y + 1 == reg_y1) // +1 cause dst_y could underflow
            begin // finished
                state <= STATE_IDLE;
            end else begin
                fb_addr <= src_addr;
                if (read_waits < 2) begin
                    read_waits <= read_waits + 1;
                end else begin
                    blit_buffer[src_x] <= fb_read_data;

                    // inc pos
                    if ({src_x + 17'h1, 3'b000} >= reg_x2 + op_width) begin
                        src_x <= reg_x2 >> 3;
                        blit_stage <= BLIT_STAGE_WRITE;
                    end else begin
                        src_x <= src_x + 1;
                    end
                end
            end
        end
        BLIT_STAGE_WRITE: begin
            fb_addr <= dst_addr;
            if (dst_covered_bits != 8'hff && read_waits < 2) begin
                read_waits <= read_waits + 1;
            end else begin
                fb_write <= 1;
                fb_write_data <=
                    (dst_blit_bits & dst_covered_bits) |
                    (fb_read_data & (~dst_covered_bits));
                state <= STATE_BLIT_INC_POS;
            end
        end
        default: begin end
        endcase
    end
    STATE_BLIT_INC_POS: begin
        fb_addr <= dst_addr;
        if ({dst_x + 17'h1, 3'b000} >= reg_x1 + op_width) begin
            dst_x <= reg_x1 >> 3;
            dst_y <= blit_dir == BLIT_DIR_DN ? dst_y + 1 : dst_y - 1;
            src_x <= reg_x2 >> 3;
            src_y <= blit_dir == BLIT_DIR_DN ? src_y + 1 : src_y - 1;
            blit_stage <= BLIT_STAGE_READ;
        end else begin
            dst_x <= dst_x + 1;
            src_x <= src_x + 1;
        end
        state <= STATE_BLIT;
    end
    default: begin end
    endcase
end

endmodule

