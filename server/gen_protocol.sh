#!/bin/bash

SERVER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WL_D_DIR=$SERVER_DIR/..

PROTOCOL=$WL_D_DIR/protocol/wayland.xml
SERVER_SRC=$SERVER_DIR/source/wayland/server/protocol.d
SCANNER_SRC=$WL_D_DIR/scanner/source/wayland/scanner.d

if [ $PROTOCOL -ot $SERVER_SRC ]; then
    if [ $SCANNER_SRC -ot $SERVER_SRC ]; then
        exit 0
    fi
fi

cd $WL_D_DIR

dub run wayland-d:scanner --build=release -- \
                -c server \
                -m wayland.server.protocol \
                -i $PROTOCOL \
                -o $SERVER_SRC
