module compositor;

import backend;
import wayland.server;

import std.typecons : Flag;
import core.thread;
import core.time;

class Compositor : BackendHandler
{
	Backend backend;

    override void expose()
	{}

    override void mouseMove(int x, int y)
	{}

    override void mouseButton(int button, Flag!"down" down)
	{}

    override void key(int key, Flag!"down" down)
	{}

	int run()
	{
		backend = Backend.create();
		backend.initialize(new BackendConfig(false, 1024, 768), this);
		Thread.sleep(dur!"msecs"(1000));
		backend.terminate();
		return 0;
	}
}


int main()
{
	auto comp = new Compositor;
	return comp.run();
}
