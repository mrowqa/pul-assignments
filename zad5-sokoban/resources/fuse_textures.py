#!/bin/python3

from PIL import Image

files = ["wall.gif", "box.gif", "box_ready.gif", "target.gif", "player.gif"]

data = ""

for f in files:
    im = Image.open(f).convert("RGB").resize((32, 32))
    w, h = im.size
    for x in range(w):
        for y in range(h):
            r, g, b = im.getpixel((y, x))
            res = \
                (int(r / 2**8 * 2**3) << 5) + \
                (int(g / 2**8 * 2**3) << 2) + \
                int(b / 2**8 * 2**2)
            data += "{:02x}\n".format(res)
        # data += "\n"
    # data += "\n\n"

data += "00\n" * (6000 - 32*32*len(files)) # padding

with open("textures.hex", "w") as f:
    f.write(data)

