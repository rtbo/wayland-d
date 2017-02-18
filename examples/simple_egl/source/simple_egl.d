module simple_egl;

// port of this example:
// https://github.com/eyelash/tutorials/blob/master/wayland-egl.c

import wayland.client;
import wayland.egl;
import wayland.cursor;
import wayland.util;
import wayland.native.util;
import zxdg_shell_v6;
import derelict.gles.egl;
import derelict.gles.gles2;

import std.exception;
import std.format;
import std.stdio;
import std.string;
import core.time;

enum winWidth = 256;
enum winHeight = 256;

class Display
{
	WlDisplay display;
	WlCompositor compositor;
	WlShm shm;
	WlSeat seat;
	ZxdgShellV6 shell;
	WlCursorTheme cursorTheme;
	WlCursor defaultCursor;
	WlSurface cursorSurf;
	WlPointer pointer;
	WlKeyboard kbd;

	EGLDisplay eglDisplay;
	EGLContext eglContext;
	EGLConfig config;

	EglWindow window;

	this()
	{
		display = enforce(WlDisplay.connect());
		auto reg = display.getRegistry();
		reg.onGlobal = (WlRegistry reg, uint name, string iface, uint ver)
		{
			import std.algorithm : min;
			if (iface == WlCompositor.iface.name)
			{
				compositor = cast(WlCompositor)reg.bind(name, WlCompositor.iface, min(ver, 4));
			}
			else if (iface == WlShm.iface.name)
			{
				shm = cast(WlShm)reg.bind(name, WlShm.iface, min(ver, 1));
				cursorTheme = enforce(
					WlCursorTheme.load(null, 32, shm),
					"Unable to load default cursor theme"
				);
				defaultCursor = enforce(
					cursorTheme.cursor("left_ptr"),
					"Unable to load default left pointer"
				);
			}
			else if (iface == WlSeat.iface.name)
			{
				seat = cast(WlSeat)reg.bind(name, WlSeat.iface, min(ver, 1));
				seat.onCapabilities = &seatCapChanged;

			}
			else if (iface == ZxdgShellV6.iface.name)
			{
				shell = cast(ZxdgShellV6)reg.bind(name, ZxdgShellV6.iface, min(ver, 1));
				shell.onPing = (ZxdgShellV6 shell, uint serial) {
					shell.pong(serial);
				};
			}
		};
		display.roundtrip();
		reg.destroy();

		cursorSurf = compositor.createSurface();

		DerelictEGL.load();

		eglDisplay = enforce(eglGetDisplay (cast(void*)display.proxy));
		enforce(eglInitialize(eglDisplay, null, null) == EGL_TRUE);
		enforce(eglBindAPI (EGL_OPENGL_ES_API) == GL_TRUE);


		int[] ctxAttribs = [
			EGL_CONTEXT_CLIENT_VERSION, 2,
			EGL_NONE
		];
		int[] attributes = [
			EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
			EGL_RED_SIZE, 8,
			EGL_GREEN_SIZE, 8,
			EGL_BLUE_SIZE, 8,
			EGL_ALPHA_SIZE, 8,
			EGL_BUFFER_SIZE, 32,
			EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
			EGL_NONE
		];
		EGLint numConfig;
		enforce(eglChooseConfig (eglDisplay, attributes.ptr, &config, 1, &numConfig) == GL_TRUE);
		eglContext = enforce(eglCreateContext (eglDisplay, config, EGL_NO_CONTEXT, ctxAttribs.ptr));
	}


	void seatCapChanged (WlSeat seat, WlSeat.Capability cap)
	{
		if ((cap & WlSeat.Capability.pointer) && !pointer)
		{
			pointer = seat.getPointer();
			pointer.onEnter = &pointerEnter;
			pointer.onButton = &pointerButton;
		}
		else if (!(cap & WlSeat.Capability.pointer) && pointer)
		{
			pointer.destroy();
			pointer = null;
		}

		if ((cap & WlSeat.Capability.keyboard) && !kbd)
		{
			kbd = seat.getKeyboard();
			kbd.onKey = &kbdKey;
		}
		else if (!(cap & WlSeat.Capability.keyboard) && kbd)
		{
			kbd.destroy();
			kbd = null;
		}
	}

