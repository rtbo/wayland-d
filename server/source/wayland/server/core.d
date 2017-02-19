// Copyright © 2017 Rémi Thebault
module wayland.server.core;

import wayland.native.server;
import wayland.util;

import std.string;


class WlDisplayBase : Native!wl_display
{
    mixin nativeImpl!(wl_display);

    alias DestroyDg = void delegate();
    alias ClientCreatedDg = void delegate(WlClient);

    // one loop per display, so no need to use an object store
    private WlEventLoop _loop;

    private DestroyDg _destroyDg;
    private ClientCreatedDg _clientCreatedDg;

    private WlClient[] _clients;


    static WlDisplayBase create()
    {
        // FIXME: instantiate the protocol object
        auto natDpy = wl_display_create();
        auto dpy = new WlDisplayBase(natDpy);

        ObjectCache.set(natDpy, dpy);

        wl_display_add_destroy_listener(natDpy, &displayDestroyListener);
        wl_display_add_client_created_listener(natDpy, &clientCreatedListener);

        return dpy;
    }

    protected this (wl_display* native)
    {
        _native = native;
    }

    void destroy()
    {
        wl_display_destroy(native);
        assert(!ObjectCache.get(native));
        _native = null;
        _destroyDg = null;
        _clientCreatedDg = null;
    }

    @property void onDestroy(DestroyDg dg)
    {
        _destroyDg = dg;
    }

    @property void onClientCreated(ClientCreatedDg dg)
    {
        _clientCreatedDg = dg;
    }

    @property WlEventLoop eventLoop()
    {
        if (!_loop) _loop = new WlEventLoop(wl_display_get_event_loop(native));
        return _loop;
    }

    int addSocket(string name)
    {
        return wl_display_add_socket(native, toStringz(name));
    }

    string addSocketAuto()
    {
        return fromStringz(wl_display_add_socket_auto(native)).idup;
    }

    int addSocketFd(int fd)
    {
        return wl_display_add_socket_fd(native, fd);
    }

    void terminate()
    {
        wl_display_terminate(native);
    }

    void run()
    {
        wl_display_run(native);
    }

    void flushClients()
    {
        wl_display_flush_clients(native);
    }

    @property uint serial()
    {
        return wl_display_get_serial(native);
    }

    uint nextSerial()
    {
        return wl_display_next_serial(native);
    }

    @property void destroyListener(DestroyDg dg)
    {
        _destroyDg = dg;
    }

    WlClient createClient(int fd)
    {
        auto natCl = wl_client_create(native, fd);
        WlClient cl = cast(WlClient)ObjectCache.get(natCl);
        assert(cl, "could not retrieve client from obj cache");
        return cl;
    }

    @property WlClient[] clients()
    {
        return _clients;
    }

    private void registerNewClient(wl_client* natCl)
    {
        auto cl = new WlClient(natCl);
        ObjectCache.set(natCl, cl);
        _clients ~= cl;
        if (_clientCreatedDg) _clientCreatedDg(cl);
    }

    private void unregisterClient(wl_client* natCl)
    {
        import std.algorithm : remove;
        WlClient cl = cast(WlClient)ObjectCache.get(natCl);
        assert(cl, "could not retrieve client from obj cache");
        if (cl._onDestroy) cl._onDestroy(cl);
        _clients = _clients.remove!(c => c is cl);
        ObjectCache.remove(natCl);
    }
}


class WlEventLoop : Native!wl_event_loop
{
    mixin nativeImpl!(wl_event_loop);

    alias DestroyDg = void delegate(WlEventLoop loop);
    nothrow
    {
        alias FdDg = int delegate (int fd, uint mask);
        alias TimerDg = int delegate ();
        alias SignalDg = int delegate (int sigNum);
        alias IdleDg = void delegate ();
    }

    private DestroyDg _destroyDg;

    this (wl_event_loop* native)
    {
        _native = native;
        ObjectCache.set(native, this);
        wl_event_loop_add_destroy_listener(native, &evLoopDestroyListener);
    }

    this()
    {
        this(wl_event_loop_create());
    }

    void destroy()
    {
        wl_event_loop_destroy(_native);
        assert(!ObjectCache.get(native));
        _destroyDg = null;
        _native = null;
    }

    @property void destroyListener(DestroyDg dg)
    {
        _destroyDg = dg;
    }

    @property int fd()
    {
        return wl_event_loop_get_fd(native);
    }

    int dispatch(int timeout)
    {
        return wl_event_loop_dispatch(native, timeout);
    }

    void dispatchIdle()
    {
        wl_event_loop_dispatch_idle(native);
    }

    WlFdEventSource addFd(int fd, uint mask, FdDg dg)
    {
        return new WlFdEventSource(
            wl_event_loop_add_fd (
                native, fd, mask, &eventLoopFdFunc, &dg
            ),
            fd, dg
        );
    }

    WlTimerEventSource addTimer(TimerDg dg)
    {
        return new WlTimerEventSource(
            wl_event_loop_add_timer(
                native, &eventLoopTimerFunc, &dg
            ),
            dg
        );
    }

    WlSignalEventSource addSignal(int signalNum, SignalDg dg)
    {
        return new WlSignalEventSource(
            wl_event_loop_add_signal(
                native, signalNum, &eventLoopSignalFunc, &dg
            ),
            signalNum, dg
        );
    }

    WlIdleEventSource addIdle(IdleDg dg)
    {
        return new WlIdleEventSource(
            wl_event_loop_add_idle(
                native, &eventLoopIdleFunc, &dg
            ),
            dg
        );
    }
}

