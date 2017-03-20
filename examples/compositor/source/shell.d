module shell;

import compositor;
import output;
import wayland.server;

import std.stdio;
import std.algorithm;
import std.range;

class Shell : WlShell
{
    Compositor comp;
    ShellSurface[] topLevels;

    this (Compositor comp)
    {
        super(comp.display, ver);
        this.comp = comp;
    }

    void addTopLevel(ShellSurface ss)
    {
        topLevels ~= ss;
        ss.addDestroyListener((WlResource res) {
            topLevels = topLevels.remove!(tl => res is tl);
        });
    }

    void mouseButton(int x, int y, int button, WlPointer.ButtonState state)
    {
        foreach(tl; retro(topLevels))
        {
            if (x >= tl.x && x < tl.x+tl.width &&
                y >= tl.y && y < tl.y+tl.height)
            {
                comp.seat.mouseButton(tl.client, button, state);
                break;
            }
        }
    }

    // paint windows over background (last inserted on top)
    // a more general algorithm should be needed for other kinds of surfaces (eg. cursors)
    void paint(Output output)
    {
        immutable ow = output.width;
        immutable oh = output.height;
        auto ob = output.buf;
        foreach (tl; topLevels)
        {
            if (!(tl.surf.outputMask & output.mask)) continue;

            auto sb = tl.surf.state.buffer;
            auto sd = cast(uint[])sb.beginAccess();
            scope(exit) sb.endAccess();

            if (tl.unplaced)
            {
                tl.x = (ow - sb.width) / 2;
                tl.y = (oh - sb.height) / 2;
                tl.unplaced = false;
            }

            tl.width = sb.width;
            tl.height = sb.height;

            if (tl.x > ow) break;

            if (sb.format == WlShm.Format.xrgb8888)
            {
                // no blending
                foreach (r; 0 .. sb.height)
                {
                    if (r + tl.y > oh) break;

                    immutable srcFrom = r*sb.stride/4;
                    immutable destFrom = (r+tl.y) * ow + tl.x;
                    immutable copyWidth = min(
                        sb.width, ow - tl.x
                    );
                    ob[destFrom .. destFrom+copyWidth] =
                            sd[srcFrom .. srcFrom+copyWidth];
                }
            }
            else
            {
                assert(sb.format == WlShm.Format.argb8888);
                // inefficient blending
                foreach (r; 0 .. sb.height)
                {
                    if (r + tl.y > oh) break;

                    foreach (c; 0 .. sb.width)
                    {
                        if (c + tl.x > ow) break;

                        immutable size_t srcInd = r*sb.stride/4 + c;
                        immutable size_t destInd = (r+tl.y) * ow + tl.x+c;

                        immutable uint dest = ob[destInd];
                        immutable uint aDest = (dest & 0xff000000) >>> 24;
                        immutable uint rDest = (dest & 0xff0000) >>> 16;
                        immutable uint gDest = (dest & 0xff00) >>> 8;
                        immutable uint bDest = (dest & 0xff);

                        immutable uint src = sd[srcInd];
                        immutable uint aSrc = (src & 0xff000000) >>> 24;
                        immutable uint rSrc = (src & 0xff0000) >>> 16;
                        immutable uint gSrc = (src & 0xff00) >>> 8;
                        immutable uint bSrc = (src & 0xff);

                        auto aRes = aSrc + aDest*(255 - aSrc) / 255;

                        auto rRes = ((aSrc*rSrc) + (255-aSrc)*(aDest*rDest)/255) / aRes;
                        auto gRes = ((aSrc*gSrc) + (255-aSrc)*(aDest*gDest)/255) / aRes;
                        auto bRes = ((aSrc*bSrc) + (255-aSrc)*(aDest*bDest)/255) / aRes;

                        if (aRes > 0xff) aRes = 0xff;
                        if (rRes > 0xff) rRes = 0xff;
                        if (gRes > 0xff) gRes = 0xff;
                        if (bRes > 0xff) bRes = 0xff;

                        ob[destInd] = aRes << 24 | rRes << 16 | gRes << 8 | bRes;
                    }
                }
            }
        }
    }

    // WlShell

    override WlShellSurface getShellSurface(WlClient cl, Resource res, uint id, WlSurface surf)
    {
        return new ShellSurface(cl, id, cast(Surface)surf, res, comp);
    }
}


class ShellSurface : WlShellSurface
{
    Surface surf;
    WlShell.Resource shRes;
    Compositor comp;
    bool unplaced = true;
    int x; int y;
    int width; int height;

    this(WlClient cl, uint id, Surface surf, WlShell.Resource shRes, Compositor comp)
    {
        super(cl, ver, id);
        this.surf = surf;
        this.shRes = shRes;
        this.comp = comp;
    }

    @property Shell shell()
    {
        return cast(Shell)shRes.outer;
    }

    // WlShellSurface

    override protected void pong(WlClient cl,
                                 uint serial)
    {}

    override protected void move(WlClient cl,
                                 WlSeat.Resource seat,
                                 uint serial)
    {}

    override protected void resize(WlClient cl,
                                   WlSeat.Resource seat,
                                   uint serial,
                                   Resize edges)
    {}


    override protected void setToplevel(WlClient cl)
    {
        try {
            surf.assignRole("shell");
            auto output = comp.outputs[0];
            surf.outputMask = surf.outputMask | output.mask;
            shell.addTopLevel(this);
        }
        catch (Exception ex)
        {
            shRes.postError(WlShell.Error.role, ex.msg);
        }
    }

    override protected void setTransient(WlClient cl,
                                         WlSurface parent,
                                         int x,
                                         int y,
                                         Transient flags)
    {}

    override protected void setFullscreen(WlClient cl,
                                          FullscreenMethod method,
                                          uint framerate,
                                          WlOutput.Resource outputRes)
    {}

    override protected void setPopup(WlClient cl,
                                     WlSeat.Resource seat,
                                     uint serial,
                                     WlSurface parent,
                                     int x,
                                     int y,
                                     Transient flags)
    {}

    override protected void setMaximized(WlClient cl,
                                         WlOutput.Resource output)
    {}

    override protected void setTitle(WlClient cl,
                                     string title)
    {

    }

    override protected void setClass(WlClient cl,
                                     string class_)
    {}

}
