module backend.x11;

import backend;
import output;

import wayland.server;
import xcb.xcb;
import xcb.xkb;
import X11.Xlib;
import X11.Xlib_xcb;
import xkbcommon.xkbcommon;
import xkbcommon.x11;

import core.stdc.stdlib;

/// X11 backend implementation
final class X11Backend : Backend
{
    private {
        BackendConfig config;
        CompositorBackendInterface comp;

        WlEventLoop loop;
        WlFdEventSource xcbSource;

        Display* dpy;
        xcb_connection_t* conn;
        Atoms atoms;
    }


    override @property string name()
    {
        return "x11";
    }

    override void initialize(BackendConfig config, CompositorBackendInterface comp)
    {
        this.config = config;
        this.comp = comp;
        loop = comp.display.eventLoop;

        dpy = XOpenDisplay(null);
        if (dpy is null) throw new Exception("can't open X11 display");

        scope(failure) XCloseDisplay(dpy);

        conn = XGetXCBConnection(dpy);
        XSetEventQueueOwner(dpy, XCBOwnsEventQueue);

        if (xcb_connection_has_error(conn))
        {
            throw new Exception("XCB connection has error");
        }

        atoms = new Atoms(conn);

        xcbSource = loop.addFd(
            xcb_get_file_descriptor(conn),
            WL_EVENT_READABLE,
            &handleEvent
        );
        xcbSource.check();
    }

    override Output createOutput()
    {
        return new X11Output(this);
    }

    override void terminate()
    {
        xcbSource.remove();
        XCloseDisplay(dpy);
    }

private:


    @property xcb_screen_t* defaultScreen()
    {
        int num = XDefaultScreen(dpy);

        auto iter = xcb_setup_roots_iterator(xcb_get_setup(conn));
        while (num && iter.rem)
        {
            xcb_screen_next(&iter);
            --num;
        }
        return iter.data;
    }

    int handleEvent(int, uint mask)
    {
        int count;

        while(1)
        {
            auto ev = (mask & WL_EVENT_READABLE) ?
                xcb_poll_for_event(conn) :
                xcb_poll_for_queued_event(conn);
            if (!ev) break;

            //auto respType = ev.response_type & ~0x80;

            ++count;
        }
        return count;
    }
}

private:


struct WmNormalHints
{
    enum minSize = 16;
    enum maxSize = 32;

    uint flags;
	uint[4] pad;
	int minWidth, minHeight;
	int maxWidth, maxHeight;
    int widthInc, heightInc;
    int minAspectX, minAspectY;
    int maxAspectX, maxAspectY;
	int baseWidth, baseHeight;
	int winGravity;
}

final class X11Output : Output
{
    private X11Backend _backend;
    private xcb_connection_t* _conn;
    private xcb_screen_t* _screen;
    private Atoms _atoms;
    private bool _fullscreen;
    private int _width;
    private int _height;
    private int _widthDPI;
    private int _heightDPI;
    private xcb_window_t _win;

    this (X11Backend backend)
    {
        _backend = backend;
        _conn = backend.conn;
        _screen = backend.defaultScreen;
        _atoms = backend.atoms;
        _fullscreen = backend.config.fullscreen;
        _width = backend.config.width;
        _height = backend.config.height;
        _widthDPI = cast(int) (25.4 * _screen.width_in_pixels) / _screen.width_in_millimeters;
        _heightDPI = cast(int) (25.4 * _screen.height_in_pixels) / _screen.height_in_millimeters;

        assert(_fullscreen || _width*_height > 0);
    }

    override @property int width()
    {
        return _width;
    }

    override @property int height()
    {
        return _height;
    }

