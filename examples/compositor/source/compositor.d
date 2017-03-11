module compositor;

import backend;
import wayland.server;

import std.algorithm;
import std.typecons : Flag;
import std.stdio;
import std.process;

class Client
{
	Compositor comp;
	WlClient cl;
	WlResource[] res;

	this(Compositor comp, WlClient cl)
	{
		this.comp = comp;
		this.cl = cl;
	}

	void onDestroy(WlClient cl)
	{
		writeln("Client.onDestroy");
		comp._clients = comp._clients.remove!(c => c is this);
	}
}

class Compositor : CompositorBackendInterface
{
	private {
		Backend _backend;
		Client[] _clients;

		WlDisplay _display;
		WlEventLoop _loop;

		WlCompositor.Global wlComp;
	}

	override @property WlDisplay display()
	{
		return _display;
	}

	override void exit()
	{
		_display.terminate();
	}

    override void eventExpose()
	{}

    override void eventMouseMove(int x, int y)
	{}

    override void eventMouseButton(int button, Flag!"down" down)
	{}

    override void eventKey(int key, Flag!"down" down)
	{}


private:

	int run()
	{
		_display = WlDisplay.create();
		scope(exit) _display.destroy();

		environment["WAYLAND_DISPLAY"] = _display.addSocketAuto();

		wlComp = new WlCompositor.Global(_display, 4, &onCompBind);
		scope(exit) wlComp.destroy();

		_backend = Backend.create();
		_backend.initialize(new BackendConfig(false, 640, 480), this);
		scope(exit) _backend.terminate();

		auto output = _backend.createOutput();
		output.enable();

		auto timer = _display.eventLoop.addTimer({
			spawnProcess([
				"wayland-tracker", "simple",
				"-x", "protocol/wayland.xml",
				"--", "examples/list_registry/wayland-d_list_registry"
			]);
			return 1;
		});
		timer.update(1000);

		_display.onClientCreated = (WlClient cl)
		{
			writeln("onClientCreated");
			_clients ~= new Client(this, cl);
		};

		_display.run();

		return 0;
	}

	void onCompBind(WlClient cl, uint ver, uint id)
	{
		writeln("comp bind");
	}
}

int main()
{
	auto comp = new Compositor;
	return comp.run();
}
