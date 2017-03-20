module backend;

import output;
import compositor;
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


    void initialize(BackendConfig config, Compositor comp);

    Output createOutput();

    void terminate();
}
