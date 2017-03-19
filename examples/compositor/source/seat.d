module seat;

import compositor;
import wayland.server;

class Seat : WlSeat
{
    Compositor comp;

    this(Compositor comp)
    {
        super(comp.display, ver);
    }

    override Resource bind(WlClient cl, uint ver, uint id)
    {
        auto res = super.bind(cl, ver, id);

        res.sendCapabilities(Capability.pointer | Capability.keyboard);
        if (ver >= nameSinceVersion) {
            res.sendName("seat");
        }
        return res;
    }

    override WlPointer getPointer(WlClient cl, Resource res, uint id)
    {
        return new ClPointer(cl, id);
    }

    override WlTouch getTouch(WlClient cl, Resource res, uint id)
    {
        return null;
    }

    override WlKeyboard getKeyboard(WlClient cl, Resource res, uint id)
    {
        return new ClKeyboard(cl, id);
    }

    override void release(WlClient cl, Resource res)
    {}
}

class ClPointer : WlPointer
{
    this(WlClient cl, uint id)
    {
        super(cl, ver, id);
    }

    override protected void setCursor(WlClient cl,
                                      uint serial,
                                      WlSurface surface,
                                      int hotspotX,
                                      int hotspotY)
    {}


    override protected void release(WlClient cl)
    {}
}

class ClKeyboard : WlKeyboard
{
    this(WlClient cl, uint id)
    {
        super(cl, ver, id);
    }

    override protected void release(WlClient cl)
    {}
}
