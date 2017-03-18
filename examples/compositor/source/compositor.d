module compositor;

import backend;
import wayland.server;
import wayland.server.shm;

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

	override Resource bind(WlClient cl, uint ver, uint id)
	{
		writeln("onCompBind");
		auto res = new Resource(cl, ver, id);
		res.onCreateSurface = &createSurface;
		res.onCreateRegion = &createRegion;
		return res;
	}

	private WlSurface createSurface(WlClient cl, Resource res, uint id) {
		return new Surface(this, cl, id);
	}

	private WlRegion createRegion(WlClient cl, Resource res, uint id) {
		return null;
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

class Buffer : WlBuffer
{
	WlShmBuffer shmBuffer;
	int width;
	int height;

	this(WlClient cl, uint id) {
		super(cl, WlBuffer.ver, id);
	}

	override protected void destroy(WlClient cl)
	{}
}

class Surface : WlSurface
{
	Compositor comp;

	this(Compositor comp, WlClient cl, uint id) {
		this.comp = comp;
		super(cl, WlSurface.ver, id);
	}

	override protected void destroy(WlClient cl)
	{}

    override protected void attach(WlClient cl,
                                   WlBuffer buffer,
                                   int x,
                                   int y)
	{}

    override protected void damage(WlClient cl,
                                   int x,
                                   int y,
                                   int width,
                                   int height)
	{}

    override protected WlCallback frame(WlClient cl,
                                  	   	uint callback)
	{
		return null;
	}

    override protected void setOpaqueRegion(WlClient cl,
                                            WlRegion region)
	{}

    override protected void setInputRegion(WlClient cl,
                                           WlRegion region)
	{}

    override protected void commit(WlClient cl)
	{}

    override protected void setBufferTransform(WlClient cl,
                                               int transform)
	{}

    override protected void setBufferScale(WlClient cl,
                                           int scale)
	{}

    override protected void damageBuffer(WlClient cl,
                                         int x,
                                         int y,
                                         int width,
                                         int height)
	{}
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
