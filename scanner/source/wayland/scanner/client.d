// Copyright © 2017-2021 Rémi Thebault
/++
 +  Wayland scanner for D.
 +  Generation of client protocol code.
 +/
module wayland.scanner.client;

import wayland.scanner;
import wayland.scanner.common;

import arsd.dom;

import std.algorithm;
import std.exception;
import std.format;
import std.range;


alias Interface = wayland.scanner.common.Interface;

class ClientFactory : Factory
{
    override Protocol makeProtocol(Element el)
    {
        return new ClientProtocol(el);
    }
    override Interface makeInterface(Element el, Protocol protocol)
    {
        return new ClientInterface(el, protocol);
    }
    override Message makeMessage(Element el, Interface iface)
    {
        return new ClientMessage(el, iface);
    }
    override Arg makeArg(Element el)
    {
        return new ClientArg(el);
    }
}

class ClientArg : Arg
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
            case ArgType.Object:
                if (iface.length)
                    return ifaceDName(iface);
                else
                    return "WlProxy";
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
                return "wl_proxy*";
        }
    }

    override @property string cCastExpr() const
    {
        final switch(type) {
            case ArgType.Int:
            case ArgType.UInt:
            case ArgType.Fixed:
            case ArgType.String:
            case ArgType.Array:
            case ArgType.Fd:
                return Arg.cCastExpr;
            case ArgType.NewId:
            case ArgType.Object:
                return format("%s.proxy", paramName);
        }
    }

    @property string reqCType() const
    {
        final switch(type) {
            case ArgType.Int:
            case ArgType.UInt:
            case ArgType.Fixed:
            case ArgType.String:
            case ArgType.Array:
            case ArgType.Fd:
                return Arg.cType;
            case ArgType.NewId:
            case ArgType.Object:
                return "wl_proxy*";
        }
    }

    @property string evCType() const
    {
        final switch(type) {
            case ArgType.Int:
            case ArgType.UInt:
            case ArgType.Fixed:
            case ArgType.String:
            case ArgType.Array:
            case ArgType.Fd:
                return Arg.cType;
            case ArgType.NewId:
            case ArgType.Object:
                if (iface.empty) return "void*";
                else return "wl_proxy*";
        }
    }

    override string dCastExpr(string parentIface) const
    {
        final switch(type) {
            case ArgType.Int:
            case ArgType.UInt:
            case ArgType.Fixed:
            case ArgType.String:
            case ArgType.Array:
            case ArgType.Fd:
                return Arg.dCastExpr(parentIface);
            case ArgType.NewId:
                if (iface)
                    return format("new %s(%s)", ifaceDName(iface), paramName);
                else
                    return format("WlProxy.get(%s)", paramName);
            case ArgType.Object:
                auto expr = format("WlProxy.get(%s)", paramName);
                if (iface)
                    return format("cast(%s)%s", ifaceDName(iface), expr);
                else
                    return expr;
        }
    }
}


class ClientMessage : Message
{
    this (Element el, Interface iface)
    {
        super(el, iface);
    }

    @property auto clArgs()
    {
        return args.map!(a => cast(ClientArg)a);
    }

    @property string reqRetStr()
    {
        final switch (reqType)
        {
        case ReqType.newObj:
            return ifaceDName(reqRet.iface);
        case ReqType.dynObj:
            return "WlProxy";
        case ReqType.void_:
            return "void";
        }
    }

    void writeRequestCode(SourceFile sf)
    {
        final switch(reqType)
        {
        case ReqType.void_:
            writeVoidReqDefinitionCode(sf);
            break;
        case ReqType.newObj:
            writeNewObjReqDefinitionCode(sf);
            break;
        case ReqType.dynObj:
            writeDynObjReqDefinitionCode(sf);
            break;
        }
    }

    void writeEventDgAlias(SourceFile sf)
    {
        sf.writeln("/// Event delegate signature of %s.%s.", ifaceDName(ifaceName), dHandlerName);
        string[] rtArgs = [
            format("%s %s", ifaceDName(ifaceName), camelName(ifaceName))
        ];
        foreach(a; args)
        {
            rtArgs ~= format("%s %s", a.dType, a.paramName);
        }
        writeDelegateAlias(sf, dEvDgType, "void", rtArgs);
    }

