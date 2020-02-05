#!/usr/bin/env python3

import argparse
import requests
import re

WIDTH, HEIGHT = 20, 15

def main():
    parser = argparse.ArgumentParser(description='Download sokoban levels')
    parser.add_argument('map_ids', type=str, nargs='+')

    args = parser.parse_args()

    for mid in args.map_ids:
        handle_mid(mid)

def handle_mid(mid):
    # download level
    URL_PREFIX = "https://sokoban.info/?"
    resp = requests.get(URL_PREFIX + mid)
    m = re.search(br'var Board\s+="([^"]+)"', resp.content)
    desc = m.group(1).split(b'!')

    # add padding
    w, h = len(desc[0]), len(desc)
    if w > WIDTH or h > HEIGHT:
        print("{}> ERROR: map of size {}x{} doesn't fit into {}x{}".format(mid, w, h, WIDTH, HEIGHT))
        return

    while len(desc) < HEIGHT:
        if len(desc) % 2 == 0:
            desc.insert(0, b'')
        else:
            desc.append(b'')
    desc = list(map(lambda s: s.center(WIDTH, b'x'), desc))

    # find stats
    player_x, player_y = None, None
    remaining_boxes = 0
    remaining_targets = 0

    for y in range(HEIGHT):
        for x in range(WIDTH):
            if desc[y][x] == ord('@'):
                if player_x is not None:
                    print("{}> ERROR: too many players on the map".format(mid))
                    return
                player_x, player_y = x, y
            elif desc[y][x] == ord('.'):
                remaining_targets += 1
            elif desc[y][x] == ord('$'):
                remaining_boxes += 1

    if remaining_boxes != remaining_targets:
        print("{}> ERROR: {} unmatched boxes, but only {} targets".format(mid, remaining_boxes, remaining_targets))
        return

    if player_x is None:
        print("{}> ERROR: player not placed on the map".format(mid))
        print(desc)
        return


    # translate to bit stream
    desc = b''.join(desc)
    bitstream = bytes([player_x, player_y, remaining_boxes])
    tr_dict = {
        ord('#'): b'\x00', # wall
        ord('$'): b'\x01', # box
        ord('*'): b'\x02', # box ready
        ord('.'): b'\x03', # target
        ord('@'): b'\x06', # player (remapped to 'inside')
        ord('x'): b'\x05', # outside
        ord(' '): b'\x06', # inside
    }
    for tile in desc:
        bitstream += tr_dict[tile]

    # save the bitstream
    fname = 'maps_cache/{}.bit'.format(mid)
    with open(fname, 'wb') as f:
        f.write(bitstream)
        print("{}> OK: written bitstream to {}".format(mid, fname))


if __name__ == "__main__":
    main()

