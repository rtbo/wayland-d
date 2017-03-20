module seat;

import compositor;
import wayland.server;

import std.algorithm;

class Seat : WlSeat
{
    Compositor comp;
    ClPointer[] pointers;

    this(Compositor comp)
    {
        super(comp.display, ver);
        this.comp = comp;
    }

    void mouseButton(WlClient cl, int button, WlPointer.ButtonState state)
    {
        foreach(p; pointers)
        {
            if (p.client is cl)
            {
                auto serial = comp.display.nextSerial();
                auto time = cast(uint)comp.time.total!"msecs";
                p.sendButton(serial, time, button, state);
            }
        }
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
        auto p = new ClPointer(this, cl, id);
        pointers ~= p;
        return p;
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
    Seat seat;

    this(Seat seat, WlClient cl, uint id)
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
    {
        seat.pointers = seat.pointers.remove!(p => p is this);
    }
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
