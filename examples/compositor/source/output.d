module output;

import wayland.server;

class Output
{
    private WlDisplay dpy;
    private WlOutput.Global glob;

    this(WlDisplay dpy)
    {
        this.dpy = dpy;
    }

    abstract @property int width();
    abstract @property int height();

    @property bool enabled()
    {
        return glob !is null;
    }

    void enable()
    {
        glob = new WlOutput.Global(dpy, 3, &onOutputBind);
    }

    void disable()
    {
        glob.destroy();
    }

    private void onOutputBind(WlClient cl, uint ver, uint id)
    {}
}
