module hello;

// this is a port of https://github.com/hdante/hello_wayland

import hello_helper;

import wayland.client;
import wayland.native.client;
import wayland.util;

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
		if(iface == wlCompositorInterface.name)
		{
			compositor = cast(WlCompositor)reg.bind(
				name, wlCompositorInterface, min(ver, 4)
			);
		}
		else if(iface == wlShmInterface.name)
		{
			shm = cast(WlShm)reg.bind(
				name, wlShmInterface, min(ver, 1)
			);
		}
		else if(iface == wlShellInterface.name)
		{
			shell = cast(WlShell)reg.bind(
				name, wlShellInterface, min(ver, 1)
			);
		}
		else if(iface == wlSeatInterface.name)
		{
			seat = cast(WlSeat)reg.bind(
				name, wlSeatInterface, min(ver, 2)
			);
			pointer = seat.getPointer();
			pointer.onEnter = &pointerEnter;
			pointer.onButton = &pointerButton;
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
		seat.destroy();
		shell.destroy();
		shm.destroy();
		compositor.destroy();
		display.disconnect();
	}
}