	void pointerEnter(WlPointer pointer, uint serial, WlSurface surface,
			WlFixed sx, WlFixed sy)
	{
		if (defaultCursor)
		{
			auto img = defaultCursor.images[0];
			auto buf = img.buffer;
			if (!buf) return;
			pointer.setCursor(serial, cursorSurf, img.hotspotX, img.hotspotY);
			cursorSurf.attach(buf, 0, 0);
			cursorSurf.damage(0, 0, img.width, img.height);
			cursorSurf.commit();
		}
	}

	void pointerButton(WlPointer pointer, uint serial, uint time, uint button,
			WlPointer.ButtonState state)
	{
		import linux.input : BTN_LEFT;

		if (!window || !window.topLevel) return;

		if (button == BTN_LEFT && state == WlPointer.ButtonState.pressed)
		{
			window.topLevel.move(seat, serial);
		}
	}

	void kbdKey(WlKeyboard keyboard, uint serial, uint time, uint key,
			WlKeyboard.KeyState state)
	{
		import linux.input : KEY_ESC;

		if (!window) return;

		if (key == KEY_ESC && state) window.running = false;
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
	ZxdgSurfaceV6 xdgSurf;
	ZxdgToplevelV6 topLevel;

	WlEglWindow eglWin;
	EGLSurface eglSurf;

	GLuint program;
	GLuint vbo;
	GLuint posAttrib = 0;
	GLuint colAttrib = 1;
	GLuint rotationUnif;

	MonoTime startTime;
	bool running = true;
	bool configured;

	this (Display dpy)
	{
		this.dpy = dpy;

		surf = enforce(dpy.compositor.createSurface());
		xdgSurf = enforce(dpy.shell.getXdgSurface(surf));
		topLevel = enforce(xdgSurf.getToplevel());

		topLevel.onConfigure = &onTLConfigure;
		topLevel.onClose = &onTLClose;
		topLevel.setTitle("wayland-d - EGL window");

		xdgSurf.onConfigure = (ZxdgSurfaceV6 surf, uint serial)
		{
			surf.ackConfigure(serial);
			configured = true;
		};

		eglWin = new WlEglWindow(surf, winWidth, winHeight);
		eglSurf = enforce(eglCreateWindowSurface(dpy.eglDisplay, dpy.config, cast(void*)eglWin.native, null));

		enforce(eglMakeCurrent (dpy.eglDisplay, eglSurf, eglSurf, dpy.eglContext) == GL_TRUE);

		DerelictGLES2.load(&loadSymbol);
		DerelictGLES2.reload();
		writeln("created OpenGLES context: ", fromStringz(glGetString(GL_VERSION)));

		initGl();
		startTime = MonoTime.currTime();
		surf.commit();
	}

	void onTLConfigure(ZxdgToplevelV6, int width, int height, wl_array* states)
	{
		if (eglWin) eglWin.resize(winWidth, winHeight, 100, 100);
	}

	void onTLClose(ZxdgToplevelV6)
	{
		running = false;
	}

	GLuint createShader(string source, GLenum stage)
	{
		const(GLchar)* srcPtr = source.ptr;
		auto srcLen = cast(GLint)source.length;
		auto sh = glCreateShader(stage);
		glShaderSource(sh, 1, &srcPtr, &srcLen);
		glCompileShader(sh);
		GLint status;
		glGetShaderiv(sh, GL_COMPILE_STATUS, &status);
		if (status == GL_FALSE)
		{
			char[1024] log;
			GLsizei len;
			glGetShaderInfoLog(sh, 1024, &len, log.ptr);
			throw new Exception(format(
				"%s shader compilation failed:\n%s",
				stage == GL_VERTEX_SHADER ? "vertex" : "fragment",
				log[0 .. len].idup));
		}

		return sh;
	}

	GLuint buildProgram()
	{
		immutable vertSrc = "
			uniform mat4 rotation;
			attribute vec4 pos;
			attribute vec4 col;
			varying vec4 v_col;
			void main() {
				gl_Position = rotation * pos;
				v_col = col;
			}
		";
		immutable fragSrc = "
			precision mediump float;
			varying vec4 v_col;
			void main() {
				gl_FragColor = v_col;
			}
		";
		auto vertSh = createShader(vertSrc, GL_VERTEX_SHADER);
		auto fragSh = createShader(fragSrc, GL_FRAGMENT_SHADER);

		GLuint program = glCreateProgram();
		glAttachShader(program, vertSh);
		glAttachShader(program, fragSh);
		glLinkProgram(program);
		GLint status;
		glGetProgramiv(program, GL_LINK_STATUS, &status);
		enforce(status);

		glDeleteShader(vertSh);
		glDeleteShader(fragSh);

		return program;
	}

	void initGl()
	{
		program = buildProgram();

		glGenBuffers(1, &vbo);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);

		immutable float[] colorTriangle = [
			// pos
			0f, 0.8f, 0f, 1f,
			-0.7f, -0.6f, 0f, 1f,
			0.7f, -0.6f, 0f, 1f,
			// col
			1f, 0.3f, 0.3f, 0.5f,
			0.3f, 1f, 0.3f, 0.5f,
			0.3f, 0.3f, 1f, 0.5f,
		];

		glBufferData(GL_ARRAY_BUFFER,
			colorTriangle.length*4,
			cast(const(void*))colorTriangle.ptr,
			GL_STATIC_DRAW);

		glUseProgram(program);
		glBindAttribLocation(program, posAttrib, "pos");
		glBindAttribLocation(program, colAttrib, "col");
		rotationUnif = glGetUniformLocation(program, "rotation");

		glBindBuffer(GL_ARRAY_BUFFER, 0);
	}

