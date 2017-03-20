module backend.x11;

import backend;
import compositor;
import output;

import wayland.server;
import wayland.util.shm_helper;
import linux.input;
import xcb.xcb;
import xcb.xkb;
import xcb.shm;
import X11.Xlib;
import X11.Xlib_xcb;
import xkbcommon.xkbcommon;
import xkbcommon.x11;

import std.exception;
import std.stdio;
import core.stdc.stdlib;
import core.sys.posix.sys.mman;
import core.sys.posix.unistd;

/// X11 backend implementation
final class X11Backend : Backend
{
    private {
        BackendConfig config;
        Compositor comp;

        WlEventLoop loop;
        WlFdEventSource xcbSource;

        Display* dpy;
        xcb_connection_t* conn;
        Atoms atoms;

        X11Output[] _outputs;
    }


    override @property string name()
    {
        return "x11";
    }

    override void initialize(BackendConfig config, Compositor comp)
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
        auto res = new X11Output(this);
        res.initShm();
        _outputs ~= res;
        return res;
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

            auto respType = ev.response_type & ~0x80;
            switch(respType)
            {
            case XCB_BUTTON_PRESS:
            case XCB_BUTTON_RELEASE:
                deliverButtonEvent(cast(xcb_button_press_event_t*)ev);
                break;
            case XCB_CLIENT_MESSAGE:
                auto clEv = cast(xcb_client_message_event_t*)ev;
                auto atom = clEv.data.data32[0];
                auto win = clEv.window;
                if (atom == atoms.wm_delete_window)
                {
                    loop.addIdle({
                        foreach(op; _outputs)
                        {
                            if (op._win == win)
                            {
                                destroyOutput(op);
                                break;
                            }
                        }
                    });
                }
                break;
            default:
                break;
            }

            ++count;
        }
        return count;
    }

    void deliverButtonEvent(xcb_button_press_event_t* ev)
    {
        uint but;
        switch (ev.detail) {
        case 1:
            but = BTN_LEFT;
            break;
        case 2:
            but = BTN_MIDDLE;
            break;
        case 3:
            but = BTN_RIGHT;
            break;
        default:
            stderr.writeln("X11 backend unknown button code: ", ev.detail);
            break;
        }

        immutable state = ev.response_type == XCB_BUTTON_PRESS ?
            WlPointer.ButtonState.pressed : WlPointer.ButtonState.released;

        comp.eventMouseButton(ev.event_x, ev.event_y, but, state);
    }

    void destroyOutput(X11Output op)
    {
        import std.algorithm : remove;
        _outputs = _outputs.remove!(o => o is op);
        op.destroy();
        if (!_outputs.length) comp.exit();
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


xcb_visualtype_t* findVisualById(xcb_screen_t* screen, xcb_visualid_t id)
{
	xcb_depth_iterator_t i;
	xcb_visualtype_iterator_t j;
	for (i = xcb_screen_allowed_depths_iterator(screen);
	     i.rem;
	     xcb_depth_next(&i)) {
		for (j = xcb_depth_visuals_iterator(i.data);
		     j.rem;
		     xcb_visualtype_next(&j)) {
			if (j.data.visual_id == id)
				return j.data;
		}
	}
	return null;
}

ubyte getDepthOfVisual(xcb_screen_t* screen, xcb_visualid_t id)
{
	xcb_depth_iterator_t i;
	xcb_visualtype_iterator_t j;
	for (i = xcb_screen_allowed_depths_iterator(screen);
	     i.rem;
	     xcb_depth_next(&i)) {
		for (j = xcb_depth_visuals_iterator(i.data);
		     j.rem;
		     xcb_visualtype_next(&j)) {
			if (j.data.visual_id == id)
				return i.data.depth;
		}
	}
	return 0;
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

    private ubyte _depth;
    private xcb_format_t* _xcbFmt;
    private int _shmFd;
    private xcb_shm_seg_t _shmSeg;
    private uint[] _buf;
    private xcb_gcontext_t _gc;

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

        super(backend.comp);

        assert(_fullscreen || _width*_height > 0);

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

    void initShm()
    {
        auto shmExt = xcb_get_extension_data(_conn, &xcb_shm_id);
        enforce(shmExt && shmExt.present);
        auto visType = findVisualById(_screen, _screen.root_visual);
        _depth = getDepthOfVisual(_screen, _screen.root_visual);

        for (auto fmt = xcb_setup_pixmap_formats_iterator(xcb_get_setup(_conn));
                fmt.rem;
                xcb_format_next(&fmt)) {
            if (fmt.data.depth == _depth) {
                _xcbFmt = fmt.data;
                break;
            }
        }
        enforce(_xcbFmt && _xcbFmt.bits_per_pixel == 32);

        immutable segSize = _width*_height*4;

        _shmFd = createMmapableFile(segSize);
        auto ptr = cast(ubyte*)enforce(mmap(
            null, segSize, PROT_READ | PROT_WRITE, MAP_SHARED, _shmFd, 0
        ));
        _buf = cast(uint[])(ptr[0 .. segSize]);
        _shmSeg = xcb_generate_id(_conn);
        auto err = xcb_request_check(_conn, xcb_shm_attach_fd_checked(
            _conn, _shmSeg, _shmFd, 0
        ));
        enforce(!err);

        _gc = xcb_generate_id(_conn);
        xcb_create_gc(_conn, _gc, _win, 0, null);
    }

    override @property int width()
    {
        return _width;
    }

    override @property int height()
    {
        return _height;
    }

    override @property uint[] buf()
    {
        return _buf;
    }

    override void blitBuf()
    {
	    auto err = xcb_request_check(_conn,
            xcb_shm_put_image_checked(
                _conn, _win, _gc,
                cast(ushort)_width, cast(ushort)_height, 0, 0,
                cast(ushort)_width, cast(ushort)_height, 0, 0,
                _depth, XCB_IMAGE_FORMAT_Z_PIXMAP,
                0, _shmSeg, 0
            )
        );
        if (err) {
            stderr.writeln("error while blitting x11");
        }
    }

    override void destroy()
    {
        super.destroy();
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
