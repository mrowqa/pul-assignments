#!/bin/bash
set -e

if [[ "$1" == "" ]]; then
    echo "Error, no project specified"
    exit 1
fi
NAME=$1

# Synteza (.v -> .ngc)
xst -ifn $NAME.xst
# Linkowanie (.ngc -> .ngd)
ngdbuild $NAME -uc $NAME.ucf
# Tłumaczenie na prymitywy dostępne w układzie Spartan 3E (.ngd -> .ncd)
map $NAME
# Place and route (.ncd -> lepszy .ncd)
par -w $NAME.ncd ${NAME}_par.ncd
# Generowanie finalnego bitstreamu (.ncd -> .bit)
bitgen -w ${NAME}_par.ncd -g StartupClk:JTAGClk