abstract class WlEventSource : Native!wl_event_source
{
    mixin nativeImpl!(wl_event_source);

    this (wl_event_source* native)
    {
        _native = native;
    }

    int remove ()
    {
        return wl_event_source_remove(native);
    }

    void check()
    {
        wl_event_source_check(native);
    }
}

class WlFdEventSource : WlEventSource
{
    private int _fd;
    private WlEventLoop.FdDg _dg;

    this (wl_event_source* native, int fd, WlEventLoop.FdDg dg)
    {
        super(native);
        _fd = fd;
        _dg = dg;
    }

    int update(uint mask)
    {
        return wl_event_source_fd_update(native, mask);
    }
}

class WlTimerEventSource : WlEventSource
{
    private WlEventLoop.TimerDg _dg;

    this (wl_event_source* native, WlEventLoop.TimerDg dg)
    {
        super(native);
        _dg = dg;
    }

    int update(uint msDelay)
    {
        return wl_event_source_timer_update(native, msDelay);
    }
}

class WlSignalEventSource : WlEventSource
{
    private int _signalNum;
    private WlEventLoop.SignalDg _dg;

    this (wl_event_source* native, int signalNum, WlEventLoop.SignalDg dg)
    {
        super(native);
        _signalNum = signalNum;
        _dg = dg;
    }
}

class WlIdleEventSource : WlEventSource
{
    private WlEventLoop.IdleDg _dg;

    this (wl_event_source* native, WlEventLoop.IdleDg dg)
    {
        super(native);
        _dg = dg;
    }
}

class WlClient : Native!wl_client
{
    mixin nativeImpl!wl_client;

    alias DestroyDg = void delegate(WlClient);
    alias ResourceCreatedDg = void delegate(WlResource);

    DestroyDg _onDestroy;
    ResourceCreatedDg _onResourceCreated;

    this (wl_client* native)
    {
        _native = native;
        ObjectCache.set(native, this);
        wl_client_add_destroy_listener(native, &clientDestroyListener);
        wl_client_add_resource_created_listener(native, &resourceCreatedListener);
    }

    void destroy()
    {
        wl_client_destroy(native);
        _onDestroy = null;
        _onResourceCreated = null;
        _native = null;
    }
}

class WlResource : Native!wl_resource
{
    mixin nativeImpl!wl_resource;

    alias DestroyDg = void delegate(WlResource);
    DestroyDg _onDestroy;

    this (wl_resource* native)
    {
        _native = native;
        ObjectCache.set(native, this);
        wl_resource_add_destroy_listener(native, &resourceDestroyListener);
    }

    void destroy()
    {
        wl_resource_destroy(native);
        ObjectCache.remove(native);
        _onDestroy = null;
        _native = null;
    }
}

private extern(C) nothrow
{
    void displayDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto dpy = cast(WlDisplayBase)ObjectCache.get(data);
            assert(dpy);
            if (dpy._destroyDg) dpy._destroyDg();
            ObjectCache.remove(data);
        });
    }

    void eventLoopDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto el = cast(WlEventLoop)ObjectCache.get(data);
            assert(el);
            if (el._destroyDg) el._destroyDg(el);
            ObjectCache.remove(data);
        });
    }

    void clientCreated(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natCl = cast(wl_client*)data;
            auto natDpy = wl_client_get_display(natCl);
            auto dpy = cast(WlDisplayBase)ObjectCache.get(natDpy);
            assert(dpy, "could not retrieve display from obj cache");
            dpy.registerNewClient(natCl);
        });
    }

    void clientDestroy(wl_listener* listener, void* data)
    {
        nothrowFnWrapper!({
            auto natCl = cast(wl_client*)data;
            auto natDpy = wl_client_get_display(natCl);
            auto dpy = cast(WlDisplayBase)ObjectCache.get(natDpy);
            assert(dpy, "could not retrieve display from obj cache");
            dpy.unregisterClient(natCl);
        });
    }

    void resourceCreated(wl_listener* listener, void* data)
    {

    }

    void resourceDestroy(wl_listener* listener, void* data)
    {

    }


    int eventLoopFdFunc(int fd, uint mask, void* data)
    {
        auto dg = *cast(WlEventLoop.FdDg*)data;
        return dg(fd, mask);
    }

    int eventLoopTimerFunc(void* data)
    {
        auto dg = *cast(WlEventLoop.TimerDg*)data;
        return dg();
    }

    int eventLoopSignalFunc(int sigNumber, void* data)
    {
        auto dg = *cast(WlEventLoop.SignalDg*)data;
        return dg(sigNumber);
    }

    void eventLoopIdleFunc(void* data)
    {
        auto dg = *cast(WlEventLoop.IdleDg*)data;
        dg();
    }

    __gshared wl_listener displayDestroyListener;
    __gshared wl_listener evLoopDestroyListener;
    __gshared wl_listener clientCreatedListener;
    __gshared wl_listener clientDestroyListener;
    __gshared wl_listener resourceCreatedListener;
    __gshared wl_listener resourceDestroyListener;
}

shared static this()
{
    displayDestroyListener.notify = &displayDestroy;
    evLoopDestroyListener.notify = &eventLoopDestroy;
    clientCreatedListener.notify = &clientCreated;
    clientDestroyListener.notify = &clientDestroy;
    resourceCreatedListener.notify = &resourceCreated;
    resourceDestroyListener.notify = &resourceDestroy;
}
