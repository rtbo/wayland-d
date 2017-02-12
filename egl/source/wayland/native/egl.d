module wayland.native.egl;

import wayland.native.client;

struct wl_egl_window;

wl_egl_window*
wl_egl_window_create(wl_proxy* surface,
		     int width, int height);

void
wl_egl_window_destroy(wl_egl_window* egl_window);

void
wl_egl_window_resize(wl_egl_window* egl_window,
		     int width, int height,
		     int dx, int dy);

void
wl_egl_window_get_attached_size(wl_egl_window* egl_window,
				int* width, int* height);
