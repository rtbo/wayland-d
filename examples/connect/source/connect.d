module connect;

import wayland.client;
import std.stdio;

void main()
{
	auto wl = WlDisplay.connect();
	if (wl)
	{
		writeln("connected to wayland display version ", wl.ver);
		wl.disconnect();
		writeln("disconnected");
	}
	else
	{
		writeln("could not connect to wayland");
	}
}
