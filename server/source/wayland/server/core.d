// Copyright © 2017 Rémi Thebault
module wayland.server.core;

import wayland.native.server;
import wayland.util;

import std.string;


class WlDisplayBase : Native!wl_display
{
    mixin nativeImpl!(wl_display);

    alias DestroyDg = void delegate();

    // one loop per display, so no need to use an object store
    private WlEventLoop _loop;
    private DestroyDg _destroyDg;

    static WlDisplayBase create()
    {
        // FIXME: instantiate the protocol object
        return new WlDisplayBase(
            wl_display_create()
        );
    }

    this (wl_display* native)
    {
        _native = native;
    }

    void destroy()
    {
        if (_destroyDg) _destroyDg();
        wl_display_destroy(native);
        _native = null;
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


}


class WlEventLoop : Native!wl_event_loop
{
    mixin nativeImpl!(wl_event_loop);

    alias DestroyDg = void delegate();

    nothrow
    {
        alias FdDg = int delegate (int fd, uint mask);
        alias TimerDg = int delegate ();
        alias SignalDg = int delegate (int sigNum);
        alias IdleDg = void delegate ();
    }

    private DestroyDg _destroyDg;

    this()
    {
        _native = wl_event_loop_create();
    }

    this (wl_event_loop* native)
    {
        _native = native;
    }

    @property void destroyListener(DestroyDg dg)
    {
        _destroyDg = dg;
    }

    void destroy()
    {
        if (_destroyDg) _destroyDg();
        wl_event_loop_destroy(_native);
        _destroyDg = null;
        _native = null;
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

private extern(C) nothrow
{
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
}
