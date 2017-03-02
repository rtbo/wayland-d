// Copyright © 2017 Rémi Thebault
/++
 +  Wayland scanner for D.
 +  Generation of server protocol code.
 +/
module wayland.scanner.server;

import wayland.scanner;
import wayland.scanner.common;

import arsd.dom;

import std.algorithm;
import std.format;

alias Interface = wayland.scanner.common.Interface;

class ServerFactory : Factory
{
    override Protocol makeProtocol(Element el)
    {
        return new ServerProtocol(el);
    }
    override Interface makeInterface(Element el, string protocolName)
    {
        return new ServerInterface(el, protocolName);
    }
    override Message makeMessage(Element el, string ifaceName)
    {
        return new ServerMessage(el, ifaceName);
    }
    override Arg makeArg(Element el)
    {
        return new ServerArg(el);
    }
}



class ServerArg : Arg
{
    this(Element el)
    {
        super(el);
    }


    override @property string dType() const
    {
        final switch(type) {
            case ArgType.Int:
            case ArgType.UInt:
            case ArgType.Fixed:
            case ArgType.String:
            case ArgType.NewId:
            case ArgType.Array:
            case ArgType.Fd:
                return Arg.dType;
            case ArgType.Object:
                if (iface.length)
                    return ifaceDName(iface) ~ ".Resource";
                else
                    return "WlResource";
        }
    }

    override @property string cCastExpr() const
    {
        final switch(type) {
            case ArgType.Int:
            case ArgType.UInt:
            case ArgType.Fixed:
            case ArgType.String:
            case ArgType.NewId:
            case ArgType.Array:
            case ArgType.Fd:
                return Arg.cCastExpr;
            case ArgType.Object:
                return format("%s.native", paramName);
        }
    }
}


class ServerMessage : Message
{
    this (Element el, string ifaceName)
    {
        super(el, ifaceName);
    }

    @property auto svArgs()
    {
        return args.map!(a => cast(ServerArg)a);
    }

    @property string sendName()
    {
        return "send" ~ titleCamelName(name);
    }

    void writeSendResMethod(SourceFile sf)
    {
        description.writeCode(sf);
        string[] rtArgs;
        string[] exprs = [
            "this.native",
            opCodeName,
        ];
        foreach (arg; args)
        {
            rtArgs ~= format("%s %s", arg.dType, arg.paramName);
            exprs ~= arg.cCastExpr;
        }
        writeSig(sf, "void", sendName, rtArgs);
        writeBody(sf, [], "wl_resource_post_event", exprs, []);
    }
}


class ServerInterface : Interface
{
    this (Element el, string protocol)
    {
        super(el, protocol);
    }

    @property auto svRequests()
    {
        return requests.map!(m => cast(ServerMessage)m);
    }

    @property auto svEvents()
    {
        return events.map!(m => cast(ServerMessage)m);
    }

    override void writeCode(SourceFile sf)
    {
        description.writeCode(sf);
        immutable heritage = name == "wl_display" ? " : WlDisplayBase" : "";
        sf.writeln("class %s%s", dName, heritage);
        sf.bracedBlock!({
            if (name == "wl_display")
            {
                sf.writeln("this(wl_display* native)");
                sf.bracedBlock!({
                    sf.writeln("super(native);");
                });
            }

            writeConstants(sf);

            foreach (en; enums)
            {
                sf.writeln();
                en.writeCode(sf);
            }
            if (enums.length) sf.writeln();

            if (name != "wl_display")
            {
                if (isGlobal)
                {
                    writeGlobalCode(sf);
                    sf.writeln();
                }
                writeResourceCode(sf);
            }
        });
    }

    void writeConstants(SourceFile sf)
    {
        if (events.length)
        {
            foreach(i, msg; events)
            {
                sf.writeln("/// Op-code of %s.%s.", dName, msg.dMethodName);
                sf.writeln("enum %s = %d;", msg.opCodeName, i);
            }
            sf.writeln();
            foreach(msg; events)
            {
                sf.writeln(
                    "/// Version of %s protocol introducing %s.%s.",
                    protocol, dName, msg.dMethodName
                );
                sf.writeln("enum %sSinceVersion = %d;", camelName(msg.name), msg.since);
            }
        }
        if (requests.length)
        {
            sf.writeln();
            foreach(msg; requests)
            {
                sf.writeln(
                    "/// %s protocol version introducing %s.%s.",
                    protocol, dName, msg.dHandlerName
                );
                sf.writeln("enum %sSinceVersion = %d;", msg.dHandlerName, msg.since);
            }
        }
    }

    void writeGlobalCode(SourceFile sf)
    {
        sf.writeln("static class Global : WlGlobal");
        sf.bracedBlock!({
            sf.writeln("this(wl_global* native)");
            sf.bracedBlock!({
                sf.writeln("super(native);");
            });
        });
    }

    void writeResourceCode(SourceFile sf)
    {
        sf.writeln("static class Resource : WlResource");
        sf.bracedBlock!({
            sf.writeln("this(wl_resource* native)");
            sf.bracedBlock!({
                sf.writeln("super(native);");
            });
            foreach(ev; svEvents)
            {
                sf.writeln();
                ev.writeSendResMethod(sf);
            }
        });
    }

    override void writePrivListener(SourceFile sf)
    {

    }

    override void writePrivListenerStubs(SourceFile sf)
    {

    }
}

class ServerProtocol : Protocol
{
    this(Element el)
    {
        super(el);
    }

    override void writeCode(SourceFile sf, in Options opt)
    {
        writeHeader(sf, opt);
        if (name == "wayland") sf.writeln("import wayland.server.core;");
        else sf.writeln("import wayland.server;");
        sf.writeln("import wayland.native.server;");
        sf.writeln("import wayland.native.util;");
        sf.writeln("import wayland.util;");
        sf.writeln("import std.string : toStringz;");
        sf.writeln();

        foreach(iface; ifaces)
        {
            iface.writeCode(sf);
            sf.writeln();
        }

        // writing private code
        sf.writeln("private:");
        sf.writeln();

        writePrivIfaces(sf);
        sf.writeln();

        sf.writeln("extern(C) nothrow");
        sf.bracedBlock!({
            foreach(i, iface; ifaces)
            {
                if (i != 0) sf.writeln();
                //iface.writePrivServerListener(sf);
                //iface.writePrivServerListenerStubs(sf);
            }
        });
    }

    override void writePrivIfaces(SourceFile sf)
    {
        foreach(iface; ifaces)
        {
            sf.writeln("immutable WlServerInterface %sIface;", camelName(iface.name));
        }
        foreach (iface; ifaces)
        {
            sf.writeln();
            sf.writeln("immutable final class %sIface : WlServerInterface",
                    titleCamelName(iface.name));
            sf.bracedBlock!({
                sf.writeln("this(immutable wl_interface* native)");
                sf.bracedBlock!({
                    sf.writeln("super(native);");
                });
                sf.writeln("override WlResource makeResource(wl_resource* resource) immutable");
                sf.bracedBlock!({
                    if (iface.name == "wl_display")
                        sf.writeln("assert(false, \"Display cannot have any resource!\");");
                    else
                        sf.writeln("return new %s.Resource(resource);", iface.dName);
                });
                if (iface.isGlobal)
                {
                    sf.writeln("override WlGlobal makeGlobal(wl_global* global) immutable");
                    sf.bracedBlock!({
                        if (iface.name == "wl_display")
                            sf.writeln("assert(false, \"Display cannot have any global!\");");
                        else
                            sf.writeln("return new %s.Global(global);", iface.dName);
                    });
                }
            });
        }
        writeNativeIfaces(sf);
    }
}
