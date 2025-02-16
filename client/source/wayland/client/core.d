// Copyright © 2017-2021 Rémi Thebault
module wayland.client.core;

import core.memory : GC;

import wayland.client.protocol : WlDisplay;
import wayland.native.client;
import wayland.native.util;
import wayland.util;

/++
 + A queue for WlProxy object events.
 +
 + Event queues allows the events on a display to be handled in a thread-safe
 + manner. See WlDisplay for details.
 +/
class WlEventQueue : Native!wl_event_queue
{
    mixin nativeImpl!(wl_event_queue);
    this(wl_event_queue* native)
    {
        _native = native;
    }
}

/++
 + Represents a connection to the compositor and acts as a proxy to
 + the wl_display singleton object.
 +
 + A WlDisplay object represents a client connection to a Wayland
 + compositor. It is created with either WlDisplay.connect(), 
 + WlDisplay.connectToFd() or WlDisplay.fromNative().
 + A connection is terminated using disconnect().
 +
 + A WlDisplay is also used as the WlProxy for the wl_display
 + singleton object on the compositor side.
 +
 + A WlDisplay object handles all the data sent from and to the
 + compositor. When a WlProxy marshals a request, it will write its wire
 + representation to the display's write buffer. The data is sent to the
 + compositor when the client calls WlDisplay.flush().
 +
 + Incoming data is handled in two steps: queueing and dispatching. In the
 + queue step, the data coming from the display fd is interpreted and
 + added to a queue. On the dispatch step, the handler for the incoming
 + event set by the client on the corresponding WlProxy is called.
 +
 + A WlDisplay has at least one event queue, called the <em>default
 + queue</em>. Clients can create additional event queues with
 + WlDisplay.createQueue() and assign WlProxy's to it. Events
 + occurring in a particular proxy are always queued in its assigned queue.
 + A client can ensure that a certain assumption, such as holding a lock
 + or running from a given thread, is true when a proxy event handler is
 + called by assigning that proxy to an event queue and making sure that
 + this queue is only dispatched when the assumption holds.
 +
 + The default queue is dispatched by calling WlDisplay.dispatch().
 + This will dispatch any events queued on the default queue and attempt
 + to read from the display fd if it's empty. Events read are then queued
 + on the appropriate queues according to the proxy assignment.
 +
 + A user created queue is dispatched with WlDisplay.dispatchQueue().
 + This function behaves exactly the same as WlDisplay.dispatch()
 + but it dispatches given queue instead of the default queue.
 +
 + A real world example of event queue usage is Mesa's implementation of
 + eglSwapBuffers() for the Wayland platform. This function might need
 + to block until a frame callback is received, but dispatching the default
 + queue could cause an event handler on the client to start drawing
 + again. This problem is solved using another event queue, so that only
 + the events handled by the EGL code are dispatched during the block.
 +
 + This creates a problem where a thread dispatches a non-default
 + queue, reading all the data from the display fd. If the application
 + would call \em poll(2) after that it would block, even though there
 + might be events queued on the default queue. Those events should be
 + dispatched with WlDisplay.dispatchPending() or
 + WlDisplay.dispatchQueuePending() before flushing and blocking.
 +/
abstract class WlDisplayBase : WlProxy, Native!wl_display
{
    protected this(wl_display* native)
    {
        super(cast(wl_proxy*)native);
    }

    static WlDisplay connect(in string name = null)
    {
        import std.exception : enforce, ErrnoException;
        import std.string : toStringz;

        const(char)* displayName = name.length ? toStringz(name) : null;
        auto nativeDpy = enforce!ErrnoException(
            wl_display_connect(displayName),
            "Could not get a display handle from Wayland"
        );
        return new WlDisplay(nativeDpy);
    }

    static WlDisplay connectToFd(in int fd)
    {
        auto nativeDpy = wl_display_connect_to_fd(fd);
        return nativeDpy ? new WlDisplay(nativeDpy) : null;
    }

    /++
     +  Construct a WlDisplay from a native handle.
     +  Useful for interaction with 3rd party libraries (e.g. GLFW)
     +  that handle the connection.
     +/ 
    static WlDisplay fromNative(wl_display* nativeDpy)
    {
        return new WlDisplay(nativeDpy);
    }

    final override @property inout(wl_display)* native() inout
    {
        return cast(inout(wl_display)*)(proxy);
    }

    final void disconnect()
    {
        wl_display_disconnect(native);
        WlProxy.destroyNotify();
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

    final immutable(WlInterface) getProtocolError(out uint code, out uint id)
    {
        const(wl_interface)* iface = null;
        code = wl_display_get_protocol_error(native, &iface, &id);
        if (iface) {
            return new immutable WlInterface(cast(immutable)iface);
        }
        else {
            return null;
        }
    }

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

/// Wrapper around wl_proxy and base class for types generated by the protocol.
abstract class WlProxy
{
    private wl_proxy* _proxy;
    private void* _userData;

    protected this(wl_proxy* proxy)
    {
        _proxy = proxy;
        void* thisHandle = cast(void*) this;
        wl_proxy_set_user_data(proxy, thisHandle);
        GC.addRoot(thisHandle);
        GC.setAttr(thisHandle, GC.BlkAttr.NO_MOVE);
    }

    protected void destroyNotify()
    {
        _proxy = null;
        // destroy(this); // HACK no destructor is implemented so we can skip that.
        GC.free(cast(void*) this);
    }

    static WlProxy get(wl_proxy* proxy)
    {
        return cast(WlProxy) wl_proxy_get_user_data(proxy);
    }

    final @property inout(wl_proxy)* proxy() inout
    {
        return _proxy;
    }

    /// Get the protocol version of WlDisplay.
    final @property uint ver()
    {
        return wl_proxy_get_version(proxy);
    }

    /// Get the id assigned to this object.
    final @property uint id()
    {
        return wl_proxy_get_id(proxy);
    }

    /// Get the class of this object.
    final @property string class_()
    {
        import std.string : fromStringz;
        return fromStringz(wl_proxy_get_class(proxy)).idup;
    }

    final @property void userData(void* value)
    {
        _userData = value;
    }

    final @property void* userData()
    {
        return _userData;
    }
}

immutable abstract class WlProxyInterface : WlInterface
{
    this(immutable wl_interface* native)
    {
        super(native);
    }

    abstract WlProxy makeProxy(wl_proxy* proxy) immutable;
}