    void writeEventDgAccessor(SourceFile sf)
    {
        description.writeCode(sf);
        sf.writeln("@property void %s(%s dg)", dHandlerName, dEvDgType);
        sf.bracedBlock!({
            sf.writeln("_%s = dg;", dHandlerName);
        });
    }

    void writeVoidReqDefinitionCode(SourceFile sf)
    {
        string[] rtArgs;
        string[] exprs = [
            "proxy", opCodeName
        ];
        foreach(arg; args)
        {
            rtArgs ~= (arg.dType ~ " " ~ arg.paramName);
            exprs ~= arg.cCastExpr;
        }
        string[] postStmt = isDtor ? ["super.destroyNotify();"] : [];

        description.writeCode(sf);
        sf.writeFnSig("void", dMethodName, rtArgs);
        sf.writeFnBody([], "wl_proxy_marshal", exprs, postStmt);
    }

    void writeNewObjReqDefinitionCode(SourceFile sf)
    {
        string[] rtArgs;
        string[] exprs = [
            "proxy", opCodeName, format("%s.iface.native", ifaceDName(reqRet.iface))
        ];
        foreach(arg; args)
        {
            if (arg is reqRet)
            {
                exprs ~= "null";
            }
            else
            {
                rtArgs ~= format("%s %s", arg.dType, arg.paramName);
                exprs ~= arg.cCastExpr;
            }
        }
        description.writeCode(sf);
        sf.writeFnSig(reqRetStr, dMethodName, rtArgs);
        sf.writeFnBody([],
            "auto _pp = wl_proxy_marshal_constructor", exprs,
            [   "if (!_pp) return null;",
                "auto _p = wl_proxy_get_user_data(_pp);",
                format("if (_p) return cast(%s)_p;", reqRetStr),
                format("return new %s(_pp);", reqRetStr)    ]
        );
    }

    void writeDynObjReqDefinitionCode(SourceFile sf)
    {
        string[] rtArgs;
        string[] exprs = [
            "proxy", opCodeName, "iface.native", "ver"
        ];
        foreach(arg; args)
        {
            if (arg is reqRet)
            {
                rtArgs ~= [ "immutable(WlProxyInterface) iface", "uint ver" ];
                exprs ~= [ "iface.native.name", "ver" ];
            }
            else
            {
                rtArgs ~= format("%s %s", arg.dType, arg.paramName);
                exprs ~= arg.cCastExpr;
            }
        }
        description.writeCode(sf);
        sf.writeFnSig(reqRetStr, dMethodName, rtArgs);
        sf.writeFnBody([],
            "auto _pp = wl_proxy_marshal_constructor_versioned", exprs,
            [   "if (!_pp) return null;",
                "auto _p = wl_proxy_get_user_data(_pp);",
                "if (_p) return cast(WlProxy)_p;",
                "return iface.makeProxy(_pp);"  ]
        );
    }

    void writePrivListenerSig(SourceFile sf)
    {
        enum fstLine = "void function(";
        immutable lstEol = format(") %s;", cEvName);

        immutable indent = ' '.repeat.take(fstLine.length).array();
        sf.writeln("%svoid* data,", fstLine);
        auto eol = args.empty ? lstEol : ",";
        sf.writeln("%swl_proxy* proxy%s", indent, eol);
        foreach(i, arg; enumerate(clArgs))
        {
            eol = i == args.length-1 ? lstEol : ",";
            sf.writeln("%s%s %s%s", indent, arg.evCType, arg.paramName, eol);
        }
    }

