module egl_window;

// port of this example:
// https://github.com/eyelash/tutorials/blob/master/wayland-egl.c

import wayland.client;
import wayland.egl;
import derelict.gles.egl;
import derelict.gles.gles2;

import std.stdio;
import std.exception;

enum winWidth = 256;
enum winHeight = 256;

class Display
{
	WlDisplay display;
	WlCompositor compositor;
	WlShell shell;
	EGLDisplay eglDisplay;
	EGLContext eglContext;
	EGLConfig config;

	this()
	{
		DerelictEGL.load();

		display = enforce(WlDisplay.connect());
		auto reg = display.getRegistry();
		reg.onGlobal = &regGlobal;
		display.roundtrip();
		reg.destroy();

		eglDisplay = enforce(eglGetDisplay (cast(void*)display.proxy));
		enforce(eglInitialize(eglDisplay, null, null) == EGL_TRUE);
		enforce(eglBindAPI (EGL_OPENGL_ES_API) == GL_TRUE);
		int[] attributes = [
			EGL_RED_SIZE, 8,
			EGL_GREEN_SIZE, 8,
			EGL_BLUE_SIZE, 8,
			EGL_ALPHA_SIZE, 8,
			EGL_BUFFER_SIZE, 32,
			EGL_NONE
		];
		EGLint numConfig;
		enforce(eglChooseConfig (eglDisplay, attributes.ptr, &config, 1, &numConfig) == GL_TRUE);
		eglContext = enforce(eglCreateContext (eglDisplay, config, EGL_NO_CONTEXT, null));

		DerelictGLES2.load(&loadSymbol);
	}

	void regGlobal(WlRegistry reg, uint name, string iface, uint ver)
	{
		import std.algorithm : min;
		if (iface == WlCompositor.iface.name)
		{
			compositor = cast(WlCompositor)reg.bind(name, WlCompositor.iface, min(ver, 4));
		}
		else if (iface == WlShell.iface.name)
		{
			shell = cast(WlShell)reg.bind(name, WlShell.iface, min(ver, 1));
		}
	}

	void destroy()
	{
		eglDestroyContext(eglDisplay, eglContext);
		eglTerminate(eglDisplay);
		display.disconnect();
	}

}

class EglWindow
{
	Display dpy;

	WlSurface surf;
	WlShellSurface shSurf;
	WlEglWindow eglWin;
	EGLSurface eglSurf;

	bool running = true;
	float red = 0;
	float green = 0;
	float blue = 0;
	bool configured;

	this (Display dpy)
	{
		this.dpy = dpy;
		surf = enforce(dpy.compositor.createSurface());
		shSurf = enforce(dpy.shell.getShellSurface(surf));
		shSurf.setToplevel();

		eglWin = new WlEglWindow(surf, winWidth, winHeight);
		eglSurf = eglCreateWindowSurface(dpy.eglDisplay, dpy.config, cast(void*)eglWin.native, null);

		shSurf.onPing = (WlShellSurface surf, uint serial) {
			surf.pong(serial);
		};
		shSurf.onConfigure = (WlShellSurface surf,
								WlShellSurface.Resize edges,
								int width, int height)
		{
			eglWin.resize(width, height, 0, 0);
			configured = true;
		};

		eglMakeCurrent (dpy.eglDisplay, eglSurf, eglSurf, dpy.eglContext );

		surf.commit();
	}

	void draw()
	{
		glViewport(0, 0, winWidth, winHeight);
		glClearColor (red, green, blue, 0.5);
		glClear (GL_COLOR_BUFFER_BIT);
		eglSwapBuffers (dpy.eglDisplay, eglSurf);

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
		eglDestroySurface(dpy.eglDisplay, eglSurf);
		eglWin.destroy();
		shSurf.destroy();
		surf.destroy();
	}
}

void* loadSymbol(string name)
{
    import std.format : format;
	import std.string : toStringz;

    auto sym = enforce (
		eglGetProcAddress(toStringz(name)),
    	format("Failed to load symbol %s: 0x%x", name, eglGetError())
	);
    return sym;
}

int main ()
{
	auto dpy = new Display();
	scope(exit) dpy.destroy();
	auto win = new EglWindow(dpy);
	scope(exit) win.destroy();

	while(win.running)
	{
		if (win.configured) dpy.display.dispatch();
		else dpy.display.dispatchPending();
		win.draw();
	}

	return 0;
}
