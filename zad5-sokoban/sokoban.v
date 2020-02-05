`default_nettype none

module sokoban(
    input wire uclk,
    // input wire mclk,
    // debug
    output reg [7:0] led,
    input wire [3:0] btn0,
    input wire [7:0] sw0,
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
reg [7:0] sw1;
reg [7:0] sw;

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
// help ISE use only 3 blocks instead of 4...
reg [7:0] tile_data0 [0:2047];
reg [7:0] tile_data1 [0:2047];
reg [7:0] tile_data2 [0:2047];

initial begin
    $readmemh("resources/textures0.hex", tile_data0);
    $readmemh("resources/textures1.hex", tile_data1);
    $readmemh("resources/textures2.hex", tile_data2);
    led <= 0;
end

// TODO "secret room" with "daj 5! \n xd"; displays for 5 secs after lvl completion; or 0.25s after incorrect move
// TODO: other ideas:
// - pallete for textures
// - better tricks for compressing maps
// - MULT18x18SIO - could get rid of it ("currently" 3 reported as used, though only 2 should be used...)

// tile map
localparam MAP_WIDTH = RESOLUTION_WIDTH / TILE_EDGE_LEN; // 20
localparam MAP_HEIGHT = RESOLUTION_HEIGHT / TILE_EDGE_LEN; // 15
localparam MAP_SIZE = MAP_WIDTH * MAP_HEIGHT; // 300
localparam MAP_MEM = 2048;
localparam MAPS_CAPACITY = MAP_MEM / MAP_SIZE * 3; // "* 3" -- compressed map

// control wires for epp & the game
// epp
reg [10:0] epp_map_addr;
reg epp_map_write;
reg [2:0] epp_map_write_tile;
// main logic
reg [10:0] game_map_addr;
reg game_map_write;
reg [2:0] game_map_write_tile;

wire [8:0] map_read_data;
reg [2:0] map_read_tile;
wire [8:0] vga_map_read_data;
reg [2:0] vga_map_read_tile;
reg [10:0] map_addr;
reg [10:0] vga_map_addr;
reg [8:0] map_write_data;
reg map_write;

reg epp_write_buffered, epp_next_epp_write_buffered; // fwd decl
reg [7:0] current_map; // fwd decl
reg [7:0] current_map_d1;

// thought: cm2xyz -- it's periodic, make it smaller! (uh, 3*n will never align with power of two)
reg [10:0] current_map_to_offset [MAPS_CAPACITY-1:0];
reg [3:0] current_map_to_tile_selector [MAPS_CAPACITY-1:0];
wire [10:0] current_map_offset = current_map_to_offset[current_map];
wire [3:0] current_map_tile_selector = current_map_to_tile_selector[current_map_d1];

reg [8:0] map_write_mask; // tmp "var"

// note: there's a pipelined ram version for even shorter critical path in other file
// expensive is "map_addr <= *_map_addr + xyz";
//     one could "waste" some memory to gain better timings: align maps to power of two,
//     and simply use current_map as high bytes
// other solution: simply do "+xyz" in every place the "*_map_addr" is set; ISE doesn't optimise it :/
always @* begin
    // writes - assumption: target tile was read one cycle before the write (for masked write)
    map_write_mask <= 9'b111 << (current_map_tile_selector - 2);
    if (epp_map_write || epp_next_epp_write_buffered) begin
        map_addr <= epp_map_addr;
        map_write <= epp_map_write;
        map_write_data <= ({3{epp_map_write_tile}} & map_write_mask) |
                          (map_read_data & ~map_write_mask);
    end else begin
        map_addr <= game_map_addr;
        map_write <= game_map_write;
        map_write_data <= ({3{game_map_write_tile}} & map_write_mask) |
                          (map_read_data & ~map_write_mask);
    end
    map_read_tile <= map_read_data[current_map_tile_selector -: 3];

    vga_map_read_tile <= vga_map_read_data[current_map_tile_selector -: 3];
end

always @(posedge clk) begin
    current_map_d1 <= current_map;
end

RAMB16_S9_S9 #(
    // TODO better init...
    .INIT_00("03_02_01_00_06_05_04_03_02_01_00_06_05_04_03_02_01_00_06_05_04_03_02_01_00_06_05_04_03_02_01_00")
) tile_map (
    .DOA(map_read_data[7:0]), // Port A 8-bit Data Output
    .DOB(vga_map_read_data[7:0]), // Port B 8-bit Data Output
    .DOPA(map_read_data[8:8]), // Port A 1-bit Parity Output
    .DOPB(vga_map_read_data[8:8]), // Port B 1-bit Parity Output
    .ADDRA(map_addr), // Port A 11-bit Address Input
    .ADDRB(vga_map_addr), // Port B 11-bit Address Input
    .CLKA(clk), // Port A Clock
    .CLKB(clk), // Port B Clock
    .DIA(map_write_data[7:0]), // Port A 8-bit Data Input
    .DIB(0), // Port B 8-bit Data Input
    .DIPA(map_write_data[8:8]), // Port A 1-bit parity Input
    .DIPB(0), // Port-B 1-bit parity Input
    .ENA(1), // Port A RAM Enable Input
    .ENB(1), // Port B RAM Enable Input
    .SSRA(0), // Port A Synchronous Set/Reset Input
    .SSRB(0), // Port B Synchronous Set/Reset Input
    .WEA(map_write), // Port A Write Enable Input
    .WEB(0) // Port B Write Enable Input
);

// fwd decl
reg [7:0] number_of_maps;
reg [9:0] read_progress;

reg [9:0] map_player_pos [0:MAPS_CAPACITY-1];
reg [7:0] map_remaining_boxes [0:MAPS_CAPACITY-1];
reg [7:0] map_score [0:MAPS_CAPACITY-1];

wire [9:0] player_pos = map_player_pos[current_map];
wire [7:0] remaining_boxes = map_remaining_boxes[current_map];
wire [7:0] score = map_score[current_map];

integer i;
initial begin
    number_of_maps <= 1;
    current_map <= 0;
    read_progress <= 0;

    // align player with the pattern
    map_player_pos[0] <= 4;
    map_score[0] <= 42;
    map_remaining_boxes[0] <= 0;
    for (i=1; i<MAPS_CAPACITY; i=i+1) begin
        map_player_pos[i] <= 0;
        map_score[i] <= 0;
        map_remaining_boxes[i] <= 0;
    end

    for (i=0; i<MAPS_CAPACITY; i=i+1) begin
        current_map_to_offset[i] <= (i / 3) * MAP_SIZE;
        current_map_to_tile_selector[i] <= i % 3 * 3 + 2; //0->2, 1->5, 2->8
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
reg [19:0] in_tile_idx_d1;
reg [7:0] tile0_pixel_d2, tile1_pixel_d2, tile2_pixel_d2;
reg [7:0] tile_pixel_mux_d2;

reg is_current_tile_player_d1;
reg [7:0] current_tile_d1, current_tile_d2;
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

// TODO rewrite "=" into "<="
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
    vga_map_addr = map_y * MAP_WIDTH + map_x + current_map_offset;
    current_tile_d1 = is_current_tile_player_d1 ? TILE_PLAYER : vga_map_read_tile;
    in_tile_idx_d1 = tile_y_d1 * TILE_EDGE_LEN + tile_x_d1 + current_tile_d1 * TILE_SIZE;

    // outs
    hsync_d0 = H_FRONT_PORCH <= screen_x && screen_x < H_SYNC_PULSE ? HS_ACTIVE : ~HS_ACTIVE; // kinda xor
    vsync_d0 = V_FRONT_PORCH <= screen_y && screen_y < V_SYNC_PULSE ? VS_ACTIVE : ~VS_ACTIVE;
    rgb_d2 = is_on_map_d2 ?
        (current_tile_d2 == TILE_EMPTY_OUTSIDE ? TILE_EMPTY_OUTSIDE_COLOR :
         current_tile_d2 == TILE_EMPTY_INSIDE ? TILE_EMPTY_INSIDE_COLOR :
         (tile_pixel_mux_d2 == 0 ? tile0_pixel_d2 :
          tile_pixel_mux_d2 == 1 ? tile1_pixel_d2 :
          tile2_pixel_d2))
        : 0;
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
    is_current_tile_player_d1 <= map_y * MAP_WIDTH + map_x == player_pos;
    current_tile_d2 <= current_tile_d1;

    // mem
    tile0_pixel_d2 <= tile_data0[in_tile_idx_d1];
    tile1_pixel_d2 <= tile_data1[in_tile_idx_d1];
    tile2_pixel_d2 <= tile_data2[in_tile_idx_d1];
    tile_pixel_mux_d2 <= in_tile_idx_d1 >> 11;

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

localparam EPP_STATE_IDLE = 0;
localparam EPP_STATE_WAIT_FOR_PC = 1;

reg [2:0] epp_state;
reg [3:0] epp_addr;

reg [7:0] epp_data_buf;
reg epp_wr_buf;

reg [10:0] epp_saved_map_addr;
reg [2:0] epp_saved_map_write_tile;

initial begin
    epp_state <= EPP_STATE_IDLE;
    epp_addr <= 4'h0;
    epp_write_buffered <= 0;
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

// epp "next"s
reg [2:0] epp_next_epp_state;
reg [3:0] epp_next_epp_addr;
reg [7:0] epp_next_epp_data_buf;
reg epp_next_epp_wr_buf;
reg epp_next_EppWait;

reg [10:0] epp_next_epp_saved_map_addr;
reg [2:0] epp_next_epp_saved_map_write_tile;

reg [7:0] epp_next_state;
reg [7:0] epp_next_number_of_maps;
reg [7:0] epp_next_current_map;
reg [9:0] epp_next_read_progress;

reg [7:0] epp_next_score;
reg [9:0] epp_next_player_pos;
reg [9:0] epp_next_remaining_boxes;


// logic
localparam STATE_IDLE = 0;
localparam STATE_READING_MAPS = 1;
localparam STATE_WAIT_BTNS_RELEASED = 2;
localparam STATE_PLAYER_MOVE = 3;
localparam STATE_PLAYER_MOVE_FETCH_AHEAD_X2 = 4;
localparam STATE_PLAYER_MOVE_READ_AHEAD = 5;
localparam STATE_PLAYER_MOVE_READ_AHEAD_X2 = 6;
localparam STATE_PLAYER_MOVE_WRITE_AHEAD = 7;
localparam STATE_PLAYER_MOVE_WRITE_AHEAD_X2_FETCH = 8;
localparam STATE_PLAYER_MOVE_WRITE_AHEAD_X2 = 9;

localparam BTN_MV_RIGHT = 4'b0001;
localparam BTN_MV_UP    = 4'b0010;
localparam BTN_MV_DOWN  = 4'b0100;
localparam BTN_MV_LEFT  = 4'b1000;

reg [7:0] state;
reg [7:0] next_led;

reg [9:0] pos_ahead;
reg [9:0] pos_ahead_x2;
reg [7:0] tile_ahead;
reg [7:0] tile_ahead_x2;

initial begin
    state <= STATE_IDLE;
end

reg has_next_current_map;
reg has_next_state;
reg has_next_pos_ahead;
reg has_next_tile_ahead;
reg has_next_tile_ahead_x2;
reg has_next_player_pos;
reg has_next_remaining_boxes;
reg score_up;

reg [7:0] next_current_map;
reg [7:0] next_state;
reg [9:0] next_pos_ahead;
reg [9:0] next_pos_ahead_x2;
reg [7:0] next_tile_ahead;
reg [7:0] next_tile_ahead_x2;
reg [9:0] next_player_pos;
reg [7:0] next_remaining_boxes;

initial begin
    has_next_current_map <= 0;
    has_next_state <= 0;
    has_next_pos_ahead <= 0;
    has_next_tile_ahead <= 0;
    has_next_tile_ahead_x2 <= 0;
    has_next_player_pos <= 0;
    has_next_remaining_boxes <= 0;
    score_up <= 0;
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
// NO VALIDATION so far (on FPGA side; there's validation in the PC driver)

always @* begin
    // mem
    epp_map_addr <= map_addr;
    epp_map_write <= 0;
    epp_map_write_tile <= 3'hx;
    epp_next_epp_write_buffered <= 0;
    epp_next_epp_saved_map_addr <= epp_saved_map_addr;
    epp_next_epp_saved_map_write_tile <= epp_saved_map_write_tile;

    // game logic
    epp_next_state <= state;
    epp_next_number_of_maps <= number_of_maps;
    epp_next_current_map <= current_map;
    epp_next_read_progress <= read_progress;
    epp_next_score <= score;
    epp_next_player_pos <= player_pos;
    epp_next_remaining_boxes <= remaining_boxes;

    // epp
    epp_next_EppWait <= 0;
    epp_next_epp_addr <= epp_addr;
    epp_next_epp_state <= epp_state;
    epp_next_epp_data_buf <= epp_data_buf;
    epp_next_epp_wr_buf <= epp_wr_buf;

    case (epp_state)
    EPP_STATE_IDLE: begin
        epp_next_EppWait <= 0;
        if (!EppAstb2) begin
            if (EppWR2 == EPP_WRITE) begin
                epp_next_epp_addr <= EppDB2;
            end else begin // read
                epp_next_epp_data_buf <= epp_addr;
            end
            epp_next_epp_wr_buf <= EppWR;
            epp_next_epp_state <= EPP_STATE_WAIT_FOR_PC;
        end else if (!EppDstb2) begin
            if (EppWR2 == EPP_WRITE) begin
                case (epp_addr)
                EPP_REG_MAP: begin
                    case (state)
                    STATE_IDLE: begin
                        epp_next_state <= STATE_READING_MAPS;
                        epp_next_number_of_maps <= EppDB2;
                        epp_next_current_map <= 0;
                        epp_next_read_progress <= 0;
                    end
                    STATE_READING_MAPS: begin
                        epp_next_read_progress <= read_progress + 1;
                        case (read_progress)
                        0: begin // pos x
                            epp_next_player_pos <= EppDB2;
                        end
                        1: begin // pos y
                            epp_next_player_pos <= player_pos + EppDB2 * MAP_WIDTH;
                        end
                        2: begin
                            epp_next_remaining_boxes <= EppDB2;
                        end
                        default: begin
                            epp_map_addr <= read_progress - EPP_MAP_HEADER_SIZE + current_map_offset;
                            epp_next_epp_write_buffered <= 1;
                            epp_next_epp_saved_map_addr <= read_progress - EPP_MAP_HEADER_SIZE + current_map_offset;
                            epp_next_epp_saved_map_write_tile <= EppDB2;
                        end
                        endcase
                        if (read_progress == EPP_MAP_HEADER_SIZE + MAP_SIZE - 1) begin
                            epp_next_score <= 0;
                            epp_next_read_progress <= 0;
                            if (current_map == number_of_maps - 1) begin
                                epp_next_current_map <= 0;
                                epp_next_state <= STATE_IDLE;
                            end else begin
                                epp_next_current_map <= current_map + 1;
                            end
                        end
                    end
                    endcase
                end
                EPP_REG_STATUS: begin end
                default: begin end
                endcase
            end else begin // EPP_READ
                case (epp_addr)
                EPP_REG_STATUS: begin
                    epp_next_epp_data_buf <= state;
                end
                default: begin end
                endcase
            end
            epp_next_epp_wr_buf <= EppWR2;
            epp_next_epp_state <= EPP_STATE_WAIT_FOR_PC;
        end
    end
    EPP_STATE_WAIT_FOR_PC: begin
        if (epp_write_buffered) begin
            epp_map_write <= 1;
            epp_map_addr <= epp_saved_map_addr;
            epp_map_write_tile <= epp_saved_map_write_tile;
        end

        epp_next_EppWait <= 1;
        if (EppAstb2 && EppDstb2) begin
            epp_next_epp_state <= EPP_STATE_IDLE;
        end
    end
    default: begin
    end
    endcase
end


always @(posedge clk) begin
    /////////////////////////////////
    /////     EPP     ///////////////
    /////////////////////////////////

    // mem
    epp_write_buffered <= epp_next_epp_write_buffered;
    epp_saved_map_addr <= epp_next_epp_saved_map_addr;
    epp_saved_map_write_tile <= epp_next_epp_saved_map_write_tile;

    // sync inputs
    EppDB1 <= EppDB;
    EppDB2 <= EppDB1;
    EppAstb1 <= EppAstb;
    EppAstb2 <= EppAstb1;
    EppDstb1 <= EppDstb;
    EppDstb2 <= EppDstb1;
    EppWR1 <= EppWR;
    EppWR2 <= EppWR1;

    // game logic
    state <= epp_next_state;
    number_of_maps <= epp_next_number_of_maps;
    current_map <= epp_next_current_map;
    read_progress <= epp_next_read_progress;
    map_score[current_map] <= epp_next_score;
    map_player_pos[current_map] <= epp_next_player_pos;
    map_remaining_boxes[current_map] <= epp_next_remaining_boxes;

    // epp
    EppWait <= epp_next_EppWait;
    epp_addr <= epp_next_epp_addr;
    epp_state <= epp_next_epp_state;
    epp_data_buf <= epp_next_epp_data_buf;
    epp_wr_buf <= epp_next_epp_wr_buf;


    /////////////////////////////////
    /////  Main logic ///////////////
    /////////////////////////////////

    // "has_*" not to overshadow epp_next_*

    if (has_next_current_map) begin
        current_map <= next_current_map;
    end
    if (has_next_state) begin
        state <= next_state;
    end
    if (has_next_pos_ahead) begin
        pos_ahead <= next_pos_ahead;
        pos_ahead_x2 <= next_pos_ahead_x2;
    end
    if (has_next_tile_ahead) begin
        tile_ahead <= next_tile_ahead;
    end
    if (has_next_tile_ahead_x2) begin
        tile_ahead_x2 <= next_tile_ahead_x2;
    end
    if (has_next_player_pos) begin
        map_player_pos[current_map] <= next_player_pos;
    end
    if (score_up) begin
        map_score[current_map] <= score + 1;
    end
    if (has_next_remaining_boxes) begin
        map_remaining_boxes[current_map] <= next_remaining_boxes;
    end

    led <= next_led;
end

always @* begin
    // TODO: try coming back to 'hxxxxxxxx (?)
    has_next_current_map <= 0;
    next_current_map <= current_map;
    has_next_state <= 0;
    next_state <= state;
    has_next_pos_ahead <= 0;
    next_pos_ahead <= pos_ahead;
    next_pos_ahead_x2 <= pos_ahead_x2;
    has_next_tile_ahead <= 0;
    next_tile_ahead <= tile_ahead;
    has_next_tile_ahead_x2 <= 0;
    next_tile_ahead_x2 <= tile_ahead_x2;
    has_next_player_pos <= 0;
    next_player_pos <= player_pos;
    score_up <= 0;
    has_next_remaining_boxes <= 0;
    next_remaining_boxes <= remaining_boxes;
    game_map_addr <= map_addr;
    game_map_write <= 0;
    game_map_write_tile <= 3'hx;

    case (state)
    STATE_IDLE: begin
        if (sw[7]) begin
            has_next_current_map <= 1;
            next_current_map <= sw[6:0]; // "use" all switches to make tooling happy
        end else if (btn == BTN_MV_UP || btn == BTN_MV_DOWN
                || btn == BTN_MV_LEFT || btn == BTN_MV_RIGHT) begin
            has_next_state <= 1;
            next_state <= STATE_PLAYER_MOVE_READ_AHEAD;
            has_next_pos_ahead <= 1;
            case (btn)
            BTN_MV_UP: begin
                next_pos_ahead <= player_pos - MAP_WIDTH;
                next_pos_ahead_x2 <= player_pos - 2*MAP_WIDTH;
            end
            BTN_MV_DOWN: begin
                next_pos_ahead <= player_pos + MAP_WIDTH;
                next_pos_ahead_x2 <= player_pos + 2*MAP_WIDTH;
            end
            BTN_MV_LEFT: begin
                next_pos_ahead <= player_pos - 1;
                next_pos_ahead_x2 <= player_pos - 2;
            end
            BTN_MV_RIGHT: begin
                next_pos_ahead <= player_pos + 1;
                next_pos_ahead_x2 <= player_pos + 2;
            end
            endcase
            game_map_addr <= next_pos_ahead + current_map_offset;
        end
    end
    STATE_PLAYER_MOVE_READ_AHEAD: begin
        has_next_tile_ahead <= 1;
        next_tile_ahead <= map_read_tile;
        game_map_addr <= pos_ahead_x2 + current_map_offset;
        has_next_state <= 1;
        next_state <= STATE_PLAYER_MOVE_READ_AHEAD_X2;
    end
    STATE_PLAYER_MOVE_READ_AHEAD_X2: begin
        has_next_tile_ahead_x2 <= 1;
        next_tile_ahead_x2 <= map_read_tile;
        has_next_state <= 1;
        next_state <= STATE_PLAYER_MOVE;
    end
    STATE_PLAYER_MOVE: begin
        if (tile_ahead == TILE_EMPTY_INSIDE || tile_ahead == TILE_TARGET) begin
            has_next_player_pos <= 1;
            next_player_pos <= pos_ahead;
            score_up <= 1;

            has_next_state <= 1;
            next_state <= STATE_WAIT_BTNS_RELEASED;

        end else if ((tile_ahead == TILE_BOX || tile_ahead == TILE_BOX_READY) &&
                (tile_ahead_x2 == TILE_EMPTY_INSIDE || tile_ahead_x2 == TILE_TARGET)) begin
            has_next_player_pos <= 1;
            next_player_pos <= pos_ahead;
            score_up <= 1;

            has_next_remaining_boxes <= 1;
            next_remaining_boxes <=
                remaining_boxes - (tile_ahead_x2 == TILE_TARGET) + (tile_ahead == TILE_BOX_READY);

            game_map_addr <= pos_ahead + current_map_offset; // fetch for masked write

            has_next_state <= 1;
            next_state <= STATE_PLAYER_MOVE_WRITE_AHEAD;

        end else begin // can't move
            has_next_state <= 1;
            next_state <= STATE_WAIT_BTNS_RELEASED;
            // TODO animation "becoming whiter"
        end
    end
    STATE_PLAYER_MOVE_WRITE_AHEAD: begin
        game_map_addr <= pos_ahead + current_map_offset;
        game_map_write <= 1;
        game_map_write_tile <= (tile_ahead == TILE_BOX_READY ? TILE_TARGET : TILE_EMPTY_INSIDE);

        has_next_state <= 1;
        next_state <= STATE_PLAYER_MOVE_WRITE_AHEAD_X2_FETCH;
    end
    STATE_PLAYER_MOVE_WRITE_AHEAD_X2_FETCH: begin
        game_map_addr <= pos_ahead_x2 + current_map_offset;

        has_next_state <= 1;
        next_state <= STATE_PLAYER_MOVE_WRITE_AHEAD_X2;
    end
    STATE_PLAYER_MOVE_WRITE_AHEAD_X2: begin
        game_map_addr <= pos_ahead_x2 + current_map_offset;
        game_map_write <= 1;
        game_map_write_tile <= (tile_ahead_x2 == TILE_TARGET ? TILE_BOX_READY : TILE_BOX);
        if (remaining_boxes == 0 && current_map + 1 < MAPS_CAPACITY) begin
            has_next_current_map <= 1;
            next_current_map <= current_map + 1;
        end

        has_next_state <= 1;
        next_state <= STATE_WAIT_BTNS_RELEASED;
    end
    STATE_PLAYER_MOVE_WRITE_AHEAD: begin
        game_map_addr <= pos_ahead_x2 + current_map_offset;
        game_map_write <= 1;
        game_map_write_tile <= (tile_ahead_x2 == TILE_TARGET ? TILE_BOX_READY : TILE_BOX);
        if (remaining_boxes == 0 && current_map + 1 < MAPS_CAPACITY) begin
            has_next_current_map <= 1;
            next_current_map <= current_map + 1; // TODO what if finished all maps?
        end

        has_next_state <= 1;
        next_state <= STATE_WAIT_BTNS_RELEASED;
    end
    STATE_WAIT_BTNS_RELEASED: begin
        if (btn == 0) begin
            has_next_state <= 1;
            next_state <= STATE_IDLE;
        end
    end
    STATE_READING_MAPS: begin
    end
    default: begin end
    endcase

    // LEDs
    next_led <= score;

    // debug prints
    case(sw)
    8'b01000000: begin
        next_led[1:0] <= state;
        next_led[4:2] <= current_map;
        next_led[7:5] <= number_of_maps;
    end
    8'b01100000: begin
        next_led[3:0] <= tile_ahead;
        next_led[7:4] <= tile_ahead_x2;
    end
    8'b01010000: begin
        next_led <= pos_ahead;
    end
    8'b01110000: begin
        next_led <= pos_ahead_x2;
    end
    8'b01001000: begin
        next_led <= remaining_boxes;
    end
    endcase
end

endmodule

