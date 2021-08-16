// Copyright © 2017-2021 Rémi Thebault
module wayland.util;

import wayland.native.util;

/// Implemented by type that wrap a native wayland struct pointer.
interface Native(wl_native)
{
    /// Access the wrapped struct.
    @property inout(wl_native)* native() inout;
}

/// Utility mixin that implements Native for a type.
mixin template nativeImpl(wl_native)
{
    private wl_native* _native;

    public final override @property inout(wl_native)* native() inout
    {
        return _native;
    }
}


immutable class WlInterface
{
    private immutable wl_interface* _native;

    immutable this(immutable wl_interface* native)
    {
        this._native = native;
    }

    @property immutable(wl_interface)* native() immutable
    {
        return _native;
    }

    @property string name() immutable
    {
        import std.string : fromStringz;
        return fromStringz(_native.name);
    }
}

/++
 +  Check for equality between two interfaces
 +/
bool wlIfaceEquals(immutable(WlInterface) a, immutable(WlInterface) b)
{
    import core.stdc.string : strcmp;

    return a is b || strcmp(a._native.name, b._native.name) == 0;
}

/++
 +  Wraps a function literal into a try-catch statement.
 +
 +  Use this in functions called by C as exception cannot propagate there.
 +  The try-catch statement will print a warning if an exception is thrown.
 +  The try-catch statement will terminate runtime and exit program if an error is thrown.
 +/
auto nothrowFnWrapper(alias fn)() nothrow
{
    try
    {
        return fn();
    }
    catch(Exception ex)
    {
        import std.exception : collectException;
        import std.stdio : stderr;
        collectException(stderr.writeln("wayland-d: error in listener stub: "~ex.msg));
    }
    catch(Throwable err)
    {
        import core.runtime : Runtime;
        import core.stdc.stdlib : exit;
        import std.exception : collectException;
        import std.stdio : stderr;
        collectException(stderr.writeln("wayland-d: aborting due to error in listener stub: "~err.msg));
        collectException(Runtime.terminate());
        exit(1);
    }
    alias rt = typeof(fn());
    static if (!is(rt == void))
    {
        return rt.init;
    }
}



/// static cache of objects that are looked-up by the address of their native
/// counter part
struct ObjectCache
{
    private __gshared Object[void*] _cache;

    static void set (void* native, Object obj)
    {
        _cache[native] = obj;
    }

    static Object get (void* native)
    {
        auto op = native in _cache;
        return op ? *op : null;
    }

    static void remove (void* native)
    {
        _cache.remove(native);
    }
}

/**
 * Fixed-point number
 *
 * A `WlFixed` is a 24.8 signed fixed-point number with a sign bit, 23 bits
 * of integer precision and 8 bits of decimal precision.
 */
struct WlFixed
{
    private uint _raw;
    private union DI
    {
        long i;
        double d;
    }

    public this(uint raw)
    {
        _raw = raw;
    }

    /**
    * Converts an integer to a fixed-point number.
    */
    public static WlFixed create(in int val)
    {
        return WlFixed(val * 256);
    }

    /**
    * Converts a floating-point number to a fixed-point number.
    */
    public static WlFixed create(in double val)
    {
        DI u;
        u.d = val + (3L << (51 - 8));
        return WlFixed(cast(uint)(u.i));
    }

    @property uint raw() const
    {
        return _raw;
    }

    /**
    * Converts a fixed-point number to an integer.
    */
    int opCast(T : int)() const
    {
        return _raw / 256;
    }

    /**
    * Converts a fixed-point number to a floating-point number.
    */
    double opCast(T : double)() const
    {
        DI u;
        u.i = ((1023L + 44L) << 52) + (1L << 51) + f;
        return u.d - (3L << 43);
    }
}
