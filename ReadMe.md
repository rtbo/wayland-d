# Wayland D bindings

D bindings to wayland.

![dub version](https://img.shields.io/dub/v/wayland.svg)
![dub downloads](https://img.shields.io/dub/dt/wayland.svg)

There are several components:
 - __*Scanner*__: XML protocol parser and code generator. It generates high level objects.
   - support for client and server side code generation.
   - support foreign protocols (such as `xdg-shell`. See the [simple-egl example](https://github.com/rtbo/wayland-d/blob/master/examples/simple_egl/source/simple_egl.d))

 - __*Client*__: client protocol and `libwayland-client` native API wrapped into higher level objects.

 - __*EGL*__: allow use of wayland-egl (see [this example](https://github.com/rtbo/wayland-d/blob/master/examples/simple_egl/source/simple_egl.d)).

 - __*Server*__: server side protocol and bindings to `libwayland-server` to allow the creation of a compositor.



## Scanner usage

```sh
$ dub run wayland:scanner -- -h
wayland:scanner-v0.1.0
  A Wayland protocol scanner and D code generator.

Options:
-c   --code generated code: client|server [client]
-i  --input input file [stdin]
-o --output output file [stdout]
-m --module D module name (required)
-h   --help This help information.
```


## Client usage

Add the `wayland:client` dependency in your `dub.json`:
```json
"dependencies": {
    "wayland:client": "~>0.1.0"
}
```
The main wayland protocol is automatically generated by the scanner
as a pre-build step of `wayland:client`.
To use other protocols, the scanner must be used and XML protocol definition
provided by the application. See the [simple-egl](https://github.com/rtbo/wayland-d/blob/master/examples/simple_egl/source/simple_egl.d)
example that uses the `xdg-shell` protocol.

### Requests

Requests are made by calling methods on the `WlProxy` objects generated by the
protocol. For example:
```d
WlSurface surf = makeSurf();
WlBuffer buf = makeBuf();
surf.attach(buf, 0, 0);
```

As described in the protocol, some requests are void, others return a new object.


### Events

Events are listened to by registering a delegate in the `WlProxy` objects.
See `WlRegistry.onGlobal` in the example hereunder.


### Example of client code

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

## Server usage

In the current implementation of the bindings, handling client requests is done
by subclassing the `WlGlobal` and `WlResource` subclasses generated by the protocol.
All protocol-generated classes that have requests are `abstract`.
In the requests creating new resources, the application must therefore return
a subclass object that implement the protocol requests.

Events are sent to clients by calling the `send[EventName]` methods of resource objects.

A part of the main protocol is implemented natively by `libwayland-server`. This
is the case of `wl_shm` and `wl_shm_pool`. A consequence of this is that `wl_buffer` objects
are not created under the application control. To create a `WlBuffer` subclass
object that implement the requests, it is required to listen to native resource creation:

```d
class Compositor : WlCompositor
{
    ...
	void newClientConnection(WlClient cl)
	{
		cl.addNativeResourceCreatedListener((wl_resource* natRes) {
			import core.stdc.string : strcmp;
			if (strcmp(wl_resource_get_class(natRes), "wl_buffer") == 0) {
				new Buffer(natRes);
			}
		});
	}
}

class Buffer : WlBuffer
{
    ...
}
```

See the [compositor](https://github.com/rtbo/wayland-d/blob/master/examples/compositor) example
that implement a quick and dirty compositor. It is not a good design of compositor, it only
illustrates the bindings mechanics.


## Playground

You can run the examples if you are under a wayland compositor:
```sh
dub run wayland:list_registry
```
For some of the examples, this only works if you `cd` first to the project root
directory:

```sh
git clone https://github.com/rtbo/wayland-d.git
cd wayland-d
dub run wayland:hello
```
