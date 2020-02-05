#!/bin/python3

from PIL import Image

files = ["wall.gif", "box.gif", "box_ready.gif", "target.gif", "player.gif", "outside.gif", "inside.gif"]

data = ""
palette = ""
bytes_in_pack = 2048
colors = 16
packs = 2
palette_space = 16 * 8

for f in files:
    im = Image.open(f).convert("RGB").resize((32, 32)).quantize(colors=colors)
    w, h = im.size
    for y in range(h):
        for x in range(0, w, 2):
            c = im.getpixel((x, y)) + (im.getpixel((x+1, y)) << 4)
            if c >= 256:
                print("x, y, c", x, y, c)
            assert 0 <= c < 256
            data += "{:02x}\n".format(c)
        # data += "\n"
    # data += "\n\n"
    for i in range(colors):
        r = im.palette.palette[3*i]
        g = im.palette.palette[3*i+1]
        b = im.palette.palette[3*i+2]
        res = \
            (int(r / 2**8 * 2**3) << 5) + \
            (int(g / 2**8 * 2**3) << 2) + \
            int(b / 2**8 * 2**2)
        assert 0 <= res < 256
        palette += "{:02x}\n".format(res)

data += "00\n" * (bytes_in_pack*packs - len(data)//3) # padding

for part in range(packs):
    chunk_len = len("00\n") * bytes_in_pack
    with open("textures_paletted{}.hex".format(part), "w") as f:
        f.write(data[part*chunk_len:(part+1)*chunk_len])

with open("textures_palette.hex", "w") as f:
    f.write(palette)

