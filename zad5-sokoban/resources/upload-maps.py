#!/usr/bin/env python3

import argparse
import usb1
from adepttool.device import get_devices
import sys
from time import sleep

MAX_MAPS = 6

def main():
    parser = argparse.ArgumentParser(description='Program the FPGA on Basys 2.')
    parser.add_argument('--device', type=int, help='Device index', default=0)
    parser.add_argument('map_ids', type=str, nargs='+')

    args = parser.parse_args()

    # without with-as so the port is available when executing with python -i
    with usb1.USBContext() as ctx:
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

        # load & upload the maps
        maps = list(map(load_map, args.map_ids))
        if len(maps) > MAX_MAPS:
            print('ERROR: max allowed maps is {}, got {}'.format(MAX_MAPS, len(maps)))
            sys.exit(1)
        upload_maps(port, maps)

def load_map(map_id):
    with open('maps_cache/{}.bit'.format(map_id), 'rb') as f:
        return f.read()

def upload_maps(port, maps):
    EPP_MAP_PORT = 0

    bitstream = bytes([len(maps)])
    bitstream += b''.join(maps)

    print('bitstream: {} bytes'.format(len(bitstream)))
    port.put_reg(EPP_MAP_PORT, bitstream)

if __name__ == "__main__":
    main()

