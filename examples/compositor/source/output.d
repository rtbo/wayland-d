module output;

import wayland.server;


class Output : WlOutput
{
    private WlDisplay dpy;
    private WlOutput glob;

    this(WlDisplay dpy)
    {
        this.dpy = dpy;
        super(dpy, 3);
    }

    abstract @property int width();
    abstract @property int height();

    override void release(WlClient cl, Resource res)
    {}
}
