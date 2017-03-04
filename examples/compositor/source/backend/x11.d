module backend.x11;

import backend;

import xcb.xcb;
import xcb.xkb;
import X11.Xlib;
import X11.Xlib_xcb;
import xkbcommon.xkbcommon;
import xkbcommon.x11;

final class X11Backend : Backend
{
    BackendConfig _config;
    BackendHandler _handler;

    override @property string name()
    {
        return "x11";
    }

    override @property BackendConfig config()
    {
        return _config;
    }

    override @property BackendHandler handler()
    {
        return _handler;
    }

    override void initialize(BackendConfig config, BackendHandler handler)
    {
        _config = config;
        _handler = handler;
    }

    override void terminate()
    {

    }
}
