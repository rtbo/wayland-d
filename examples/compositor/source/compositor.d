module compositor;

import backend;
import seat;
import shell;
import output;
import wayland.server;
import wayland.server.shm;
import wayland.native.server;

import std.algorithm;
import std.typecons : Flag;
import std.stdio;
import std.process;
import std.format;
import std.exception;
import core.time;


class Compositor : WlCompositor
{
	private {
		WlDisplay _display;

		Backend _backend;
		Seat _seat;
		Shell _shell;

		WlClient[] _clients;
		Output[] _outputs;
		uint _outputMaskShift;

		MonoTime _startTime;
	}

	this(WlDisplay display)
	{
		this._display = display;
		super(display, ver);
		_seat = new Seat(this);
		_shell = new Shell(this);
		_startTime = MonoTime.currTime;
	}

	@property Duration time()
	{
		return MonoTime.currTime - _startTime;
	}

	@property WlDisplay display()
	{
		return _display;
	}

	@property Output[] outputs()
	{
		return _outputs;
	}

	@property Shell shell()
	{
		return _shell;
	}

	@property Seat seat()
	{
		return _seat;
	}

	void addOutput(Output output)
	{
		_outputMaskShift += 1;
		output.mask = 1 << _outputMaskShift;
		_outputs ~= output;
	}

	void exit()
	{
		_display.terminate();
	}

    void eventExpose()
	{}

    void eventMouseMove(int x, int y)
	{}

    void eventMouseButton(int x, int y, int button, WlPointer.ButtonState state)
	{
		_shell.mouseButton(x, y, button, state);
	}

    void eventKey(int key, Flag!"down" down)
	{}

	void scheduleRepaint()
	{
		foreach (o; _outputs) {
			o.scheduleRepaint();
		}
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

private:

	int run()
	{
		_display.initShm();

		_backend = Backend.create();
		_backend.initialize(new BackendConfig(false, 640, 480), this);
		scope(exit) _backend.terminate();

		addOutput(_backend.createOutput());

		auto timer = _display.eventLoop.addTimer({
			spawnProcess([
				"wayland-tracker", "simple",
				"-x", "protocol/wayland.xml",
				"--", "examples/hello/wayland_hello"
			]);
			return 1;
		});
		timer.update(1000);

		_display.addClientCreatedListener(&addClient);

		scheduleRepaint();

		_display.run();

		return 0;
	}

	void addClient(WlClient cl)
	{
		_clients ~= cl;
		cl.addDestroyListener(&removeClient);
		// Some interfaces are implemented by libwayland-server (i.e. wl_shm, wl_shm_pool).
		// Therefore, some resources are not created in the D code stack.
		// Here we listen for the creation of buffer and wrap them with a D object.
		cl.addNativeResourceCreatedListener((wl_resource* natRes) {
			import core.stdc.string : strcmp;
			if (strcmp(wl_resource_get_class(natRes), "wl_buffer") == 0) {
				new Buffer(natRes);
			}
		});
	}

	void removeClient(WlClient cl)
	{
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
	size_t stride;
	WlShm.Format format;

	this(wl_resource* natRes) {
		super(natRes);
	}

	void fetch()
	{
		shmBuffer = enforce(WlShmBuffer.get(this));
		width = shmBuffer.width;
		height = shmBuffer.height;
		stride = shmBuffer.stride;
		format = shmBuffer.format;
	}

	void[] beginAccess()
	{
		shmBuffer.beginAccess();
		return shmBuffer.data();
	}

	void endAccess()
	{
		shmBuffer.endAccess();
	}

	// WlBuffer

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

	void flushTo(SurfaceState state)
	{
		state.newlyAttached = newlyAttached;
		state.x = x;
		state.y = y;
		state.buffer = buffer;
		state.damageReg = damageReg;
		state.damageBufferReg = damageBufferReg;
		state.opaqueReg = opaqueReg;
		state.inputReg = inputReg;
	}
}

class AlreadyAssignedRoleException : Exception
{
	this(string oldRole, string newRole)
	{
		super(format("Surface role already assigned: was '%s', tentative to assign '%s'.", oldRole, newRole));
	}
}

class Surface : WlSurface
{
	private Compositor _comp;
	private SurfaceState _pending;
	private SurfaceState _state;
	private string _role;
	private uint _outputMask;

	this(Compositor comp, WlClient cl, uint id) {
		_comp = comp;
		_pending = new SurfaceState;
		_state = new SurfaceState;
		super(cl, WlSurface.ver, id);
	}

	@property SurfaceState state()
	{
		return _state;
	}

	@property string role()
	{
		return _role;
	}

	void assignRole(string role)
	{
		if (_role.length && _role != role)
		{
			throw new AlreadyAssignedRoleException(_role, role);
		}
	}

	@property uint outputMask()
	{
		return _outputMask;
	}

	@property void outputMask(uint mask)
	{
		_outputMask = mask;
	}

	void scheduleRepaint()
	{
		foreach (o; _comp.outputs)
		{
			if (_outputMask & o.mask) {
				o.scheduleRepaint();
			}
		}
	}

	// WlSurface

	override protected void destroy(WlClient cl)
	{

	}

    override protected void attach(WlClient cl,
                                   WlBuffer buffer,
                                   int x,
                                   int y)
	{
		auto b = cast(Buffer)buffer;
		_pending.buffer = b;
		_pending.newlyAttached = true;
		_pending.x = x;
		_pending.y = y;
		if (b) b.fetch();
	}

    override protected void damage(WlClient cl,
                                   int x,
                                   int y,
                                   int width,
                                   int height)
	{
		_pending.damageReg ~= Rect(x, y, width, height);
	}

    override protected WlCallback frame(WlClient cl,
                                  	   	uint callback)
	{
		return null;
	}

    override protected void setOpaqueRegion(WlClient cl,
                                            WlRegion region)
	{
		_pending.opaqueReg = (cast(Region)region).rects;
	}

    override protected void setInputRegion(WlClient cl,
                                           WlRegion region)
	{
		_pending.inputReg = (cast(Region)region).rects;
	}

    override protected void commit(WlClient cl)
	{
		_pending.flushTo(_state);
		scheduleRepaint();
	}

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
	{
		_pending.damageBufferReg ~= Rect(x, y, width, height);
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