    override void enable()
    {
        immutable uint mask = XCB_CW_EVENT_MASK;
        uint[2] values = [
            XCB_EVENT_MASK_EXPOSURE |
            XCB_EVENT_MASK_STRUCTURE_NOTIFY |
			XCB_EVENT_MASK_KEY_PRESS |
			XCB_EVENT_MASK_KEY_RELEASE |
			XCB_EVENT_MASK_BUTTON_PRESS |
			XCB_EVENT_MASK_BUTTON_RELEASE |
			XCB_EVENT_MASK_POINTER_MOTION |
			XCB_EVENT_MASK_ENTER_WINDOW |
			XCB_EVENT_MASK_LEAVE_WINDOW |
			XCB_EVENT_MASK_KEYMAP_STATE |
			XCB_EVENT_MASK_FOCUS_CHANGE,
            0
        ];
        _win = xcb_generate_id(_conn);
        xcb_create_window(_conn,
                cast(ubyte)XCB_COPY_FROM_PARENT,
                _win,
                _screen.root,
                0, 0,
                cast(ushort)_width, cast(ushort)_height,
                0,
                XCB_WINDOW_CLASS_INPUT_OUTPUT,
                _screen.root_visual,
                mask, values.ptr);

        if (_fullscreen)
        {
            xcb_change_property(_conn, XCB_PROP_MODE_REPLACE, _win,
                        _atoms.net_wm_state,
                        XCB_ATOM_ATOM, 32, 1, &_atoms.net_wm_state_fullscreen);
        }
        else
        {
            WmNormalHints hints;
            hints.flags = hints.maxSize | hints.minSize;
            hints.minWidth = _width;
            hints.minHeight = _height;
            hints.maxWidth = _width;
            hints.maxHeight = _height;
            xcb_change_property(_conn, XCB_PROP_MODE_REPLACE, _win,
                        _atoms.wm_normal_hints,
                        _atoms.wm_size_hints, 32,
                        hints.sizeof / 4,
                        cast(ubyte*)&hints);
        }

        enum title = "Wayland compositor";
        xcb_change_property(_conn, XCB_PROP_MODE_REPLACE, _win,
				    _atoms.net_wm_name, _atoms.utf8_string, 8,
				    title.length, title.ptr);

	    xcb_change_property (_conn, XCB_PROP_MODE_REPLACE, _win,
		            _atoms.wm_protocols,
		            XCB_ATOM_ATOM, 32, 1, &_atoms.wm_delete_window);
        xcb_map_window(_conn, _win);
        xcb_flush(_conn);
    }

    override void disable()
    {
        xcb_unmap_window(_conn, _win);
        xcb_destroy_window(_conn, _win);
        xcb_flush(_conn);
    }
}


final class Atoms
{
    xcb_atom_t		 wm_protocols;
    xcb_atom_t		 wm_normal_hints;
    xcb_atom_t		 wm_size_hints;
    xcb_atom_t		 wm_delete_window;
    xcb_atom_t		 wm_class;
    xcb_atom_t		 net_wm_name;
    xcb_atom_t		 net_supporting_wm_check;
    xcb_atom_t		 net_supported;
    xcb_atom_t		 net_wm_icon;
    xcb_atom_t		 net_wm_state;
    xcb_atom_t		 net_wm_state_fullscreen;
    xcb_atom_t		 str;
    xcb_atom_t		 utf8_string;
    xcb_atom_t		 cardinal;
    xcb_atom_t		 xkb_names;

    this(xcb_connection_t* conn)
    {
        enum numAtoms = 15;
        struct AtomName
        {
            string name;
            xcb_atom_t* atom;
        }
        AtomName[numAtoms] atomNames = [
            AtomName("WM_PROTOCOLS",             &wm_protocols),
            AtomName("WM_NORMAL_HINTS",          &wm_normal_hints),
            AtomName("WM_SIZE_HINTS",            &wm_size_hints),
            AtomName("WM_DELETE_WINDOW",         &wm_delete_window),
            AtomName("WM_CLASS", 	             &wm_class),
            AtomName("_NET_WM_NAME",             &net_wm_name),
            AtomName("_NET_WM_ICON",             &net_wm_icon),
            AtomName("_NET_WM_STATE",            &net_wm_state),
            AtomName("_NET_WM_STATE_FULLSCREEN", &net_wm_state_fullscreen),
            AtomName("_NET_SUPPORTING_WM_CHECK", &net_supporting_wm_check),
            AtomName("_NET_SUPPORTED",           &net_supported),
            AtomName("STRING",                   &str),
            AtomName("UTF8_STRING",              &utf8_string),
            AtomName("CARDINAL",                 &cardinal),
            AtomName("_XKB_RULES_NAMES",         &xkb_names),
        ];

        xcb_intern_atom_cookie_t[numAtoms] cookies = void;
        foreach (i; 0..numAtoms)
        {
            cookies[i] = xcb_intern_atom (conn, 0,
                    cast(ushort)atomNames[i].name.length,
                    atomNames[i].name.ptr);
        }
        foreach (i; 0..numAtoms)
        {
            auto rep = xcb_intern_atom_reply(conn, cookies[i], null);
            *atomNames[i].atom = rep.atom;
            free(rep);
        }
    }
}