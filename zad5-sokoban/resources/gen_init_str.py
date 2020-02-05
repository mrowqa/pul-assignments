#!/usr/bin/python3

mem = []
for i in range(340):
    mem.append(i % 7)

chunk_size = 32
i = 0
while i * chunk_size < 100: #len(mem) / 3:
    val = ""
    for j in range(chunk_size):
        mem_cont = mem[i*chunk_size + j] + \
                   (mem[i*chunk_size + j + 100]<<3) + \
                   (mem[i*chunk_size + j + 200]<<6)
        val = "{:02x}".format(mem_cont & 0xFF) + val
    print('.INIT_{:02}("{}"),'.format(i, val))
    i += 1

