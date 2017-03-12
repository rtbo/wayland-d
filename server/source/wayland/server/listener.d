module wayland.server.listener;

import wayland.native.server;
import wayland.native.util;
import wayland.util;


class WlListener : Native!wl_listener
{
    alias NotifyDg = void delegate(void* data);

    private wl_listener _native;
    private NotifyDg _notify;

    this()
    {
        wl_list_init(&_native.link);
        _native.notify = &wl_d_listener_notify;
    }

    this(NotifyDg notify)
    {
        this();
        _notify = notify;
    }

    @property inout(wl_listener*) native() inout
    {
        return &_native;
    }

    @property NotifyDg notify()
    {
        return _notify;
    }

    @property void notify(NotifyDg notify)
    {
        _notify = notify;
    }
}

class WlSignal : Native!wl_signal
{
    private wl_signal _native;
    WlListener[] _listeners;

    this()
    {
        wl_signal_init(&_native);
    }

    @property inout(wl_signal*) native() inout
    {
        return &_native;
    }

    void add(WlListener listener)
    {
        wl_signal_add(native, listener.native);
        _listeners ~= listener;
    }

    WlListener get(WlListener.NotifyDg notify)
    {
        foreach(l; _listeners)
        {
            if (l._notify is notify)
            {
                return l;
            }
        }
        return null;
    }

    void emit(void* data)
    {
        wl_signal_emit(native, data);
    }
}

class Signal(Args...)
{
    alias Listener = void delegate(Args args);

    private Listener[] _listeners;

    this() {}

    void add(Listener listener)
    {
        _listeners ~= listener;
    }

    void emit(Args args)
    {
        foreach(l; _listeners)
        {
            l(args);
        }
    }
}

private extern(C) nothrow
{
    void wl_d_listener_notify(wl_listener* l, void* data)
    {
        nothrowFnWrapper!({
            auto dl = cast(WlListener)(
                cast(void*)l - WlListener._native.offsetof
            );
            assert(dl && (l is &dl._native));
            if (dl._notify) dl._notify(data);
        });
    }
}
