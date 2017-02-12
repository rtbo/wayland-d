module egl_window;

// port of this example:
// https://github.com/eyelash/tutorials/blob/master/wayland-egl.c

import wayland.client;
import wayland.egl;
import derelict.gles.egl;
import derelict.gles.gles2;
import std.stdio;

enum winWidth = 256;
enum winHeight = 256;

class EglWindow
{
	EGLDisplay eglDisplay;
	WlDisplay display;
	WlCompositor compositor;
	WlShell shell;
	bool running = true;
	float red = 0;
	float green = 0;
	float blue = 0;

	EGLContext eglContext;
	WlSurface surf;
	WlShellSurface shSurf;
	WlEglWindow eglWin;
	EGLSurface elgSurf;

	this()
	{
		DerelictEGL.load();
		DerelictGLES2.load();

		auto display = enforce(WlDisplay.connect());
		auto reg = display.getRegistry();
		reg.onGlobal = &regGlobal;
		display.roundtrip();
		reg.destroy();

		eglDisplay = eglGetDisplay (display);
		eglInitialize (eglDisplay, null, null);
	}

	void regGlobal(WlRegistry reg, uint name, string iface, uint ver)
	{
		if (iface == WlCompositor.iface.name)
		{
			compositor = cast(WlCompositor)reg.bind(name, WlCompositor.iface, 0);
		}
		else if (iface == WlShell.iface.name)
		{
			shell = cast(WlShell)reg.bind(name, WlShell.iface, 0);
		}
	}

	void create()
	{
		eglBindAPI (EGL_OPENGL_API);
		int[] attributes = [
			EGL_RED_SIZE, 8,
			EGL_GREEN_SIZE, 8,
			EGL_BLUE_SIZE, 8,
			EGL_NONE
		];
		EGLConfig config;
		EGLint numConfig;
		eglChooseConfig (eglDisplay, attributes, &config, 1, &numConfig);
		eglContext = eglCreateContext (eglDisplay, config, EGL_NO_CONTEXT, null);

		surf = enforce(compositor.createSurface());
		shSurf = enforce(shell.getShellSurface(surf));
		shSurf.setToplevel();

		eglWin = new WlEglWindow(surf, winWidth, winHeight);
		eglSurf = eglCreateWindowSurface(eglDisplay, config, eglWin, null);

		shSurf.onPing = (WlShellSurface surf, uint serial) {
			surf.pong(serial);
		};
		shSurf.onConfigure = (WlShellSurface surf, uint edges, int width, int height) {
			eglWin.resize(width, height);
		};

		eglMakeCurrent (eglDisplay, eglSurf, eglSurf, eglContext );
	}

	void draw()
	{
		glClearColor (red, green, blue, 1.0);
		glClear (GL_COLOR_BUFFER_BIT);
		eglSwapBuffers (eglDisplay, eglDurface);

		if (red < 1f)
		{
			red += 0.01f;
		}
		else if (green < 1f)
		{
			green += 0.01f;
		}
		else if (blue < 1f)
		{
			blue += 0.01f;
		}
		else
		{
			running = false;
		}
	}

	void destroy()
	{
		eglDestroySurface(eglDisplay, eglSurf);
		eglWin.destroy();
		shSurf.destroy();
		surf.destroy();
		eglDestroyContext(eglDisplay, eglContext);

		eglTerminate(eglDisplay);
		display.disconnect();
	}
}



int main ()
{
	auto win = new EglWindow();
	win.create();

	while(win.running)
	{
		win.display.dispatch();
		win.draw();
	}

	win.destroy();
	return 0;
}
