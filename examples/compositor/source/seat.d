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
        auto res = new Resource(cl, ver, id);
        res.onGetPointer = &getPointer;
        res.onGetKeyboard = &getKeyboard;

        res.sendCapabilities(Capability.pointer | Capability.keyboard);
        if (ver >= nameSinceVersion) {
            res.sendName("seat");
        }
        return res;
    }

    private WlPointer getPointer(WlClient cl, Resource res, uint id)
    {
        return new ClPointer(cl, id);
    }

    private WlKeyboard getKeyboard(WlClient cl, Resource res, uint id)
    {
        return new ClKeyboard(cl, id);
    }
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
