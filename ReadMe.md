# wayland-d

D bindings to wayland.

![dub version](https://img.shields.io/dub/v/wayland-d.svg)
![dub downloads](https://img.shields.io/dub/dt/wayland-d.svg)

Have several components:
 - scanner: XML protocol parser and code generator. It generates high level objects.
 - client: client protocol and libwayland-client native API wrapped into higher level objects.
 - egl: allow use of wayland-egl (see [this example](https://github.com/rtbo/wayland-d/blob/master/examples/egl_window/source/egl_window.d)).
 - server: unimplemented.

## Client usage

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

## Playground

You can try one of the examples if you are under a wayland compositor:
```sh
dub run wayland-d:hello
```
