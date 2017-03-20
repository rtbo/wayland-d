# wayland-d

D bindings to wayland.

![dub version](https://img.shields.io/dub/v/wayland-d.svg)
![dub downloads](https://img.shields.io/dub/dt/wayland-d.svg)

Have several components:
 - __*Scanner*__: XML protocol parser and code generator. It generates high level objects.
   - support for client and server side code generation.
   - support foreign protocols (such as `xdg-shell`. See the [simple-egl example](https://github.com/rtbo/wayland-d/blob/master/examples/simple_egl/source/simple_egl.d))

 - __*Client*__: client protocol and `libwayland-client` native API wrapped into higher level objects.

 - __*EGL*__: allow use of wayland-egl (see [this example](https://github.com/rtbo/wayland-d/blob/master/examples/simple_egl/source/simple_egl.d)).

 - __*Server*__: server side protocol and bindings to `libwayland-server` to allow the creation of a compositor.


## Client usage

Add the `wayland-d:client` dependency in your `dub.json`:
```json
"dependencies": {
    "wayland-d:client": "~>0.0.3"
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

You can run the examples if you are under a wayland compositor:
```sh
dub run wayland-d:list_registry
```
For some of the examples, this only works if you `cd` first to the project root
directory:

```sh
git clone https://github.com/rtbo/wayland-d.git
cd wayland-d
dub run wayland-d:hello
```