    void writePrivListenerStub(SourceFile sf)
    {
        immutable fstLine = format("void wl_d_on_%s_%s(", ifaceName, name);
        immutable indent = ' '.repeat.take(fstLine.length).array();
        sf.writeln("%svoid* data,", fstLine);
        auto eol = args.empty ? ")" : ",";
        sf.writeln("%swl_proxy* proxy%s", indent, eol);
        foreach(i, arg; enumerate(clArgs))
        {
            eol = i == args.length-1 ? ")" : ",";
            sf.writeln("%s%s %s%s", indent, arg.evCType, arg.paramName, eol);
        }
        sf.bracedBlock!({
            sf.writeln("nothrowFnWrapper!({");
            sf.indentedBlock!({
                sf.writeln("auto _p = data;");
                sf.writeln("assert(_p, \"listener stub without the right userdata\");");
                sf.writeln("auto _i = cast(%s)_p;", ifaceDName(ifaceName));
                sf.writeln("assert(_i, \"listener stub proxy is not %s\");", ifaceDName(ifaceName));
                sf.writeln("if (_i._%s)", dHandlerName);
                sf.bracedBlock!({
                    string sep = args.length ? ", " : "";
                    sf.write("_i._%s(_i%s", dHandlerName, sep);
                    foreach (i, arg; args)
                    {
                        sep = (i == args.length-1) ? "" : ", ";
                        sf.write("%s%s", arg.dCastExpr(ifaceName), sep);
                    }
                    sf.writeln(");");
                });

            });
            sf.writeln("});");
        });
    }
}


class ClientInterface : Interface
{
    this (Element el, Protocol protocol)
    {
        super(el, protocol);
    }

    @property auto clRequests()
    {
        return requests.map!(r => cast(ClientMessage)r);
    }

    @property auto clEvents()
    {
        return events.map!(r => cast(ClientMessage)r);
    }

    @property string globalNativeListenerName()
    {
        return format("wl_d_%s_listener", name);
    }

    override void writeCode(SourceFile sf)
    {
        description.writeCode(sf);

        sf.writeln("final class %s : %s", dName,
            name == "wl_display" ?
                "WlDisplayBase" :
                "WlProxy");
        sf.bracedBlock!(
        {
            writeVersion(sf);
            sf.writeln();
            sf.writeln("/// Build a %s from a native object.", dName);
            sf.writeln(name == "wl_display" ?
                "package(wayland) this(wl_display* native)" :
                "private this(wl_proxy* native)"
            );
            sf.bracedBlock!({
                sf.writeln("super(native);");
                if (writeEvents)
                {
                    sf.writeln(
                        "wl_proxy_add_listener(proxy, cast(void_func_t*)&%s, cast(void*) this);",
                        globalNativeListenerName
                    );
                }
            });
            sf.writeln();
            sf.writeln("/// Interface object that creates %s objects.", dName);
            sf.writeln("static @property immutable(WlProxyInterface) iface()");
            sf.bracedBlock!({
                sf.writeln("return %sIface;", camelName(name));
            });
            writeConstants(sf);
            if (writeEvents)
            {
                sf.writeln();
                foreach(msg; clEvents)
                {
                    msg.writeEventDgAlias(sf);
                }
            }
            foreach (en; enums)
            {
                sf.writeln();
                en.writeCode(sf);
            }
            writeDtorCode(sf);
            foreach (msg; clRequests)
            {
                sf.writeln();
                msg.writeRequestCode(sf);
            }
            if (writeEvents)
            {
                foreach(msg; clEvents)
                {
                    sf.writeln();
                    msg.writeEventDgAccessor(sf);
                }

                sf.writeln();
                foreach(msg; events)
                {
                    sf.writeln("private %s _%s;", msg.dEvDgType, msg.dHandlerName);
                }
            }
        });
    }

    void writeConstants(SourceFile sf)
    {
        if (requests.length)
        {
            sf.writeln();
            foreach(i, msg; requests)
            {
                sf.writeln("/// Op-code of %s.%s.", dName, msg.dMethodName);
                sf.writeln("enum %s = %d;", msg.opCodeName, i);
            }
            sf.writeln();
            foreach(msg; requests)
            {
                sf.writeln(
                    "/// Version of %s protocol introducing %s.%s.",
                    protocol.name, dName, msg.dMethodName
                );
                sf.writeln("enum %sSinceVersion = %d;", camelName(msg.name), msg.since);
            }
        }
        if (events.length)
        {
            sf.writeln();
            foreach(msg; events)
            {
                sf.writeln(
                    "/// %s protocol version introducing %s.%s.",
                    protocol.name, dName, msg.dHandlerName
                );
                sf.writeln("enum %sSinceVersion = %d;", msg.dHandlerName, msg.since);
            }
        }
    }

