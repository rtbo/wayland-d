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
import std.range;

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

    @property string reqDgAliasName()
    {
        return "On" ~ titleCamelName(name) ~ "Dg";
    }

    @property string reqDgMemberName()
    {
        return "_on" ~ titleCamelName(name) ~ "Dg";
    }

    @property string reqDgPropName()
    {
        return "on" ~ titleCamelName(name);
    }

    @property string sendName()
    {
        return "send" ~ titleCamelName(name);
    }

    @property string privRqListenerStubName()
    {
        return format("wl_d_on_%s_%s", ifaceName, name);
    }

    void writeReqDelegateAlias(SourceFile sf)
    {
        string[] rtArgs = [
            "WlClient cl", "WlResource res"
        ];
        foreach (a; args) {
            if (a.type == ArgType.Object)
            {
                rtArgs ~= format("WlResource %s", a.paramName);
            }
            else if (a.type == ArgType.NewId && !a.iface.length)
            {
                rtArgs ~= [
                    "string iface", "uint ver", format("uint %s", a.paramName)
                ];
            }
            else {
                rtArgs ~= format("%s %s", a.dType, a.paramName);
            }
        }
        writeDelegateAlias(sf, reqDgAliasName, "void", rtArgs);
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
        sf.writeFnSig("void", sendName, rtArgs);
        sf.writeFnBody([], "wl_resource_post_event", exprs, []);
    }

    void writePrivRqListenerStub(SourceFile sf)
    {
        string[] rtArgs = [
            "wl_client* natCl", "wl_resource* natRes",
        ];
        string[] exprs = [
            "cast(WlClient)ObjectCache.get(natCl)", "_res",
        ];
        foreach (a; args) {
            if (a.type == ArgType.Object)
            {
                rtArgs ~= format("wl_resource* %s", a.paramName);
                exprs ~= format("cast(WlResource)ObjectCache.get(%s)", a.paramName);
            }
            else if (a.type == ArgType.NewId && !a.iface.length)
            {
                rtArgs ~= [
                    "const(char)* iface", "uint ver", format("uint %s", a.paramName)
                ];
                exprs ~= [
                    "fromStringz(iface).idup", "ver", a.paramName
                ];
            }
            else {
                rtArgs ~= format("%s %s", a.cType, a.paramName);
                exprs ~= a.dCastExpr(ifaceName);
            }
        }
        writeFnSig(sf, "void", privRqListenerStubName, rtArgs);
        sf.bracedBlock!({
            sf.writeln("nothrowFnWrapper!({");
            sf.indentedBlock!({
                sf.writeln("auto _res = cast(%s.Resource)ObjectCache.get(natRes);", ifaceDName(ifaceName));
                sf.writeln("if (_res.%s) {", reqDgMemberName);
                sf.indentedBlock!({
                    writeFnExpr(sf, format("_res.%s", reqDgMemberName), exprs);
                });
                sf.writeln("}");
            });
            sf.writeln("});");
        });
    }

    void writePrivStubSig(SourceFile sf)
    {
        string[] rtArgs = [
            "wl_client* natCl", "wl_resource* natRes",
        ];
        foreach (a; args) {
            if (a.type == ArgType.Object)
            {
                rtArgs ~= format("wl_resource* %s", a.paramName);
            }
            else if (a.type == ArgType.NewId && !a.iface.length)
            {
                rtArgs ~= [
                    "const(char)* iface", "uint ver", format("uint %s", a.paramName)
                ];
            }
            else {
                rtArgs ~= format("%s %s", a.cType, a.paramName);
            }
        }
        writeFnPointer(sf, name, "void", rtArgs);
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

    @property string onBindFuncName()
    {
        return format("wl_d_on_bind_%s", name);
    }

    @property string listenerStubsStructName()
    {
        return format("%s_listener_stub_aggregate", name);
    }

    @property string listenerStubsSymbol()
    {
        return format("wl_d_%s_listener_stubs", name);
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
                sf.writeln();
            }

            writeIfaceAccess(sf);

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

    void writeIfaceAccess(SourceFile sf)
    {
        sf.writeln("/// Access to the interface of \"%s.%s\"", protocol, name);
        sf.writeln("static @property immutable(WlServerInterface) iface()");
        sf.bracedBlock!({
            sf.writeln("return %sIface;", camelName(name));
        });
    }

    void writeConstants(SourceFile sf)
    {
        if (events.length)
        {
            sf.writeln();
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
        sf.writeln();
        sf.writeln("static class Global : WlGlobal");
        sf.bracedBlock!({
            sf.writeln("/// Bind delegate signature.");
            sf.writeln("alias OnBindDg = void delegate(WlClient cl, uint ver, uint id);");
            sf.writeln();
            sf.writeln("/// Creates a Global object.");
            sf.writeln("this(WlDisplay dpy, uint ver, OnBindDg onBindDg)");
            sf.bracedBlock!({
                sf.writeln("_onBindDg = onBindDg;");
                sf.writeln("super(wl_global_create(");
                sf.indentedBlock!({
                    sf.writeln("dpy.native, iface.native, ver, cast(void*)this, &%s", onBindFuncName);
                });
                sf.writeln("));");
            });
            sf.writeln();
            sf.writeln("private OnBindDg _onBindDg;");
        });
    }

    void writeResourceCode(SourceFile sf)
    {
        sf.writeln();
        sf.writeln("static class Resource : WlResource");
        sf.bracedBlock!({
            if (requests.length) sf.writeln();
            foreach(rq; svRequests)
            {
                rq.writeReqDelegateAlias(sf);
            }
            sf.writeln("this(wl_resource* native)");
            sf.bracedBlock!({
                sf.writeln("super(native);");
            });
            sf.writeln();
            sf.writeln("this(WlClient cl, uint ver, uint id)");
            sf.bracedBlock!({
                sf.writeln("auto native = wl_resource_create(cl.native, iface.native, ver, id);");
                if (requests.length) {
                    sf.writeln("wl_resource_set_implementation(native, &%s, cast(void*)this, null);", listenerStubsSymbol);
                }
                sf.writeln("this(native);");
            });

            foreach(rq; svRequests)
            {
                sf.writeln();
                sf.writeln("@property %s %s()", rq.reqDgAliasName, rq.reqDgPropName);
                sf.bracedBlock!({
                    sf.writeln("return %s;", rq.reqDgMemberName);
                });
                sf.writeln();
                sf.writeln("@property void %s(%s dg)", rq.reqDgPropName, rq.reqDgAliasName);
                sf.bracedBlock!({
                    sf.writeln("%s = dg;", rq.reqDgMemberName);
                });
            }

            foreach(ev; svEvents)
            {
                sf.writeln();
                ev.writeSendResMethod(sf);
            }

            if (requests.length) sf.writeln();
            foreach(rq; svRequests)
            {
                sf.writeln("private %s %s;", rq.reqDgAliasName, rq.reqDgMemberName);
            }
        });
    }

    void writePrivBindStub(SourceFile sf)
    {
        sf.writeln("void %s(wl_client* natCl, void* data, uint ver, uint id)", onBindFuncName);
        sf.bracedBlock!({
            sf.writeln("nothrowFnWrapper!({");
            sf.indentedBlock!({
                sf.writeln("auto g = cast(%s.Global)data;", dName);
                sf.writeln("auto cl = cast(WlClient)ObjectCache.get(natCl);");
                sf.writeln(`assert(g && cl, "%s: could not get global or client from cache");`, onBindFuncName);
                sf.writeln("g._onBindDg(cl, ver, id);");
            });
            sf.writeln("});");
        });
    }

    void writePrivRqListenerStubs(SourceFile sf)
    {
        sf.writeln("// %s listener stubs", name);
        foreach(rq; svRequests)
        {
            sf.writeln();
            rq.writePrivRqListenerStub(sf);
        }

        sf.writeln();
        sf.writeln("struct %s", listenerStubsStructName);
        sf.bracedBlock!({
            foreach (rq; svRequests) {
                rq.writePrivStubSig(sf);
            }
        });

        sf.writeln();
        sf.writeln("__gshared %s = %s(", listenerStubsSymbol, listenerStubsStructName);
        sf.indentedBlock!({
            foreach(rq; svRequests) {
                sf.writeln("&%s,", rq.privRqListenerStubName);
            }
        });
        sf.writeln(");");
    }
}

class ServerProtocol : Protocol
{
    this(Element el)
    {
        super(el);
    }

    @property auto svIfaces()
    {
        return ifaces.map!(i => cast(ServerInterface)i);
    }

    @property auto svGlobalIfaces()
    {
        return svIfaces.filter!(i => i.isGlobal);
    }

    @property auto svIfacesWithRq()
    {
        return svIfaces.filter!(i => i.requests.length > 0);
    }

    override void writeCode(SourceFile sf, in Options opt)
    {
        writeHeader(sf, opt);
        if (name == "wayland") sf.writeln("import wayland.server.core;");
        else sf.writeln("import wayland.server;");
        sf.writeln("import wayland.native.server;");
        sf.writeln("import wayland.native.util;");
        sf.writeln("import wayland.util;");
        sf.writeln("import std.string : toStringz, fromStringz;");
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
            bool needNL;
            foreach(iface; svGlobalIfaces.filter!(i=>i.name != "wl_display"))
            {
                if (needNL) sf.writeln();
                else needNL = true;
                iface.writePrivBindStub(sf);
            }

            foreach(iface; svIfacesWithRq.filter!(i=>i.name != "wl_display"))
            {
                if (needNL) sf.writeln();
                else needNL = true;
                iface.writePrivRqListenerStubs(sf);
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
            });
        }

        writeNativeIfaces(sf);

        sf.writeln("shared static this()");
        sf.bracedBlock!({
            foreach (iface; ifaces)
            {
                sf.writeln("WlResourceFactory.registerInterface(%sIface);",
                        camelName(iface.name));
            }
        });
    }
}
