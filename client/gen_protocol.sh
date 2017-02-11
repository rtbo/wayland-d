#!/bin/bash

CLIENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WL_D_DIR=$CLIENT_DIR/..

cd $WL_D_DIR

dub run wayland-d:scanner -- \
                -m wayland.client.protocol \
                -i protocol/wayland.xml \
                -o client/source/wayland/client/protocol.d
