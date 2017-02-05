module connect;

import wayland.client;
import std.stdio;

void main()
{
	auto conn = WlDisplay.connect();
	if (conn)
	{
		writeln("connected");
		conn.disconnect();
		writeln("disconnected");
	}
	else
	{
		writeln("could not connect");
	}
}
