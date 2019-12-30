#!/bin/bash

set -e

if [[ "$1" == "" ]]; then
    echo "Error, no project specified"
    exit 1
fi
NAME=$1

iverilog -o $NAME ${NAME}_tb.v $NAME.v
./$NAME

