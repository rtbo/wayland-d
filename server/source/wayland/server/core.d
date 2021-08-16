// Copyright © 2017-2021 Rémi Thebault
module wayland.server.core;

import wayland.server.protocol : WlDisplay, WlShm;
import wayland.server.eventloop;
import wayland.server.listener;
import wayland.native.server;
import wayland.native.util;
import wayland.util;

import std.string;
import std.stdio;
import std.exception : enforce;
import core.sys.posix.sys.types;


enum : uint
{
    WL_EVENT_READABLE = 0x01,
    WL_EVENT_WRITABLE = 0x02,
    WL_EVENT_HANGUP   = 0x04,
    WL_EVENT_ERROR    = 0x08
}


class WlDisplayBase : Native!wl_display
{
    mixin nativeImpl!(wl_display);

    alias DestroySig = Signal!();
    alias ClientCreatedSig = Signal!(WlClient);

    private wl_listener _destroyListener;
    private DestroySig _destroySig;

    private wl_listener _clientCreatedListener;
    private ClientCreatedSig _clientCreatedSig;

    // one loop per display, so no need to use the object store
    private WlEventLoop _loop;

    private WlClient[] _clients;


    static WlDisplay create()
    {
        return new WlDisplay(wl_display_create());
    }

    protected this (wl_display* native)
    {
        _native = native;
        ObjectCache.set(native, this);

        wl_list_init(&_destroyListener.link);
        _destroyListener.notify = &wl_d_display_destroy;
        wl_display_add_destroy_listener(native, &_destroyListener);

        wl_list_init(&_clientCreatedListener.link);
        _clientCreatedListener.notify = &wl_d_client_created;
        wl_display_add_client_created_listener(native, &_clientCreatedListener);
    }

    void destroy()
    {
        wl_display_destroy(native);
    }

    private DestroySig destroySig()
    {
        if (!_destroySig) _destroySig = new DestroySig();
        return _destroySig;
    }

    private ClientCreatedSig clientCreatedSig()
    {
        if (!_clientCreatedSig) _clientCreatedSig = new ClientCreatedSig();
        return _clientCreatedSig;
    }

    void addDestroyListener(DestroySig.Listener listener)
    {
        destroySig.add(listener);
    }

    void addClientCreatedListener(ClientCreatedSig.Listener listener)
    {
        clientCreatedSig.add(listener);
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

    void initShm()
    {
        wl_display_init_shm(native);
    }

    void addShmFormat(WlShm.Format format)
    {
        wl_display_add_shm_format(native, cast(uint)format);
    }
}


abstract class WlGlobal : Native!wl_global
{
    mixin nativeImpl!wl_global;

    this (wl_global* native)
    {
        _native = native;
        ObjectCache.set(native, this);
    }

    void destroy()
    {
        wl_global_destroy(_native);
    }
}


struct Credentials
{
    pid_t pid;
    uid_t uid;
    gid_t gid;
}

final class WlClient : Native!wl_client
{
    mixin nativeImpl!wl_client;

    alias DestroySig = Signal!(WlClient);
    alias NativeResourceCreatedSig = Signal!(wl_resource*);

    private wl_listener _destroyListener;
    private DestroySig _destroySig;

    private wl_listener _resourceCreatedListener;
    private NativeResourceCreatedSig _nativeResourceCreatedSig;

    this (wl_client* native)
    {
        _native = native;
        ObjectCache.set(native, this);

        wl_list_init(&_destroyListener.link);
        _destroyListener.notify = &wl_d_client_destroy;
        wl_client_add_destroy_listener(native, &_destroyListener);

        wl_list_init(&_resourceCreatedListener.link);
        _resourceCreatedListener.notify = &wl_d_client_resource_created;
        wl_client_add_resource_created_listener(native, &_resourceCreatedListener);
    }

    void destroy()
    {
        wl_client_destroy(native);
    }

    private DestroySig destroySig()
    {
        if (!_destroySig) _destroySig = new DestroySig();
        return _destroySig;
    }

    private NativeResourceCreatedSig nativeResourceCreatedSig()
    {
        if (!_nativeResourceCreatedSig) _nativeResourceCreatedSig = new NativeResourceCreatedSig();
        return _nativeResourceCreatedSig;
    }

    void addDestroyListener(DestroySig.Listener listener)
    {
        destroySig.add(listener);
    }

