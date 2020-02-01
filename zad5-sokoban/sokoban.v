`default_nettype none

module sokoban(
    input wire uclk,
    // input wire mclk,
    // debug
    output reg [7:0] led,
    input wire [3:0] btn0,
    input wire [2:0] sw0,
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

// clocks
wire clk;
wire clk_fb;

DCM_SP #(
    .CLKFX_DIVIDE(32),
    .CLKFX_MULTIPLY(25)
) dcm (
    .CLKFX(clk), // pixel clock: 25 MHz
    .CLKIN(uclk),
    .CLK0(clk_fb),
    .CLKFB(clk_fb),
    .RST(0)
);

// sync inputs
reg [3:0] btn1;
reg [3:0] btn;
reg [2:0] sw1;
reg [2:0] sw;

always @(posedge clk) begin
    btn1 <= btn0;
    btn <= btn1;
    sw1 <= sw0;
    sw <= sw1;
end

// fwd decl
localparam RESOLUTION_WIDTH = 640;
localparam RESOLUTION_HEIGHT = 480;

// ---------------------------

// tiles
localparam TILE_EDGE_LEN = 32;
localparam TILE_SIZE = TILE_EDGE_LEN * TILE_EDGE_LEN;

localparam TILE_WALL = 0;
localparam TILE_BOX = 1;
localparam TILE_BOX_READY = 2;
localparam TILE_TARGET = 3;
localparam TILE_PLAYER = 4;
localparam TILE_EMPTY_OUTSIDE = 5;
localparam TILE_EMPTY_INSIDE = 6;

localparam TILE_EMPTY_OUTSIDE_COLOR = 8'h00;
localparam TILE_EMPTY_INSIDE_COLOR = 8'h24;

// tile data
reg [7:0] tile_data [0:5999];

initial begin
    $readmemh("resources/textures.hex", tile_data);
    led <= 0;
end


// tile map
localparam MAP_WIDTH = RESOLUTION_WIDTH / TILE_EDGE_LEN; // 20
localparam MAP_HEIGHT = RESOLUTION_HEIGHT / TILE_EDGE_LEN; // 15
localparam MAP_SIZE = MAP_WIDTH * MAP_HEIGHT; // 300
localparam MAP_MEM = 2000;
localparam MAPS_CAPACITY = MAP_MEM / MAP_SIZE;
reg [7:0] tile_map [0:MAP_MEM-1]; // fits 6 maps (uses whole byte for values in range [0,6])

integer i;
initial begin
    for (i=0; i<MAP_MEM; i=i+1) begin
        tile_map[i] <= i % 7;
    end
end

reg map_write;
reg [7:0] map_write_data;
reg [13:0] map_addr;
reg [7:0] map_read_data;

initial begin
    map_write <= 0;
    map_write_data <= 0;
    map_addr <= 0;
    map_read_data <= 0;
end

always @(posedge clk) begin
    if (map_write) begin
        tile_map[map_addr] <= map_write_data;
    end else begin
        map_read_data <= tile_map[map_addr];
    end
end

// fwd decl
reg [7:0] number_of_maps;
reg [7:0] current_map;
reg [9:0] read_progress;

reg [7:0] player_x [0:MAPS_CAPACITY-1];
reg [7:0] player_y [0:MAPS_CAPACITY-1];
reg [7:0] remaining_boxes [0:MAPS_CAPACITY-1];
reg [7:0] score [0:MAPS_CAPACITY-1];

initial begin
    number_of_maps <= 1;
    current_map <= 0;
    read_progress <= 0;

    // align player with the pattern
    player_x[0] <= 4;
    player_y[0] <= 0;
    score[0] <= 42;
    remaining_boxes[0] <= 0;
    for (i=1; i<MAPS_CAPACITY; i=i+1) begin
        player_x[i] <= 0;
        player_y[i] <= 0;
        score[i] <= 0;
        remaining_boxes[i] <= 0;
    end
end


//////////////////////////////////////////////////////////////////////////////
////////////////////       VGA           /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
// http://tinyvga.com/vga-timing/640x480@60Hz
localparam H_ACTIVE = 640;
localparam H_FRONT_PORCH = H_ACTIVE + 16;
localparam H_SYNC_PULSE = H_FRONT_PORCH + 96;
localparam H_BACK_PORCH = H_SYNC_PULSE + 48;
localparam HS_ACTIVE = 1;
localparam V_ACTIVE = 480;
localparam V_FRONT_PORCH = V_ACTIVE + 10;
localparam V_SYNC_PULSE = V_FRONT_PORCH + 2;
localparam V_BACK_PORCH = V_SYNC_PULSE + 33;
localparam VS_ACTIVE = 1;

// TODO less bits per reg?
reg [9:0] screen_x;
reg [9:0] screen_y;
reg [9:0] map_x;
reg [9:0] map_y;
reg [9:0] tile_x;
reg [9:0] tile_y;

reg [9:0] tile_x_d1;
reg [9:0] tile_y_d1;
reg [19:0] in_map_idx;
reg [19:0] in_tile_idx_d1;
reg [7:0] tile_pixel_d2;

reg [7:0] current_tile_d1;
reg is_on_map, is_on_map_d1, is_on_map_d2;

reg [9:0] next_screen_x;
reg [9:0] next_screen_y;

reg hsync_d0, hsync_d1, hsync_d2;
reg vsync_d0, vsync_d1, vsync_d2;
reg [7:0] rgb_d2;

initial begin
    screen_x <= 0;
    screen_y <= 0;
end

always @* begin
    // screen
    if (screen_x == H_BACK_PORCH - 1) begin
        next_screen_x = 0;
        next_screen_y = screen_y == V_BACK_PORCH - 1 ? 0 : screen_y + 1;
    end else begin
        next_screen_x = screen_x + 1;
        next_screen_y = screen_y;
    end

    // map & tile
    tile_x = screen_x & 5'h1f;
    tile_y = screen_y & 5'h1f;
    map_x = screen_x >> 5;
    map_y = screen_y >> 5;

    // calc indices for sync mem read
    is_on_map = screen_x < RESOLUTION_WIDTH && screen_y < RESOLUTION_HEIGHT;
    in_map_idx = map_y * MAP_WIDTH + map_x + current_map * MAP_SIZE;
    in_tile_idx_d1 = tile_y_d1 * TILE_EDGE_LEN + tile_x_d1 + current_tile_d1 * TILE_SIZE;

    // outs
    hsync_d0 = H_FRONT_PORCH <= screen_x && screen_x < H_SYNC_PULSE ? HS_ACTIVE : ~HS_ACTIVE; // kinda xor
    vsync_d0 = V_FRONT_PORCH <= screen_y && screen_y < V_SYNC_PULSE ? VS_ACTIVE : ~VS_ACTIVE;
    rgb_d2 = is_on_map_d2 ? tile_pixel_d2 : 0;
end

always @(posedge clk) begin
    // pipeline delays: in suffix _d<value>
    // next_ is like "delay value -= 1"

    // pos (delay baseline; "_d0")
    screen_x <= next_screen_x;
    screen_y <= next_screen_y;

    // helpers - delayers
    is_on_map_d1 <= is_on_map;
    is_on_map_d2 <= is_on_map_d1;
    tile_x_d1 <= tile_x;
    tile_y_d1 <= tile_y;
    hsync_d1 <= hsync_d0;
    hsync_d2 <= hsync_d1;
    vsync_d1 <= vsync_d0;
    vsync_d2 <= vsync_d1;

    // mem
    if (map_x == player_x[current_map] && map_y == player_y[current_map]) begin
        current_tile_d1 <= TILE_PLAYER;
    end else begin
        current_tile_d1 <= tile_map[in_map_idx];
    end
    case (current_tile_d1)
        TILE_EMPTY_OUTSIDE: tile_pixel_d2 <= TILE_EMPTY_OUTSIDE_COLOR;
        TILE_EMPTY_INSIDE: tile_pixel_d2 <= TILE_EMPTY_INSIDE_COLOR;
        default: tile_pixel_d2 <= tile_data[in_tile_idx_d1];
    endcase

    // outs
    rgb <= rgb_d2;
    hsync <= hsync_d2;
    vsync <= vsync_d2;
end

//////////////////////////////////////////////////////////////////////////////
////////////////////       EPP           /////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////

localparam EPP_REG_MAP = 0;
localparam EPP_REG_STATUS = 1;

localparam EPP_WRITE = 0; // PC writes to FPGA
localparam EPP_READ = 1;

localparam EPP_ADDR_STB = 0;
localparam EPP_DATA_STB = 1;

localparam EPP_STATE_IDLE = 0;
localparam EPP_STATE_WAIT_FOR_PC = 1;

reg [2:0] epp_state;
reg [3:0] epp_addr;

reg [7:0] epp_data_buf;
reg epp_stb_buf;
reg epp_wr_buf;

initial begin
    epp_state <= EPP_STATE_IDLE;
    epp_addr <= 4'h0;
end

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

// logic
localparam STATE_IDLE = 0;
localparam STATE_READING_MAPS = 1;

reg [7:0] state;


initial begin
    state <= STATE_IDLE;
end

localparam EPP_MAP_HEADER_SIZE = 3;
// EPP MAP STREAM:
// <# of maps>
// <maps...>
// for each map:
// <player_x>
// <player_y>
// <# of unmatched boxes>
// <blocks...>
// NO VALIDATION so far

always @(posedge clk) begin
    // sync inputs
    EppDB1 <= EppDB;
    EppDB2 <= EppDB1;
    EppAstb1 <= EppAstb;
    EppAstb2 <= EppAstb1;
    EppDstb1 <= EppDstb;
    EppDstb2 <= EppDstb1;
    EppWR1 <= EppWR;
    EppWR2 <= EppWR1;

    map_addr <= 0;
    map_write <= 0;

    led <= score[current_map];

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
                EPP_REG_MAP: begin
                    case (state)
                    STATE_IDLE: begin
                        state <= STATE_READING_MAPS;
                        number_of_maps <= EppDB2;
                        current_map <= 0;
                        read_progress <= 0;
                    end
                    STATE_READING_MAPS: begin
                        // TODO check what if overmapped
                        // led <= 8'b01101001; // TODO
                        led <= led + 1; // TODO
                        read_progress <= read_progress + 1;
                        case (read_progress)
                        0: player_x[current_map] <= EppDB2;
                        1: player_y[current_map] <= EppDB2;
                        2: remaining_boxes[current_map] <= EppDB2;
                        default: begin
                            map_addr <= read_progress - EPP_MAP_HEADER_SIZE + current_map * MAP_SIZE;
                            map_write <= 1;
                            map_write_data <= EppDB2;
                        end
                        EPP_MAP_HEADER_SIZE + MAP_SIZE: begin
                            score[current_map] <= 0;
                            read_progress <= 0;
                            if (current_map == number_of_maps - 1) begin
                                current_map <= 0;
                                state <= STATE_IDLE;
                            end else begin
                                current_map <= current_map + 1;
                            end
                        end
                        endcase
                    end
                    endcase
                end
                EPP_REG_STATUS: begin end
                default: begin end
                endcase
            end else begin // EPP_READ
                case (epp_addr)
                EPP_REG_STATUS: begin
                    epp_data_buf <= state;
                end
                default: begin end
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

    /////////////////////////////////
    /////  Main logic ///////////////
    /////////////////////////////////

    case (state)
    STATE_IDLE: begin
        led <= 1;
        if (btn == 4'b1111) begin
            current_map <= sw;
        end
    end
    STATE_READING_MAPS: begin
        // led <= 3;
    end
    default: begin end
    endcase
    // TODO jump to level
    // TODO game logic...
end

endmodule

