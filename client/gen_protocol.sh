#!/bin/bash

CLIENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WL_D_DIR=$CLIENT_DIR/..

PROTOCOL=$WL_D_DIR/protocol/wayland.xml
CLIENT_SRC=$CLIENT_DIR/source/wayland/client/protocol.d
SCANNER_SRC=$WL_D_DIR/scanner/source/wayland/scanner.d

if [ $PROTOCOL -ot $CLIENT_SRC ]; then
    if [ $SCANNER_SRC -ot $CLIENT_SRC ]; then
        exit 0
    fi
fi

cd $WL_D_DIR

dub run wayland-d:scanner -- \
                -m wayland.client.protocol \
                -i $PROTOCOL \
                -o $CLIENT_SRC
