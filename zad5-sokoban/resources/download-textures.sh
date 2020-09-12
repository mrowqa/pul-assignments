#!/bin/bash

USER_AGENT="Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1)"

wget "https://sokoban.info/img/i0.gif" -O "outside.gif" -U "$USER_AGENT"
wget "https://sokoban.info/img/i1.gif" -O "target.gif" -U "$USER_AGENT"
wget "https://sokoban.info/img/i2.gif" -O "wall.gif" -U "$USER_AGENT"
wget "https://sokoban.info/img/i3.gif" -O "box.gif" -U "$USER_AGENT"
wget "https://sokoban.info/img/i4.gif" -O "box_ready.gif" -U "$USER_AGENT"
wget "https://sokoban.info/img/i5.gif" -O "player.gif" -U "$USER_AGENT"
wget "https://sokoban.info/img/i7.gif" -O "inside.gif" -U "$USER_AGENT"

