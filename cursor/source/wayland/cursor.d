module wayland.cursor;

import wayland.native.cursor;
import wayland.client;
import wayland.util;

import std.string;


class WlCursorImage : Native!wl_cursor_image
{
    mixin nativeImpl!(wl_cursor_image);

    this(wl_cursor_image* native)
    {
        _native = native;
    }

    @property uint width()
    {
        return native.width;
    }

    @property uint height()
    {
        return native.height;
    }

    @property uint hotspotX()
    {
        return native.hotspot_x;
    }

    @property uint hotspotY()
    {
        return native.hotspot_y;
    }

    @property uint delay()
    {
        return native.delay;
    }

    @property WlBuffer buffer()
    {
        auto nb = wl_cursor_image_get_buffer(native);
        if (!nb) return null;
        auto buf = cast(WlBuffer)WlProxy.get(nb);
        if (!buf) buf = cast(WlBuffer)WlBuffer.iface.makeProxy(nb);
        return buf;
    }
}

class WlCursor : Native!wl_cursor
{
    mixin nativeImpl!(wl_cursor);

    private WlCursorImage[] _images;

    this(wl_cursor* native)
    {
        _native = native;
    }

    @property string name()
    {
        return fromStringz(native.name).idup;
    }

    @property WlCursorImage[] images()
    {
        import std.array : uninitializedArray;

        if (_images) return _images;

        _images = uninitializedArray!(WlCursorImage[])(native.image_count);
        foreach (i; 0 .. native.image_count)
        {
            _images[i] = new WlCursorImage(native.images[i]);
        }
        return _images;
    }

    int frame(uint time)
    {
        return wl_cursor_frame(native, time);
    }

    int frameAndDuration(uint time, out uint duration)
    {
        return wl_cursor_frame_and_duration(native, time, &duration);
    }
}

class WlCursorTheme : Native!wl_cursor_theme
{
    mixin nativeImpl!(wl_cursor_theme);

    this(wl_cursor_theme* native)
    {
        _native = native;
    }

    static WlCursorTheme load(string name, size_t size, WlShm shm)
    {
        auto nn = name.length ? toStringz(name) : null;
        auto ct = wl_cursor_theme_load(nn, cast(int)size, shm.proxy);
        return ct ? new WlCursorTheme(ct) : null;
    }

    void destroy()
    {
        wl_cursor_theme_destroy(native);
    }

    WlCursor cursor(string name)
    {
        auto cp = wl_cursor_theme_get_cursor(native, toStringz(name));
        return cp ? new WlCursor(cp) : null;
    }

}

version(WlDynamic)
{
    import derelict.util.loader : SharedLibLoader;

    private class WlCursorLoader : SharedLibLoader
    {
        this()
        {
            super("libwayland-cursor.so");
        }

        protected override void loadSymbols()
        {
            bindFunc( cast( void** )&wl_cursor_theme_load, "wl_cursor_theme_load" );
            bindFunc( cast( void** )&wl_cursor_theme_destroy, "wl_cursor_theme_destroy" );
            bindFunc( cast( void** )&wl_cursor_theme_get_cursor, "wl_cursor_theme_get_cursor" );
            bindFunc( cast( void** )&wl_cursor_image_get_buffer, "wl_cursor_image_get_buffer" );
            bindFunc( cast( void** )&wl_cursor_frame, "wl_cursor_frame" );
            bindFunc( cast( void** )&wl_cursor_frame_and_duration, "wl_cursor_frame_and_duration" );
        }
    }

    private __gshared WlCursorLoader _loader;

    shared static this()
    {
        _loader = new WlCursorLoader;
    }

    public @property SharedLibLoader wlCursorDynLib()
    {
        return _loader;
    }
}