    void writeDtorCode(SourceFile sf)
    {
        immutable hasDtor = requests.canFind!(rq => rq.isDtor);
        immutable hasDestroy = requests.canFind!(rq => rq.name == "destroy");

        enforce(!hasDestroy || hasDtor);

        if (!hasDestroy && name != "wl_display")
        {
            sf.writeln();
            sf.writeln("/// Destroy this %s object.", dName);
            sf.writeln("void destroy()");
            sf.bracedBlock!({
                sf.writeln("wl_proxy_destroy(proxy);");
                sf.writeln("super.destroyNotify();");
            });
        }
    }

    void writePrivListener(SourceFile sf)
    {
        if (!writeEvents) return;

        sf.writeln("struct %s_listener", name);
        sf.bracedBlock!({
            foreach(ev; clEvents)
            {
                ev.writePrivListenerSig(sf);
            }
        });

        sf.writeln();
        immutable fstLine = format("__gshared %s = %s_listener (", globalNativeListenerName, name);
        immutable indent = ' '.repeat(fstLine.length).array();
        foreach (i, ev; events)
        {
            sf.writeln("%s&wl_d_on_%s_%s%s", (i == 0 ? fstLine : indent),
                                        name, ev.name,
                                        (i == events.length-1) ? ");" : ",");
        }
    }

    void writePrivListenerStubs(SourceFile sf)
    {
        if (!writeEvents) return;

        foreach(ev; clEvents)
        {
            sf.writeln();
            ev.writePrivListenerStub(sf);
        }
    }
}



class ClientProtocol : Protocol
{
    this(Element el)
    {
        super(el);
    }

    @property auto clIfaces()
    {
        return ifaces.map!(iface => cast(ClientInterface)iface);
    }

    override void writeCode(SourceFile sf, in Options opt)
    {
        writeHeader(sf, opt);
        if (name == "wayland") sf.writeln("import wayland.client.core;");
        else sf.writeln("import wayland.client;");
        sf.writeln("import wayland.native.client;");
        sf.writeln("import wayland.native.util;");
        sf.writeln("import wayland.util;");
        sf.writeln();
        sf.writeln("import std.exception : enforce;");
        sf.writeln("import std.string : fromStringz, toStringz;");
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
            foreach(i, iface; enumerate(clIfaces))
            {
                if (i != 0) sf.writeln();
                iface.writePrivListener(sf);
                iface.writePrivListenerStubs(sf);
            }
        });
    }

    override void writePrivIfaces(SourceFile sf)
    {
        foreach(iface; ifaces)
        {
            sf.writeln("immutable WlProxyInterface %sIface;", camelName(iface.name));
        }
        foreach (iface; ifaces)
        {
            sf.writeln();
            sf.writeln("immutable final class %sIface : WlProxyInterface",
                    titleCamelName(iface.name));
            sf.bracedBlock!({
                sf.writeln("this(immutable wl_interface* native)");
                sf.bracedBlock!({
                    sf.writeln("super(native);");
                });
                sf.writeln("override WlProxy makeProxy(wl_proxy* proxy) immutable");
                sf.bracedBlock!({
                    if (iface.name == "wl_display")
                    {
                        sf.writeln("return new WlDisplay(cast(wl_display*)proxy);");
                    }
                    else
                        sf.writeln("return new %s(proxy);", iface.dName);
                });
            });
        }
        writeNativeIfaces(sf);
    }

    override void writeNativeIfacesAssignment(SourceFile sf)
    {
        foreach (iface; ifaces)
        {
            sf.writeln("%sIface = new immutable %sIface( &wl_ifaces[%s] );",
                    camelName(iface.name),
                    titleCamelName(iface.name),
                    indexSymbol(iface.name));
        }
    }

}
