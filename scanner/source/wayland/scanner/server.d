// Copyright © 2017-2021 Rémi Thebault
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
    override Interface makeInterface(Element el, Protocol protocol)
    {
        return new ServerInterface(el, protocol);
    }
    override Message makeMessage(Element el, Interface iface)
    {
        return new ServerMessage(el, iface);
    }
    override Arg makeArg(Element el)
    {
        return new ServerArg(el);
    }
}


// Server bindings implementation notes:
// There are two kind of server objects: globals and resources.
//
// Globals inherit WlGlobal and are to be created by the compositor at startup.
// Each created global is announced by the registry to the client.
// `[Global].bind` function create a `[Global].Resource` object whose implementation
// is set automatically to the outer Global object, which MUST override the abstract
// request handlers.
//
// Resources inherit WlResource. They are created by global or other parent resource
// objects upon client requests. These resources must be subclassed by the application
// and their abstract request handlers must be overriden.


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
            case ArgType.Array:
            case ArgType.Fd:
                return Arg.dType;
            case ArgType.NewId:
                return "uint";
            case ArgType.Object:
                if (iface.length)
                {
                    auto i = ServerInterface.get(iface);
                    if (i && i.isGlobal) {
                        return i.dName ~ ".Resource";
                    }
                    else if (i && !i.isGlobal) {
                        return i.dName;
                    }
                }
                return "WlResource";
        }
    }

    override @property string cType() const
    {
        final switch(type) {
            case ArgType.Int:
            case ArgType.UInt:
            case ArgType.Fixed:
            case ArgType.String:
            case ArgType.Array:
            case ArgType.Fd:
            case ArgType.Object:
                return Arg.cType;
            case ArgType.NewId:
                return "uint";
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
    this (Element el, Interface iface)
    {
        super(el, iface);
    }

    @property ServerInterface svIface()
    {
        return cast(ServerInterface)iface;
    }

    @property auto svArgs()
    {
        return args.map!(a => cast(ServerArg)a);
    }

    @property string reqMethodName()
    {
        return camelName(name);
    }

    @property string sendName()
    {
        return "send" ~ titleCamelName(name);
    }

    @property string privRqListenerStubName()
    {
        return format("wl_d_%s_%s", ifaceName, name);
    }

    @property string[] reqRtArgs()
    {
        string[] rtArgs = [ "WlClient cl" ];
        if (iface.isGlobal) rtArgs ~= format(
            "%s res", svIface.selfResType(Yes.local)
        );
        foreach (a; args) {
            if (a.type == ArgType.NewId && !a.iface.length)
            {
                rtArgs ~= [
                    "string iface", "uint ver", format("uint %s", a.paramName)
                ];
            }
            else {
                rtArgs ~= format("%s %s", a.dType, a.paramName);
            }
        }
        return rtArgs;
    }

    @property string reqRetStr()
    {
        final switch(reqType)
        {
        case ReqType.newObj:
            return ifaceDName(reqRet.iface);
        case ReqType.dynObj:
            return "WlResource";
        case ReqType.void_:
            return "void";
        }
    }

    void writeReqMethodDecl(SourceFile sf, string[] attrs)
    {
        writeFnSigRaw(sf, attrs.join(" "), reqRetStr, reqMethodName, reqRtArgs);
        sf.writeln(";");
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
            "cast(WlClient)ObjectCache.get(natCl)",
        ];
        if (iface.isGlobal) exprs ~= "_res";
        foreach (a; args) {
            if (a.type == ArgType.Object)
            {
                rtArgs ~= format("wl_resource* %s", a.paramName);
                // TODO: check if wl_resource_get_user_data could work here
                exprs ~= format("cast(%s)ObjectCache.get(%s)", a.dType, a.paramName);
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
                immutable resType = svIface.selfResType(No.local);
                sf.writeln("auto _res = cast(%s)wl_resource_get_user_data(natRes);", resType);
                immutable outer = iface.isGlobal ? ".outer" : "";
                writeFnExpr(sf, format("_res%s.%s", outer, reqMethodName), exprs);
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


    static ServerInterface get(string name)
    {
        auto i = Interface.get(name);
        if (i) return cast(ServerInterface)i;
        else return null;
    }


    this (Element el, Protocol protocol)
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

    string selfResType(Flag!"local" local)
    {
        if (local) {
            return isGlobal ? "Resource" : dName;
        }
        else {
            return dName ~ (isGlobal ? ".Resource" : "");
        }
    }

    @property string bindFuncName()
    {
        return format("wl_d_bind_%s", name);
    }

    @property string listenerStubsStructName()
    {
        return format("%sListenersAggregate", titleCamelName(name));
    }

    @property string listenerStubsSymbol()
    {
        return format("%sListeners", camelName(name));
    }

    override void writeCode(SourceFile sf)
    {
        description.writeCode(sf);
        immutable heritage = name == "wl_display" ? " : WlDisplayBase" :
                (isGlobal ? " : WlGlobal" : " : WlResource");
        immutable attrs = name == "wl_display" ? "" :
                (requests.length ? "abstract " : "");
        sf.writeln("%sclass %s%s", attrs, dName, heritage);
        sf.bracedBlock!({
            writeVersion(sf);
            sf.writeln();
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

            if (name != "wl_display")
            {
                if (isGlobal)
                {
                    writeGlobalCode(sf);
                }
                else
                {
                    writeResourceCode(sf);
                }
            }
        });
    }

    void writeIfaceAccess(SourceFile sf)
    {
        sf.writeln("/// Access to the interface of \"%s.%s\"", protocol.name, name);
        sf.writeln("static @property immutable(WlInterface) iface()");
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
                sf.writeln("/// Op-code of %s.%s.", name, msg.name);
                sf.writeln("enum %s = %d;", msg.opCodeName, i);
            }
            sf.writeln();
            foreach(msg; events)
            {
                sf.writeln(
                    "/// Version of %s protocol introducing %s.%s.",
                    protocol.name, name, msg.name
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
                    protocol.name, name, msg.name
                );
                sf.writeln("enum %sSinceVersion = %d;", camelName(msg.name), msg.since);
            }
        }
    }

    void writeGlobalCode(SourceFile sf)
    {
        sf.writeln();
        sf.writeln("protected this(WlDisplay dpy, uint ver)");
        sf.bracedBlock!({
            sf.writeln("super(wl_global_create(");
            sf.indentedBlock!({
                sf.writeln("dpy.native, iface.native, ver, cast(void*)this, &%s", bindFuncName);
            });
            sf.writeln("));");
        });
        sf.writeln();
        sf.writeln("/// Create a Resource object when a client connects.");
        sf.writeln("Resource bind(WlClient cl, uint ver, uint id)");
        sf.bracedBlock!({
            sf.writeln("return new Resource(cl, ver, id);");
        });
        foreach(rq; svRequests)
        {
            sf.writeln();
            rq.description.writeCode(sf);
            rq.writeReqMethodDecl(sf, ["abstract", "protected"]);
        }
        sf.writeln();
        writeResourceCodeForGlobal(sf);
    }

    void writeResourceCodeForGlobal(SourceFile sf)
    {
        sf.writeln("class Resource : WlResource");
        sf.bracedBlock!({
            writeResourceCtors(sf, []);
            foreach(ev; svEvents)
            {
                sf.writeln();
                ev.writeSendResMethod(sf);
            }
        });
    }

    void writeResourceCode(SourceFile sf)
    {
        sf.writeln();
        writeResourceCtors(sf, ["protected"]);
        foreach(rq; svRequests)
        {
            sf.writeln();
            rq.description.writeCode(sf);
            rq.writeReqMethodDecl(sf, ["abstract", "protected"]);
        }
        foreach(ev; svEvents)
        {
            sf.writeln();
            ev.writeSendResMethod(sf);
        }
    }

    void writeResourceCtors(SourceFile sf, string[] attrs)
    {
        immutable attrStr = attrs.join(" ") ~ (attrs.length ? " " : "");
        sf.writeln("%sthis(WlClient cl, uint ver, uint id)", attrStr);
        sf.bracedBlock!({
            immutable natExpr = "wl_resource_create(cl.native, iface.native, ver, id)";
            if (requests.length)
            {
                sf.writeln("auto native = %s;", natExpr);
                writeFnExpr(sf, "wl_resource_set_implementation", [
                    "native", format("&%s", listenerStubsSymbol),
                    "cast(void*)this", "null"
                ]);
                sf.writeln("super(native);");
            }
            else
            {
                sf.writeln("super(%s);", natExpr);
            }
        });
        sf.writeln();
        sf.writeln("%sthis(wl_resource* natRes)", attrStr);
        sf.bracedBlock!({
            sf.writeln("super(natRes);");
        });
    }

    void writePrivBindStub(SourceFile sf)
    {
        sf.writeln("void %s(wl_client* natCl, void* data, uint ver, uint id)", bindFuncName);
        sf.bracedBlock!({
            sf.writeln("nothrowFnWrapper!({");
            sf.indentedBlock!({
                sf.writeln("auto g = cast(%s)data;", dName);
                sf.writeln("auto cl = cast(WlClient)ObjectCache.get(natCl);");
                sf.writeln(`assert(g && cl, "%s: could not get global or client from cache");`, bindFuncName);
                sf.writeln("g.bind(cl, ver, id);");
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
    }

    void writePrivRqListenerStubsSymbol(SourceFile sf)
    {
        sf.writeln("__gshared %s = %s (", listenerStubsSymbol, listenerStubsStructName);
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
        foreach(iface; svIfacesWithRq.filter!(i=>i.name != "wl_display"))
        {
            sf.writeln();
            iface.writePrivRqListenerStubsSymbol(sf);
        }
    }

    override void writePrivIfaces(SourceFile sf)
    {
        foreach(iface; ifaces)
        {
            sf.writeln("immutable WlInterface %sIface;", camelName(iface.name));
        }

        writeNativeIfaces(sf);
    }

    override void writeNativeIfacesAssignment(SourceFile sf)
    {
        foreach (iface; ifaces)
        {
            sf.writeln("%sIface = new immutable WlInterface ( &wl_ifaces[%s] );",
                camelName(iface.name), indexSymbol(iface.name)
            );
        }
    }
}
