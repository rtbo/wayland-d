module compositor;

import backend;
import wayland.server;

import std.algorithm;
import std.typecons : Flag;
import std.stdio;
import std.process;


class Compositor : CompositorBackendInterface
{
	private {
		Backend _backend;

		WlDisplay _display;
		WlEventLoop _loop;

		WlClient[] _clients;
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

	void onCompBind(WlClient cl, uint ver, uint id)
	{
		writeln("onCompBind");
		auto res = new WlCompositor.Resource(cl, ver, id);
		res.onCreateSurface = &compCreateSurface;
		res.onCreateRegion = &compCreateRegion;
	}

	void compCreateSurface(WlClient cl, WlCompositor.Resource res, uint id) {
	}

	void compCreateRegion(WlClient cl, WlCompositor.Resource res, uint id) {
	}
}

int main()
{
	auto comp = new Compositor;
	return comp.run();
}
