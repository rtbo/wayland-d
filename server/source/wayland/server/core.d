// Copyright © 2017 Rémi Thebault
module wayland.server.core;

import wayland.server.protocol;
import wayland.server.eventloop;
import wayland.native.server;
import wayland.util;

import std.string;
import std.exception : enforce;
import core.sys.posix.sys.types;


class WlDisplayBase : Native!wl_display
{
    mixin nativeImpl!(wl_display);

    alias DestroyDg = void delegate();
    alias ClientCreatedDg = void delegate(WlClient);

    // one loop per display, so no need to use an object store
    private WlEventLoop _loop;

    private DestroyDg _onDestroy;
    private ClientCreatedDg _onClientCreated;

    private WlClient[] _clients;


    static WlDisplay create()
    {
        auto natDpy = wl_display_create();
        auto dpy = new WlDisplay(natDpy);

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
        _onDestroy = null;
        _onClientCreated = null;
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

    private void registerNewClient(wl_client* natCl)
    {
        auto cl = new WlClient(natCl);
        ObjectCache.set(natCl, cl);
        _clients ~= cl;
        if (_onClientCreated) _onClientCreated(cl);
    }

    private void unregisterClient(wl_client* natCl)
    {
        import std.algorithm : remove;
        WlClient cl = cast(WlClient)ObjectCache.get(natCl);
        assert(cl, "could not retrieve client from obj cache");
        if (cl._onDestroy) cl._onDestroy(cl);
        _clients = _clients.remove!(c => c is cl);
        cl._onDestroy = null;
        cl._native = null;
        ObjectCache.remove(natCl);
    }
}


class WlGlobal : Native!wl_global
{
    mixin nativeImpl!wl_global;

    this (wl_global* wl_global)
    {
        _native = native;
    }

    void destroy()
    {
        wl_global_destroy(_native);
        _native = null;
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

    DestroyDg _onDestroy;
    ResourceCreatedDg _onResourceCreated;
    WlResource[] _resources;

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
        return res ? res : new WlResource(natRes);
    }

    void postNoMemory()
    {
        wl_client_post_no_memory(native);
    }

    @property WlDisplayBase display()
    {
        auto natDpy = wl_client_get_display(native);
        assert(natDpy);
        return enforce(cast(WlDisplayBase)ObjectCache.get(natDpy));
    }

    private void registerNewResource(wl_resource* natRes)
    {
        auto res = new WlResource(natRes);
        ObjectCache.set(natRes, res);
        _resources ~= res;
        if (_onResourceCreated) _onResourceCreated(res);
    }

    private void unregisterResource(wl_resource* natRes)
    {
        import std.algorithm : remove;
        WlResource res = cast(WlResource)ObjectCache.get(natRes);
        assert(res, "could not retrieve resource from obj cache");
        if (res._onDestroy) res._onDestroy(res);
        _resources = _resources.remove!(r => r is res);
        res._onDestroy = null;
        res._native = null;
        ObjectCache.remove(natRes);
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
        wl_resource_add_destroy_listener(native, &resourceDestroyListener);
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
        return enforce(cast(WlClient)ObjectCache.get(natCl));
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
            assert(dpy);
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
            assert(dpy, "could not retrieve display from obj cache");
            dpy.registerNewClient(natCl);
        });
    }

    void clientDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natCl = cast(wl_client*)data;
            auto natDpy = wl_client_get_display(natCl);
            auto dpy = cast(WlDisplayBase)ObjectCache.get(natDpy);
            assert(dpy, "could not retrieve display from obj cache");
            dpy.unregisterClient(natCl);
        });
    }

    void resourceCreated(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natRes = cast(wl_resource*)data;
            auto natCl = wl_resource_get_client(natRes);
            auto cl = cast(WlClient)ObjectCache.get(natCl);
            assert(cl, "could not retrieve client from obj cache");
            cl.registerNewResource(natRes);
        });
    }

    void resourceDestroy(wl_listener*, void* data)
    {
        nothrowFnWrapper!({
            auto natRes = cast(wl_resource*)data;
            auto natCl = wl_resource_get_client(natRes);
            auto cl = cast(WlClient)ObjectCache.get(natCl);
            assert(cl, "could not retrieve client from obj cache");
            cl.unregisterResource(natRes);
        });
    }

    __gshared wl_listener displayDestroyListener;
    __gshared wl_listener clientCreatedListener;
    __gshared wl_listener clientDestroyListener;
    __gshared wl_listener resourceCreatedListener;
    __gshared wl_listener resourceDestroyListener;
}

shared static this()
{
    displayDestroyListener.notify = &displayDestroy;
    clientCreatedListener.notify = &clientCreated;
    clientDestroyListener.notify = &clientDestroy;
    resourceCreatedListener.notify = &resourceCreated;
    resourceDestroyListener.notify = &resourceDestroy;
}
