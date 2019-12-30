`define SIM

module test;

initial begin
    $dumpfile("gpu.vcd");
    $dumpvars(0, test);

    #1
    test_gpu.epp_regs[0] = 6; // x
    test_gpu.epp_regs[2] = 1; // y
    test_gpu.epp_regs[8] = 3 + 8; // w
    test_gpu.epp_regs[10] = 1; // h

    #2
    test_gpu.start_fill = 1;

    #3
    test_gpu.start_fill = 0;

    #1000
    $monitor("At time %t, mem[27..2B] = [%h, %h, %h, %h, %h] ",
              $time,
              test_gpu.frame_buffer['h27],
              test_gpu.frame_buffer['h28],
              test_gpu.frame_buffer['h29],
              test_gpu.frame_buffer['h2A],
              test_gpu.frame_buffer['h2B]
              );
    $finish;
end

reg uclk = 0;
always #1 uclk = !uclk;

wire [7:0] led;
wire hsync;
wire vsync;
wire [7:0] rgb;
wire [7:0] EppDB;
reg EppAstb;
reg EppDstb;
reg EppWR;
wire EppWait;

gpu test_gpu(uclk, led, hsync, vsync, rgb, EppDB, EppAstb, EppDstb, EppWR, EppWait);

endmodule
