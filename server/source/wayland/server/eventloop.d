// Copyright © 2017 Rémi Thebault
module wayland.server.eventloop;

import wayland.native.server;
import wayland.util;

class WlEventLoop : Native!wl_event_loop
{
    mixin nativeImpl!(wl_event_loop);

    alias DestroyDg = void delegate(WlEventLoop loop);
    alias FdDg = int delegate (int fd, uint mask);
    alias TimerDg = int delegate ();
    alias SignalDg = int delegate (int sigNum);
    alias IdleDg = void delegate ();


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
        return new WlFdEventSource(native, fd, mask, dg);
    }

    WlTimerEventSource addTimer(TimerDg dg)
    {
        return new WlTimerEventSource(native, dg);
    }

    WlSignalEventSource addSignal(int signalNum, SignalDg dg)
    {
        return new WlSignalEventSource(native, signalNum, dg);
    }

    WlIdleEventSource addIdle(IdleDg dg)
    {
        return new WlIdleEventSource(native, dg);
    }
}

abstract class WlEventSource : Native!wl_event_source
{
    mixin nativeImpl!(wl_event_source);

    this(wl_event_source* native)
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
    private WlEventLoop.FdDg dg;

    this (wl_event_loop* nativeLoop, int fd, uint mask, WlEventLoop.FdDg dg)
    {
        this.dg = dg;
        super(wl_event_loop_add_fd(
            nativeLoop, fd, mask, &eventLoopFdFunc, cast(void*)this
        ));
    }

    int update(uint mask)
    {
        return wl_event_source_fd_update(native, mask);
    }
}

class WlTimerEventSource : WlEventSource
{
    private WlEventLoop.TimerDg dg;

    this (wl_event_loop* nativeLoop, WlEventLoop.TimerDg dg)
    {
        this.dg = dg;
        super(wl_event_loop_add_timer(
            nativeLoop, &eventLoopTimerFunc, cast(void*)this
        ));
    }

    int update(uint msDelay)
    {
        return wl_event_source_timer_update(native, msDelay);
    }
}

class WlSignalEventSource : WlEventSource
{
    private WlEventLoop.SignalDg dg;

    this (wl_event_loop* nativeLoop, int signalNum, WlEventLoop.SignalDg dg)
    {
        this.dg = dg;
        super(wl_event_loop_add_signal(
            nativeLoop, signalNum, &eventLoopSignalFunc, cast(void*)this
        ));
    }
}

class WlIdleEventSource : WlEventSource
{
    private WlEventLoop.IdleDg dg;

    this (wl_event_loop* nativeLoop, WlEventLoop.IdleDg dg)
    {
        this.dg = dg;
        super(wl_event_loop_add_idle(
            nativeLoop, &eventLoopIdleFunc, cast(void*)this
        ));
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
        return nothrowFnWrapper!({
            auto src = cast(WlFdEventSource)data;
            return src.dg(fd, mask);
        });
    }

    int eventLoopTimerFunc(void* data)
    {
        return nothrowFnWrapper!({
            auto src = cast(WlTimerEventSource)data;
            return src.dg();
        });
    }

    int eventLoopSignalFunc(int sigNumber, void* data)
    {
        return nothrowFnWrapper!({
            auto src = cast(WlSignalEventSource)data;
            return src.dg(sigNumber);
        });
    }

    void eventLoopIdleFunc(void* data)
    {
        nothrowFnWrapper!({
            auto src = cast(WlIdleEventSource)data;
            src.dg();
        });
    }

    __gshared wl_listener evLoopDestroyListener;
}


shared static this()
{
    evLoopDestroyListener.notify = &eventLoopDestroy;
}