    void addNativeResourceCreatedListener(NativeResourceCreatedSig.Listener listener)
    {
        nativeResourceCreatedSig.add(listener);
    }

    void flush()
    {
        wl_client_flush(native);
    }

    @property Credentials credentials()
    {
        Credentials res;
        wl_client_get_credentials(native, &res.pid, &res.uid, &res.gid);
        return res;
    }

    @property int fd()
    {
        return wl_client_get_fd(native);
    }

    WlResource object(uint id)
    {
        auto natRes = wl_client_get_object(native, id);
        if (!natRes) return null;
        auto res = cast(WlResource)ObjectCache.get(natRes);
        assert(res);
        return res;
    }

    void postNoMemory()
    {
        wl_client_post_no_memory(native);
    }

    @property WlDisplay display()
    {
        auto natDpy = wl_client_get_display(native);
        assert(natDpy);
        auto dpy = cast(WlDisplay)ObjectCache.get(natDpy);
        assert(dpy);
        return dpy;
    }
}

abstract class WlResource : Native!wl_resource
{
    mixin nativeImpl!wl_resource;

    alias DestroySig = Signal!(WlResource);

    private wl_listener _destroyListener;
    private DestroySig _destroySig;

    this (wl_resource* native)
    {
        _native = native;
        ObjectCache.set(native, this);

        wl_list_init(&_destroyListener.link);
        _destroyListener.notify = &wl_d_resource_destroy;
        wl_resource_add_destroy_listener(native, &_destroyListener);
    }

    void destroy()
    {
        wl_resource_destroy(native);
    }

    private DestroySig destroySig()
    {
        if (!_destroySig) _destroySig = new DestroySig();
        return _destroySig;
    }

    void addDestroyListener(DestroySig.Listener listener)
    {
        destroySig.add(listener);
    }

    @property uint id()
    {
        return wl_resource_get_id(native);
    }

    @property WlClient client()
    {
        auto natCl = wl_resource_get_client(native);
        assert(natCl);
        auto cl = cast(WlClient)ObjectCache.get(natCl);
        assert(cl);
        return cl;
    }

    @property int ver()
    {
        return wl_resource_get_version(native);
    }

    @property string cls()
    {
        return fromStringz(wl_resource_get_class(native)).idup;
    }

    void postError(Args...)(uint code, string fmt, Args args)
    {
        wl_resource_post_error(native, code, toStringz(format(fmt, args)));
    }
}

private extern(C) nothrow
{
    void wl_d_display_destroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto dpy = cast(WlDisplayBase)ObjectCache.get(data);
            assert(dpy, "wl_d_display_destroy: could not get display from cache");
            if (dpy._destroySig) dpy._destroySig.emit();
            ObjectCache.remove(data);
        });
    }

    void wl_d_client_created(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natCl = cast(wl_client*)data;
            auto natDpy = wl_client_get_display(natCl);
            auto dpy = cast(WlDisplayBase)ObjectCache.get(natDpy);
            assert(dpy, "wl_d_client_created: could not get display from cache");

            auto cl = new WlClient(natCl);
            dpy._clients ~= cl;
            if (dpy._clientCreatedSig) dpy._clientCreatedSig.emit(cl);
        });
    }

    void wl_d_client_destroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natCl = cast(wl_client*)data;
            auto natDpy = wl_client_get_display(natCl);
            auto dpy = cast(WlDisplayBase)ObjectCache.get(natDpy);
            assert(dpy, "wl_d_client_destroy: could not get display from cache");
            WlClient cl = cast(WlClient)ObjectCache.get(natCl);
            assert(cl, "wl_d_client_destroy: could not get client from cache");

            import std.algorithm : remove;
            if (cl._destroySig) cl._destroySig.emit(cl);
            dpy._clients = dpy._clients.remove!(c => c is cl);
            ObjectCache.remove(natCl);
        });
    }

    void wl_d_client_resource_created(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natRes = cast(wl_resource*)data;
            auto natCl = wl_resource_get_client(natRes);
            auto cl = cast(WlClient)ObjectCache.get(natCl);
            assert(cl);
            if (cl._nativeResourceCreatedSig) cl._nativeResourceCreatedSig.emit(natRes);
        });
    }

    void wl_d_resource_destroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natRes = cast(wl_resource*)data;

            auto res = cast(WlResource)ObjectCache.get(natRes);
            if (res && res._destroySig) res._destroySig.emit(res);

            ObjectCache.remove(natRes);
        });
    }
}