// Copyright © 2017 Rémi Thebault
module wayland.server.core;

import wayland.server.protocol : WlDisplay;
import wayland.server.eventloop;
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


immutable abstract class WlServerInterface : WlInterface
{
    this(immutable wl_interface* native)
    {
        super(native);
    }

    abstract WlResource makeResource(wl_resource* resource) immutable;

    WlGlobal makeGlobal(wl_global* global) immutable
    {
        assert(false, `Interface "` ~ name ~ `" is not global.`);
    }
}


class WlDisplayBase : Native!wl_display
{
    mixin nativeImpl!(wl_display);

    alias DestroyDg = void delegate();
    alias ClientCreatedDg = void delegate(WlClient);
    alias ClientDestroyDg = void delegate(WlClient);

    private wl_listener _destroyListener;
    private wl_listener _clientCreatedListener;

    // one loop per display, so no need to use the object store
    private WlEventLoop _loop;

    private DestroyDg _onDestroy;
    private ClientCreatedDg _onClientCreated;

    private WlClient[] _clients;


    static WlDisplay create()
    {
        auto natDpy = wl_display_create();
        auto dpy = new WlDisplay(natDpy);

        ObjectCache.set(natDpy, dpy);

        return dpy;
    }

    protected this (wl_display* native)
    {
        _native = native;
        wl_list_init(&_destroyListener.link);
        _destroyListener.notify = &displayDestroy;
        wl_display_add_destroy_listener(native, &_destroyListener);

        wl_list_init(&_clientCreatedListener.link);
        _clientCreatedListener.notify = &clientCreated;
        wl_display_add_client_created_listener(native, &_clientCreatedListener);
    }

    void destroy()
    {
        wl_display_destroy(native);
    }

    @property void onDestroy(DestroyDg dg)
    {
        _onDestroy = dg;
    }

    @property void onClientCreated(ClientCreatedDg dg)
    {
        _onClientCreated = dg;
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
        _onDestroy = dg;
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
}


class WlGlobal : Native!wl_global
{
    mixin nativeImpl!wl_global;

    this (wl_global* native)
    {
        _native = native;
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

class WlClient : Native!wl_client
{
    mixin nativeImpl!wl_client;

    alias DestroyDg = void delegate(WlClient);
    alias ResourceCreatedDg = void delegate(WlResource);

    private wl_listener _destroyListener;
    private wl_listener _resourceCreatedListener;

    private DestroyDg _onDestroy;
    private ResourceCreatedDg _onResourceCreated;
    private WlResource[] _resources;

    this (wl_client* native)
    {
        _native = native;
        wl_list_init(&_destroyListener.link);
        _destroyListener.notify = &clientDestroy;
        wl_client_add_destroy_listener(native, &_destroyListener);

        wl_list_init(&_resourceCreatedListener.link);
        _resourceCreatedListener.notify = &resourceCreated;
        wl_client_add_resource_created_listener(native, &_resourceCreatedListener);
    }

    void destroy()
    {
        wl_client_destroy(native);
    }

    @property void onDestroy(DestroyDg dg)
    {
        _onDestroy = dg;
    }

    @property void onResourceCreated(ResourceCreatedDg dg)
    {
        _onResourceCreated = dg;
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

    @property WlResource[] resources()
    {
        return _resources;
    }
}

class WlResource : Native!wl_resource
{
    mixin nativeImpl!wl_resource;

    alias DestroyDg = void delegate(WlResource);

    private wl_listener _destroyListener;
    private DestroyDg _onDestroy;

    this (wl_resource* native)
    {
        _native = native;
        wl_list_init(&_destroyListener.link);
        _destroyListener.notify = &resourceDestroy;
        wl_resource_add_destroy_listener(native, &_destroyListener);
    }

    void destroy()
    {
        wl_resource_destroy(native);
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
}

private extern(C) nothrow
{
    void displayDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto dpy = cast(WlDisplayBase)ObjectCache.get(data);
            assert(dpy, "displayDestroy: could not get display from cache");
            if (dpy._onDestroy) dpy._onDestroy();
            ObjectCache.remove(data);
        });
    }

    void clientCreated(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natCl = cast(wl_client*)data;
            auto natDpy = wl_client_get_display(natCl);
            auto dpy = cast(WlDisplayBase)ObjectCache.get(natDpy);
            assert(dpy, "clientCreated: could not get display from cache");

            auto cl = new WlClient(natCl);
            ObjectCache.set(natCl, cl);
            dpy._clients ~= cl;
            if (dpy._onClientCreated) dpy._onClientCreated(cl);
        });
    }

    void clientDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natCl = cast(wl_client*)data;
            auto natDpy = wl_client_get_display(natCl);
            auto dpy = cast(WlDisplayBase)ObjectCache.get(natDpy);
            assert(dpy, "clientDestroy: could not get display from cache");
            WlClient cl = cast(WlClient)ObjectCache.get(natCl);
            assert(cl, "clientDestroy: could not get client from cache");

            foreach(res; cl.resources)
            {
                destroyRes(res);
            }

            import std.algorithm : remove;
            if (cl._onDestroy) cl._onDestroy(cl);
            dpy._clients = dpy._clients.remove!(c => c is cl);
            ObjectCache.remove(natCl);
        });
    }

    void resourceCreated(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natRes = cast(wl_resource*)data;
            auto natCl = wl_resource_get_client(natRes);
            auto cl = cast(WlClient)ObjectCache.get(natCl);
            assert(cl, "resourceCreated: could not get client from cache");

            auto res = new WlResource(natRes);
            ObjectCache.set(natRes, res);
            cl._resources ~= res;
            if (cl._onResourceCreated) cl._onResourceCreated(res);
        });
    }

    void resourceDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natRes = cast(wl_resource*)data;
            auto natCl = wl_resource_get_client(natRes);
            auto res = cast(WlResource)ObjectCache.get(natRes);
            if (!res) return;

            destroyRes(res);

            auto cl = cast(WlClient)ObjectCache.get(natCl);
            if (cl)
            {
                import std.algorithm : remove;
                cl._resources = cl._resources.remove!(r => r is res);
            }
        });
    }
}

private
{
    void destroyRes(WlResource res)
    {
        if (res._onDestroy) res._onDestroy(res);
        ObjectCache.remove(res.native);
    }
}