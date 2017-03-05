module compositor;

import backend;
import wayland.server;

import std.typecons : Flag;
import core.thread;
import core.time;

class Compositor : CompositorBackendInterface
{
	private {
		Backend _backend;

		WlDisplay _display;
		WlEventLoop _loop;
	}

	override @property WlDisplay display()
	{
		return _display;
	}

    override void eventExpose()
	{}

    override void eventMouseMove(int x, int y)
	{}

    override void eventMouseButton(int button, Flag!"down" down)
	{}

    override void eventKey(int key, Flag!"down" down)
	{}

	int run()
	{
		_display = WlDisplay.create();
		_backend = Backend.create();
		_backend.initialize(new BackendConfig(false, 640, 480), this);

		auto output = _backend.createOutput();
		output.enable();

		_display.run();

		output.disable();
		_backend.terminate();
		_display.destroy();
		return 0;
	}
}


int main()
{
	auto comp = new Compositor;
	return comp.run();
}
