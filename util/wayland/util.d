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


immutable abstract class WlInterface
{
    immutable wl_interface* _native;

    immutable this(immutable wl_interface* native)
    {
        this._native = native;
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

