module compositor;

import backend;
import wayland.server;

import std.algorithm;
import std.typecons : Flag;
import std.stdio;
import std.process;


class Compositor : WlCompositor, CompositorBackendInterface
{
	private {
		Backend _backend;

		WlDisplay _display;
		WlEventLoop _loop;

		WlClient[] _clients;
	}

	this(WlDisplay display)
	{
		this._display = display;
		super(display, 4);
	}

	// WlCompositor

	override void bind(WlClient cl, uint ver, uint id)
	{
		writeln("onCompBind");
		auto res = new Resource(cl, ver, id);
		res.onCreateSurface = &createSurface;
		res.onCreateRegion = &createRegion;
	}

	private void createSurface(WlClient cl, Resource res, uint id) {
	}

	private void createRegion(WlClient cl, Resource res, uint id) {
	}


	// CompositorBackendInterface

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
		_display.initShm();

		_backend = Backend.create();
		_backend.initialize(new BackendConfig(false, 640, 480), this);
		scope(exit) _backend.terminate();

		auto output = _backend.createOutput();

		auto timer = _display.eventLoop.addTimer({
			spawnProcess([
				"wayland-tracker", "simple",
				"-x", "protocol/wayland.xml",
				"--", "examples/comp_client/wayland-d_comp_client"
			]);
			return 1;
		});
		timer.update(1000);

		_display.addClientCreatedListener(&addClient);

		_display.run();

		return 0;
	}

	void addClient(WlClient cl)
	{
		writeln("addClient");
		_clients ~= cl;
		cl.addDestroyListener(&removeClient);
	}

	void removeClient(WlClient cl)
	{
		writeln("removeClient");
		_clients = _clients.remove!(c => c is cl);
	}
}

int main()
{
	auto display = WlDisplay.create();
	scope(exit) display.destroy();

	environment["WAYLAND_DISPLAY"] = display.addSocketAuto();

	auto comp = new Compositor(display);
	scope(exit) comp.destroy();

	return comp.run();
}
