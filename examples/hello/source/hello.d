// Copyright © 2017-2021 Rémi Thebault
module hello;

// this is a port of https://github.com/hdante/hello_wayland

import wayland.client;
import wayland.native.client;
import wayland.util;
import wayland.util.shm_helper;

import core.sys.posix.sys.mman;
import core.sys.posix.unistd;
import std.algorithm;
import std.exception;
import std.stdio;

enum winWidth = 320;
enum winHeight = 200;
enum cursorWidth = 100;
enum cursorHeight = 59;
enum cursorHotSpotX = 10;
enum cursorHotSpotY = 35;

int main()
{
	version(WlDynamic) { wlClientDynLib.load(); }

	auto hello = new Hello;
	hello.makeMemPool(cast(immutable(ubyte)[])import("images.bin"));
	hello.createSurface();
	hello.setupBuffers();
	hello.loop();
	hello.cleanUp();
	return 0;
}

class Hello
{
	WlDisplay display;
	WlCompositor compositor;
	WlPointer pointer;
	WlKeyboard kbd;
	WlSeat seat;
	WlShell shell;
	WlShm shm;

	int poolFd;
	ubyte* poolMem;
	size_t poolSize;
	WlShmPool pool;
	WlSurface surf;
	WlShellSurface shSurf;
	WlBuffer winBuf;
	WlBuffer cursorBuf;
	WlSurface cursorSurf;
	bool doneFlag;

	this()
	{
		display = enforce(WlDisplay.connect());
		auto reg = display.getRegistry();

		reg.onGlobal = &regGlobal;

		display.roundtrip();
		reg.destroy();
	}

	void regGlobal(WlRegistry reg, uint name, string iface, uint ver)
	{
		if(iface == WlCompositor.iface.name)
		{
			compositor = cast(WlCompositor)reg.bind(
				name, WlCompositor.iface, min(ver, 4)
			);
		}
		else if(iface == WlShm.iface.name)
		{
			shm = cast(WlShm)reg.bind(
				name, WlShm.iface, min(ver, 1)
			);
		}
		else if(iface == WlShell.iface.name)
		{
			shell = cast(WlShell)reg.bind(
				name, WlShell.iface, min(ver, 1)
			);
		}
		else if(iface == WlSeat.iface.name)
		{
			seat = cast(WlSeat)reg.bind(
				name, WlSeat.iface, min(ver, 2)
			);
			seat.onCapabilities = &seatCapChanged;
		}
	}

	void seatCapChanged (WlSeat seat, WlSeat.Capability cap)
	{
		if ((cap & WlSeat.Capability.pointer) && !pointer)
		{
			writeln("setup");
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


	void makeMemPool(immutable(ubyte)[] imgData)
	{
		poolFd = createMmapableFile(imgData.length);
		poolMem = cast(ubyte*)mmap(
			null, imgData.length, PROT_READ|PROT_WRITE, MAP_SHARED, poolFd, 0
		);
		enforce(poolMem !is MAP_FAILED);
		poolSize = imgData.length;
		poolMem[0 .. poolSize] = imgData[];
		pool = enforce(shm.createPool(poolFd, cast(int)poolSize));
	}

	void createSurface()
	{
		surf = enforce(compositor.createSurface());
		scope(failure) surf.destroy();

		shSurf = shell.getShellSurface(surf);
		shSurf.onPing = (WlShellSurface wlShSurf, uint serial)
		{
			wlShSurf.pong(serial);
		};

		shSurf.setToplevel();

		cursorSurf = enforce(compositor.createSurface());
	}

	void setupBuffers()
	{
		winBuf = pool.createBuffer(
			0, winWidth, winHeight, 4*winWidth, WlShm.Format.argb8888
		);
		cursorBuf = pool.createBuffer(
			winWidth*winHeight*4, cursorWidth, cursorHeight, 4*cursorWidth,
			WlShm.Format.argb8888
		);

		surf.attach(winBuf, 0, 0);
		surf.commit();
	}

	void pointerEnter(WlPointer pointer, uint serial, WlSurface surface,
						WlFixed surfaceX, WlFixed surfaceY)
	{
		cursorSurf.attach(cursorBuf, 0, 0);
		cursorSurf.commit();
		pointer.setCursor(serial, cursorSurf, cursorHotSpotX, cursorHotSpotY);
	}

	void pointerButton(WlPointer, uint serial, uint time, uint button,
						WlPointer.ButtonState state)
	{
		doneFlag = true;
	}

	void kbdKey(WlKeyboard keyboard, uint serial, uint time, uint key,
			WlKeyboard.KeyState state)
	{
		import linux.input : KEY_ESC;

		if (key == KEY_ESC && state) doneFlag = true;
	}

	void loop()
	{
		while (!doneFlag)
		{
			if (display.dispatch() < 0)
			{
				stderr.writeln("Main loop error");
				doneFlag = true;
			}
		}
	}

	void cleanUp()
	{
		cursorBuf.destroy();
		cursorSurf.destroy();
		winBuf.destroy();
		shSurf.destroy();
		surf.destroy();
		pool.destroy();
		munmap(poolMem, poolSize);
		close(poolFd);
		pointer.destroy();
		kbd.destroy();
		seat.destroy();
		shell.destroy();
		shm.destroy();
		compositor.destroy();
		display.disconnect();
	}
}
