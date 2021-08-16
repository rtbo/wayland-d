// Copyright © 2017-2021 Rémi Thebault
module list_registry;

import wayland.client;
import std.exception;
import std.stdio;

void main()
{
    auto display = enforce(WlDisplay.connect());
	scope(exit) display.disconnect();

    auto reg = enforce(display.getRegistry());
	scope(exit) reg.destroy();

    reg.onGlobal = (WlRegistry /+reg+/, uint /+name+/, string iface, uint /+ver+/) {
        writeln("registering ", iface);
    };
    display.roundtrip();
}
