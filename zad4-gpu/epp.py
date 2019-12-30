#!/usr/bin/env python3

import argparse
import usb1
from adepttool.device import get_devices
import sys

parser = argparse.ArgumentParser(description='Program the FPGA on Basys 2.')
parser.add_argument('--device', type=int, help='Device index', default=0)

args = parser.parse_args()

# without with-as so the port is available when executing with python -i
ctx = usb1.USBContext()
devs = get_devices(ctx)
if args.device >= len(devs):
    if not devs:
        print('No devices found.')
    else:
        print('Invalid device index (max is {})'.format(len(devs)-1))
    sys.exit(1)
dev = devs[args.device]
dev.start()
port = dev.depp_ports[0]
port.enable()

# regs
X1L, X1H = 0, 1
Y1L, Y1H = 2, 3
X2L, X2H = 4, 5
Y2L, Y2H = 6, 7
WL, WH = 8, 9
HL, HH = 10, 11
BLIT = 12
FILL = 13
DA = 14
STATUS = 15


def chessboard():
    port.put_reg(X1L, b"\x00")
    port.put_reg(X1H, b"\x00")
    for y in range(200):
        port.put_reg(Y1L, bytearray([y]))
        port.put_reg(DA, (b"\xaa" if y % 2 == 0 else b"\x55") * 40)
    port.put_reg(Y1L, b"\x00")

def x_axis(y):
    port.put_reg(X1L, b"\x00")
    port.put_reg(X1H, b"\x00")
    yl, yh = y % 256, y // 256
    port.put_reg(Y1L, bytes([yl]))
    port.put_reg(Y1H, bytes([yh]))
    port.put_reg(DA, b"\xff\x00" * 20)

def get_regs():
    print(port.get_regs(range(12)))

def fill_rect(x, y, width, height, color):
    xl, xh = x % 256, x // 256
    yl, yh = y % 256, y // 256
    wl, wh = width % 256, width // 256
    hl, hh = height % 256, height // 256
    port.put_reg(X1L, bytes([xl]))
    port.put_reg(X1H, bytes([xh]))
    port.put_reg(Y1L, bytes([yl]))
    port.put_reg(Y1H, bytes([yh]))
    port.put_reg(WL, bytes([wl]))
    port.put_reg(WH, bytes([wh]))
    port.put_reg(HL, bytes([hl]))
    port.put_reg(HH, bytes([hh]))
    port.put_reg(FILL, bytes([color]))

def rect_test(spacing):
    edge = 7
    for y in range(10):
        for x in range(10):
            fill_rect(7 + x*(7+spacing), 7 + y*(7+spacing), 7, 7, (y+x) % 2)
            fill_rect(7 + x*(7+spacing) + 2, 7 + y*(7+spacing) + 2, 3, 3, (y+x+1) % 2)
