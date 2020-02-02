#!/bin/python3

from PIL import Image

files = ["wall.gif", "box.gif", "box_ready.gif", "target.gif", "player.gif"]

data = ""
bytes_in_pack = 2048
packs = 3

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

data += "00\n" * (bytes_in_pack*packs - 32*32*len(files)) # padding

for part in range(3):
    chunk_len = len("00\n") * bytes_in_pack
    with open("textures{}.hex".format(part), "w") as f:
        f.write(data[part*chunk_len:(part+1)*chunk_len])

