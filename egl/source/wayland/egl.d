module wayland.egl;

import wayland.client;
import wayland.native.egl;
import wayland.util;

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

    @property int[2] attachedSize()
    {
        int[2] wh = -1;
        wl_egl_window_get_attached_size(_native, &wh[0], &wh[1]);
        return wh;
    }
}

version(WlDynamic)
{
    import derelict.util.loader : SharedLibLoader;

    private class WlEglLoader : SharedLibLoader
    {
        this()
        {
            super("libwayland-egl.so");
        }

        protected override void loadSymbols()
        {
            bindFunc( cast( void** )&wl_egl_window_create, "wl_egl_window_create" );
            bindFunc( cast( void** )&wl_egl_window_destroy, "wl_egl_window_destroy" );
            bindFunc( cast( void** )&wl_egl_window_resize, "wl_egl_window_resize" );
            bindFunc( cast( void** )&wl_egl_window_get_attached_size, "wl_egl_window_get_attached_size" );
        }
    }

    private __gshared WlEglLoader _loader;

    shared static this()
    {
        _loader = new WlEglLoader;
    }

    public @property SharedLibLoader wlEglDynLib()
    {
        return _loader;
    }
}
