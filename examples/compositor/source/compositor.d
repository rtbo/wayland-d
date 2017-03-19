module compositor;

import backend;
import seat;
import shell;
import wayland.server;
import wayland.server.shm;

import std.algorithm;
import std.typecons : Flag;
import std.stdio;
import std.process;


class Compositor : WlCompositor, CompositorBackendInterface
{
	private {
		WlDisplay _display;
		WlEventLoop _loop;

		Backend _backend;
		Seat _seat;
		Shell _shell;

		WlClient[] _clients;
	}

	this(WlDisplay display)
	{
		this._display = display;
		super(display, ver);
		_seat = new Seat(this);
		_shell = new Shell(this);
	}

	// WlCompositor

	override WlSurface createSurface(WlClient cl, Resource, uint id)
	{
		return new Surface(this, cl, id);
	}

	override WlRegion createRegion(WlClient cl, Resource, uint id)
	{
		return new Region(cl, id);
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
				"--", "examples/hello/wayland-d_hello"
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

struct Rect {
	int x; int y; int width; int height;
}

// dumbest possible region implementation
class Region : WlRegion
{
	Rect[] rects;

	this(WlClient cl, int id)
    {
        super(cl, WlRegion.ver, id);
    }

	override protected void destroy(WlClient cl)
	{}

    override protected void add(WlClient cl,
                                int x,
                                int y,
                                int width,
                                int height)
	{
		// add without checking for interference
		rects ~= Rect(x, y, width, height);
	}

    override protected void subtract(WlClient cl,
                                     int x,
                                     int y,
                                     int width,
                                     int height)
	{
		// naive tentative. no complex algo to refont the rect list
		immutable rs = Rect(x, y, width, height);
		foreach (i, r; rects) {
			if (r == rs) {
				rects = rects.remove(i);
				return;
			}
		}
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

class SurfaceState
{
	// attach
	bool newlyAttached;
	int x; int y;
	Buffer buffer;

	// damage
	Rect[] damageReg;
	// damageBuffer
	Rect[] damageBufferReg;
	// setOpaqueRegion
	Rect[] opaqueReg;
	// setInputRegion
	Rect[] inputReg;

}


class Surface : WlSurface
{
	Compositor comp;
	SurfaceState pending;

	this(Compositor comp, WlClient cl, uint id) {
		this.comp = comp;
		super(cl, WlSurface.ver, id);
		pending = new SurfaceState;
	}

	override protected void destroy(WlClient cl)
	{}

    override protected void attach(WlClient cl,
                                   WlBuffer buffer,
                                   int x,
                                   int y)
	{
		pending.buffer = cast(Buffer)buffer;
		pending.newlyAttached = true;
		pending.x = x;
		pending.y = y;
	}

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