	void draw()
	{
		import std.math : sin, cos, PI;

		glViewport(0, 0, winWidth, winHeight);
		glClearColor (0.15f, 0.15f, 0.15f, 0.5f);
		glClear (GL_COLOR_BUFFER_BIT);

		immutable speedDiv = 5f;
		immutable msecs = (MonoTime.currTime - startTime).total!"msecs";
		immutable angle = ((msecs / speedDiv) % 360) * PI / 180f;

		immutable s = sin(angle);
		immutable c = cos(angle);
		immutable float[16] mat = [
			c, 0, s, 0,
			0, 1, 0, 0,
			-s, 0, c, 0,
			0, 0, 0, 1,
		];

		glUniformMatrix4fv(rotationUnif, 1, GL_FALSE, mat.ptr);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glVertexAttribPointer(posAttrib, 4, GL_FLOAT, GL_FALSE, 0, null);
		glVertexAttribPointer(colAttrib, 4, GL_FLOAT, GL_FALSE, 0, cast(void*)(3*4*4));
		glEnableVertexAttribArray(posAttrib);
		glEnableVertexAttribArray(colAttrib);

		glDrawArrays(GL_TRIANGLES, 0, 3);

		glDisableVertexAttribArray(colAttrib);
		glDisableVertexAttribArray(posAttrib);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		eglSwapBuffers (dpy.eglDisplay, eglSurf);
	}

	void destroy()
	{
		glUseProgram(0);
		glDeleteProgram(program);
		glDeleteBuffers(1, &vbo);
		eglDestroySurface(dpy.eglDisplay, eglSurf);
		eglWin.destroy();
		topLevel.destroy();
		xdgSurf.destroy();
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
	version(WlDynamic)
	{
		wlClientDynLib.load();
		wlEglDynLib.load();
		wlCursorDynLib.load();
	}

	auto dpy = new Display();
	scope(exit) dpy.destroy();
	auto win = new EglWindow(dpy);
	scope(exit) win.destroy();

	dpy.window = win;

	while(win.running)
	{
		if (win.configured) dpy.display.dispatch();
		else dpy.display.dispatchPending();
		win.draw();
	}

	return 0;
}
