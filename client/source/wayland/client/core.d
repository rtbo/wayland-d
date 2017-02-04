module wayland.client.core;

import wayland.native.client;
import wayland.util;


class WlEventQueue : Native!wl_event_queue
{
    mixin nativeImpl!(wl_event_queue);
    this(wl_event_queue* native)
    {
        _native = native;
    }
}


class WlDisplayBase : WlProxy, Native!wl_display
{
    private this(wl_display* native)
    {
        super(cast(wl_proxy*)native);
    }

    final override @property wl_display* native()
    {
        return cast(wl_display*)(proxy);
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


class WlProxy
{
    private wl_proxy* _proxy;

    protected this(wl_proxy* proxy)
    {
        _proxy = proxy;
    }

    protected final @property wl_proxy* proxy()
    {
        return _proxy;
    }
}
