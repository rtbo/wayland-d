// Copyright © 2017 Rémi Thebault
module wayland.server.eventloop;

import wayland.native.server;
import wayland.util;

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

    private DestroyDg _onDestroy;

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
    }

    @property void destroyListener(DestroyDg dg)
    {
        _onDestroy = dg;
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

    void eventLoopDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto el = cast(WlEventLoop)ObjectCache.get(data);
            assert(el);
            if (el._onDestroy) el._onDestroy(el);
            ObjectCache.remove(data);
        });
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

    __gshared wl_listener evLoopDestroyListener;
}


shared static this()
{
    evLoopDestroyListener.notify = &eventLoopDestroy;
}
