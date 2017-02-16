module wayland.native.egl;

import wayland.native.client;

extern(C) struct wl_egl_window;

version(WlDynamic)
{
	extern(C) nothrow
	{
        alias da_wl_egl_window_create = wl_egl_window* function (wl_proxy* surface, int width, int height);

        alias da_wl_egl_window_destroy = void function (wl_egl_window* egl_window);

        alias da_wl_egl_window_resize = void function (wl_egl_window* egl_window, int width, int height, int dx, int dy);

        alias da_wl_egl_window_get_attached_size = void function (wl_egl_window* egl_window, int* width, int* height);
	}

	__gshared
	{
        da_wl_egl_window_create wl_egl_window_create;

        da_wl_egl_window_destroy wl_egl_window_destroy;

        da_wl_egl_window_resize wl_egl_window_resize;

        da_wl_egl_window_get_attached_size wl_egl_window_get_attached_size;
	}
}

version(WlStatic)
{
	extern(C) nothrow
	{
		wl_egl_window* wl_egl_window_create(wl_proxy* surface, int width, int height);

		void wl_egl_window_destroy(wl_egl_window* egl_window);

		void wl_egl_window_resize(wl_egl_window* egl_window, int width, int height, int dx, int dy);

		void wl_egl_window_get_attached_size(wl_egl_window* egl_window, int* width, int* height);
	}
}

