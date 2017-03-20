module output;

import compositor;
import wayland.server;

import std.stdio;
import core.time;


class Output : WlOutput
{
    private Compositor _comp;

    private uint _mask;
    private bool _repaintNeeded;
    private bool _repaintScheduled;
    private WlTimerEventSource _repaintTimer;
    private WlTimerEventSource _finishFrameTimer;
    private MonoTime _startRepaint;
    enum refreshNsecs = 1_000_000_000 / 60;


    this(Compositor comp)
    {
        _comp = comp;
        super(comp.display, 3);
        _repaintTimer = _comp.display.eventLoop.addTimer(&timerRepaint);
        _finishFrameTimer = _comp.display.eventLoop.addTimer(() {
            finishFrame(_startRepaint);
            return 1;
        });

    }

    abstract @property int width();
    abstract @property int height();
    abstract @property uint[] buf();
    abstract void blitBuf();

    @property uint mask()
    {
        return _mask;
    }

    @property void mask(uint mask)
    {
        _mask = mask;
    }

    void scheduleRepaint()
    {
        _repaintNeeded = true;
        if (_repaintScheduled) return;
        _comp.display.eventLoop.addIdle(&idleRepaint);
        _repaintScheduled = true;
    }

    void idleRepaint()
    {
        startRepaintLoop();
    }

    void startRepaintLoop()
    {
        finishFrame(MonoTime.currTime);
    }

    void finishFrame(MonoTime stamp)
    {
        auto now = MonoTime.currTime;
        auto gone = now - stamp;
        auto msecs = (refreshNsecs - gone.total!"nsecs")/1000000;

        if (msecs < 1) {
            timerRepaint();
        }
        else {
            _repaintTimer.update(cast(uint)msecs);
        }
    }

    int timerRepaint()
    {
        _startRepaint = MonoTime.currTime;

        auto w = width;
        auto h = height;
        auto b = buf;

        // background: a 32*32 grid
        foreach (c; 0 .. w)
        {
            foreach (r; 0 .. h)
            {
                if (r % 32 == 0 || c % 32 == 0)
                {
                    b[r*w + c] = 0;
                }
                else
                {
                    b[r*w + c] = 0xffffffff;
                }
            }
        }

        _comp.shell.paint(this);

        blitBuf();
        _finishFrameTimer.update(10);
        return 1;
    }

    // WlOutput
    override void release(WlClient cl, Resource res)
    {}
}
