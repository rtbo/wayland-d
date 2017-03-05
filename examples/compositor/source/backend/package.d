module backend;

import output;
import wayland.server;

import std.typecons : Flag;

class BackendConfig
{
    this(bool fs, int w, int h)
    {
        fullscreen = fs;
        width = w;
        height = h;
    }

    bool fullscreen;
    // used if not fullscreen
    int width, height;
}

/// Interface that must be implemented by the compositor and supplied to the
/// backend. The backend send events and request data to the compositor using
/// this interface.
interface CompositorBackendInterface
{
    @property WlDisplay display();


    void eventExpose();

    void eventMouseMove(int x, int y);

    void eventMouseButton(int button, Flag!"down" down);

    void eventKey(int key, Flag!"down" down);
}

/// Interface that must implement backends.
/// The compositor send requests to the backend using this interface.
interface Backend
{
    /// Creates backend with specified name.
    /// If name is empty, default backend is created.
    static Backend create(string name="")
    {
        if (name == "x11" || name == "")
        {
            import backend.x11;
            return new X11Backend;
        }
        return null;
    }

    /// Name of the backend.
    @property string name();


    void initialize(BackendConfig config, CompositorBackendInterface comp);

    Output createOutput();

    void terminate();
}
