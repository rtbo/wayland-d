module backend;

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

/// interface that must be implemented by the compositor
/// and supplied to the backend.
/// The backend send events to the compositor using this interface
interface BackendHandler
{
    /// Called when surface must be exposed
    void expose();

    void mouseMove(int x, int y);

    void mouseButton(int button, Flag!"down" down);

    void key(int key, Flag!"down" down);
}

/// interface that must implement backends.
/// The compositor send requests to the backend using this interface.
interface Backend
{
    @property string name();
    @property BackendConfig config();
    @property BackendHandler handler();

    void initialize(BackendConfig config, BackendHandler handler);
    void terminate();

    static Backend create(string name="")
    {
        if (name == "x11" || name == "")
        {
            import backend.x11;
            return new X11Backend;
        }
        return null;
    }
}

