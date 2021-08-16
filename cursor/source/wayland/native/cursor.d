// Copyright © 2017-2021 Rémi Thebault
/// bindings to wayland-client-core.h
module wayland.native.cursor;

// Wayland client-core copyright:
/*
 * Copyright © 2012 Intel Corporation
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice (including the
 * next paragraph) shall be included in all copies or substantial
 * portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import wayland.native.client : wl_proxy;

extern(C)
{
    struct wl_cursor_theme;

    struct wl_cursor_image {
        uint width;		/* actual width */
        uint height;	/* actual height */
        uint hotspot_x;	/* hot spot x (must be inside image) */
        uint hotspot_y;	/* hot spot y (must be inside image) */
        uint delay;		/* animation delay to next frame (ms) */
    };

    struct wl_cursor {
        uint image_count;
        wl_cursor_image** images;
        char* name;
    };
}

version(WlDynamic)
{
    extern(C) nothrow
    {
        alias da_wl_cursor_theme_load = wl_cursor_theme* function (const(char)* name, int size, wl_proxy* shm);

        alias da_wl_cursor_theme_destroy = void function (wl_cursor_theme* theme);

        alias da_wl_cursor_theme_get_cursor = wl_cursor* function (wl_cursor_theme* theme, const(char)* name);

        alias da_wl_cursor_image_get_buffer = wl_proxy* function (wl_cursor_image* image);

        alias da_wl_cursor_frame = int function (wl_cursor* cursor, uint time);

        alias da_wl_cursor_frame_and_duration = int function (wl_cursor* cursor, uint time, uint* duration);
    }

    __gshared
    {
        da_wl_cursor_theme_load wl_cursor_theme_load;

        da_wl_cursor_theme_destroy wl_cursor_theme_destroy;

        da_wl_cursor_theme_get_cursor wl_cursor_theme_get_cursor;

        da_wl_cursor_image_get_buffer wl_cursor_image_get_buffer;

        da_wl_cursor_frame wl_cursor_frame;

        da_wl_cursor_frame_and_duration wl_cursor_frame_and_duration;
    }
}

version(WlStatic)
{
    extern(C) nothrow
    {
        wl_cursor_theme* wl_cursor_theme_load(const(char)* name, int size, wl_proxy* shm);

        void wl_cursor_theme_destroy(wl_cursor_theme* theme);

        wl_cursor* wl_cursor_theme_get_cursor(wl_cursor_theme* theme, const(char)* name);

        wl_proxy* wl_cursor_image_get_buffer(wl_cursor_image* image);

        int wl_cursor_frame(wl_cursor* cursor, uint time);

        int wl_cursor_frame_and_duration(wl_cursor* cursor, uint time, uint* duration);
    }
}
