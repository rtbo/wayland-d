module wayland.egl;

import wayland.client;
import wayland.native.egl;
import wayland.util;
import std.typecons : tuple, Tuple;

class WlEglWindow : Native!wl_egl_window
{
    mixin nativeImpl!(wl_egl_window);

    this(WlSurface surf, int width, int height)
    {
        _native = wl_egl_window_create(surf.proxy, width, height);
    }

    void destroy()
    {
        wl_egl_window_destroy(_native);
        _native = null;
    }

    void resize(int width, int height, int dx, int dy)
    {
        wl_egl_window_resize(_native, width, height, dx, dy);
    }

    @property Tuple!(int, int) attachedSize()
    {
        int w = -1, h = -1;
        wl_egl_window_get_attached_size(_native, &w, &h);
        return tuple(w, h);
    }
}
