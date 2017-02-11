## wayland-d

D bindings to wayland.

![dub version](https://img.shields.io/dub/v/wayland-d.svg)
![dub downloads](https://img.shields.io/dub/dt/wayland-d.svg)

Supersedes former bindings [wayland-scanner-d](https://github.com/rtbo/wayland-scanner-d)
and [wayland-client-d](https://github.com/rtbo/wayland-client-d).

### Client usage

Add the `wayland-d:client` dependency in your `dub.json`:
```json
"dependencies": {
    "wayland-d:client": "~>0.0.1"
}
```

example client code:
```d
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
```
