// Copyright © 2017-2021 Rémi Thebault
module wayland.server.shm;

import wayland.server.protocol : WlShm;
import wayland.server.core;
import wayland.native.server;
import wayland.native.util;
import wayland.util;

class WlShmBuffer : Native!wl_shm_buffer
{
    mixin nativeImpl!wl_shm_buffer;

    private this(wl_shm_buffer* native)
    {
        _native = native;
        ObjectCache.set(native, this);
    }

    static WlShmBuffer get(WlResource res)
    {
        auto natBuf = wl_shm_buffer_get(res.native);
        if (!natBuf) return null;
        auto buf = cast(WlShmBuffer)ObjectCache.get(natBuf);
        if (!buf)
        {
            buf = new WlShmBuffer(natBuf);
        }
        return buf;
    }

    void beginAccess()
    {
        wl_shm_buffer_begin_access(native);
    }

    void endAccess()
    {
        wl_shm_buffer_end_access(native);
    }

    @property void[] data()
    {
        auto dp = wl_shm_buffer_get_data(native);
        if (!dp) return null;
        return dp[0 .. height*stride];
    }

    @property size_t stride()
    {
        return wl_shm_buffer_get_stride(native);
    }

    @property int width()
    {
        return wl_shm_buffer_get_width(native);
    }

    @property int height()
    {
        return wl_shm_buffer_get_height(native);
    }

    @property WlShm.Format format()
    {
        return cast(WlShm.Format)wl_shm_buffer_get_format(native);
    }

    WlShmPool refPool()
    {
        return new WlShmPool(wl_shm_buffer_ref_pool(native));
    }
}

class WlShmPool : Native!wl_shm_pool
{
    mixin nativeImpl!wl_shm_pool;

    private this(wl_shm_pool* native)
    {
        _native = native;
    }

    void unref()
    {
        wl_shm_pool_unref(native);
    }
}
