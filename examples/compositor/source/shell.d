module shell;

import compositor;
import wayland.server;

class Shell : WlShell
{
    Compositor comp;

    this(Compositor comp)
    {
        super(comp.display, ver);
        this.comp = comp;
    }

    override WlShellSurface getShellSurface(WlClient cl, Resource res, uint id, WlSurface surf)
    {
        return new ShellSurface(cl, id, surf);
    }
}


class ShellSurface : WlShellSurface
{
    WlSurface surf;

    this(WlClient cl, uint id, WlSurface surf)
    {
        super(cl, ver, id);
        this.surf = surf;
    }

    override protected void pong(WlClient cl,
                                 uint serial)
    {}

    override protected void move(WlClient cl,
                                 WlSeat.Resource seat,
                                 uint serial)
    {}

    override protected void resize(WlClient cl,
                                   WlSeat.Resource seat,
                                   uint serial,
                                   Resize edges)
    {}


    override protected void setToplevel(WlClient cl)
    {}

    override protected void setTransient(WlClient cl,
                                         WlSurface parent,
                                         int x,
                                         int y,
                                         Transient flags)
    {}

    override protected void setFullscreen(WlClient cl,
                                          FullscreenMethod method,
                                          uint framerate,
                                          WlOutput.Resource output)
    {}

    override protected void setPopup(WlClient cl,
                                     WlSeat.Resource seat,
                                     uint serial,
                                     WlSurface parent,
                                     int x,
                                     int y,
                                     Transient flags)
    {}

    override protected void setMaximized(WlClient cl,
                                         WlOutput.Resource output)
    {}

    override protected void setTitle(WlClient cl,
                                     string title)
    {}

    override protected void setClass(WlClient cl,
                                     string class_)
    {}

}
