module wayland.client.core;

import wayland.native.client;
import wayland.client.protocol : WlDisplay;
import wayland.util;


class WlEventQueue : Native!wl_event_queue
{
    mixin nativeImpl!(wl_event_queue);
    this(wl_event_queue* native)
    {
        _native = native;
    }
}


abstract class WlDisplayBase : WlProxy, Native!wl_display
{
    protected this(wl_display* native)
    {
        super(cast(wl_proxy*)native);
    }

    static WlDisplay connect(in string name = null)
    {
        import std.string : toStringz;
        const(char)* displayName = name.length ? toStringz(name) : null;
        auto nativeDpy = wl_display_connect(displayName);
        return nativeDpy ? new WlDisplay(nativeDpy) : null;
    }

    static WlDisplay connectToFd(in int fd)
    {
        auto nativeDpy = wl_display_connect_to_fd(fd);
        return nativeDpy ? new WlDisplay(nativeDpy) : null;
    }

    final override @property inout(wl_display)* native() inout
    {
        return cast(inout(wl_display)*)(proxy);
    }

    final void disconnect()
    {
        return wl_display_disconnect(native);
    }

    final int getFd()
    {
        return wl_display_get_fd(native);
    }

    final int dispatch()
    {
        return wl_display_dispatch(native);
    }

    final int dispatchPending()
    {
        return wl_display_dispatch_pending(native);
    }

    final int dispatchQueue(WlEventQueue queue)
    {
        return wl_display_dispatch_queue(native, queue.native);
    }

    final int dispatchQueuePending(WlEventQueue queue)
    {
        return wl_display_dispatch_queue_pending(native, queue.native);
    }

    final int getError()
    {
        return wl_display_get_error(native);
    }

    //uint wl_display_get_protocol_error(wl_display* display, const(wl_interface)** iface, uint* id);

    final int flush()
    {
        return wl_display_flush(native);
    }

    final int roundtripQueue(WlEventQueue queue)
    {
        return wl_display_roundtrip_queue(native, queue.native);
    }

    final int roundtrip()
    {
        return wl_display_roundtrip(native);
    }

    final WlEventQueue createQueue()
    {
        return new WlEventQueue(wl_display_create_queue(native));
    }

    final int prepareReadQueue(WlEventQueue queue)
    {
        return wl_display_prepare_read_queue(native, queue.native);
    }

    final int prepareRead()
    {
        return wl_display_prepare_read(native);
    }

    final void cancelRead()
    {
        wl_display_cancel_read(native);
    }

    final int readEvents()
    {
        return wl_display_read_events(native);
    }
}


abstract class WlProxy
{
    private wl_proxy* _proxy;

    protected this(wl_proxy* proxy)
    {
        _proxy = proxy;
    }

    protected final @property inout(wl_proxy)* proxy() inout
    {
        return _proxy;
    }

    abstract @property uint version_();
}
