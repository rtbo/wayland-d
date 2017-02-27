// Copyright © 2017 Rémi Thebault
/++
 +  Wayland scanner for D.
 +  Scan wayland XML protocol and generates client or server code for that protocol.
 +/
module wayland.scanner;

import arsd.dom;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.getopt;
import std.range;
import std.stdio;
import std.typecons;
import std.uni;

enum scannerVersion = "v0.0.1";
enum usageIntro = "wayland-d:scanner-"~scannerVersion~"\n"~
                  "  A Wayland protocol scanner and D code generator.\n\n";
enum bindingsCopyright = "Copyright © 2017 Rémi Thebault";


int main(string[] args)
{
    auto opt = new Options;
    opt.cmdLine = args.join(" ");
    auto optHandler = getopt (
        args,
        "code|c",   "generated code: client|server [client]", &opt.code,
        "input|i",  "input file [stdin]", &opt.inFile,
        "output|o", "output file [stdout]", &opt.outFile,
        "module|m", "D module name (required)", &opt.moduleName,
    );

    if (optHandler.helpWanted)
    {
        defaultGetoptFormatter (
            stdout.lockingTextWriter,
            usageIntro ~ "Options:",
            optHandler.options
        );
        return 0;
    }

    if (opt.moduleName.empty)
    {
        defaultGetoptFormatter (
            stderr.lockingTextWriter,
            usageIntro ~
            "Error: D module name must be supplied with '--module' or '-m'\n\n" ~
            "Options:",
            optHandler.options
        );
        return 1;
    }

    try
    {
        File input = (opt.inFile.empty) ? stdin : File(opt.inFile, "r");
        File output = (opt.outFile.empty) ? stdout : File(opt.outFile, "w");

        string xmlStr;
        foreach (string l; lines(input))
        {
            xmlStr ~= l;
        }
        auto xmlDoc = new Document;
        xmlDoc.parse(xmlStr, true, true);
        auto p = new Protocol(xmlDoc.root);
        if (opt.code == GenCode.client)
            p.writeClientCode(new SourceFile(output), opt);
        else
            p.writeServerCode(new SourceFile(output), opt);
    }
    catch(Exception ex)
    {
        stderr.writeln("Error: "~ex.msg);
        return 1;
    }

    return 0;
}

private:

enum GenCode
{
    client,
    server,
}

class Options
{
    string cmdLine;

    string inFile;
    string outFile;
    string moduleName;

    GenCode code;
}


enum ArgType
{
    Int, UInt, Fixed, String, Object, NewId, Array, Fd
}

@property bool isNullable(in ArgType at) pure
{
    switch (at)
    {
    case ArgType.String:
    case ArgType.Object:
    case ArgType.NewId:
    case ArgType.Array:
        return true;
    default:
        return false;
    }
}


class Description
{
    string summary;
    string text;

    this (Element parentEl)
    {
        foreach (el; parentEl.getElementsByTagName("description"))
        {
            summary = el.getAttribute("summary");
            text = el.getElText();
            break;
        }
    }

    @property bool empty() const
    {
        return summary.empty && text.empty;
    }

    void writeCode(SourceFile sf)
    {
        if (empty) return;
        if (text.empty)
        {
            enforce(!summary.canFind('\n'), "Summary should be a 1 liner.");
            sf.writeln("/// %s", summary);
        }
        else if (summary.empty)
        {
            sf.writeDoc("%s", text);
        }
        else
        {
            sf.writeDoc("%s\n\n%s", summary, text);
        }
    }
}


class EnumEntry
{
    string ifaceName;
    string enumName;
    string name;
    string value;
    string summary;

    this (Element el, string ifaceName, string enumName)
    {
        assert(el.tagName == "entry");
        this.ifaceName = ifaceName;
        this.enumName = enumName;
        name = el.getAttribute("name");
        value = el.getAttribute("value");
        summary = el.getAttribute("summary");

        enforce(!value.empty, "enum entries without value aren't supported");
    }

    void writeCode(SourceFile sf)
    {
        if (summary.length)
        {
            sf.writeln("/// %s", summary);
        }
        sf.writeln(
            "%s = %s,", validDName(camelName(name)), value
        );
    }
}


class Enum
{
    string name;
    string ifaceName;
    Description description;
    EnumEntry[] entries;

    this (Element el, string ifaceName)
    {
        assert(el.tagName == "enum");
        name = el.getAttribute("name");
        this.ifaceName = ifaceName;
        description = new Description(el);
        foreach (entryEl; el.getElementsByTagName("entry"))
        {
            entries ~= new EnumEntry(entryEl, ifaceName, name);
        }
    }

    @property dName() const
    {
        return titleCamelName(name);
    }

    bool entriesHaveDoc() const
    {
        return entries.any!(e => !e.summary.empty);
    }

    void writeCode(SourceFile sf)
    {
        description.writeCode(sf);
        sf.writeln("enum %s : uint", dName);
        sf.bracedBlock!({
            foreach(entry; entries)
            {
                entry.writeCode(sf);
            }
        });
    }
}



class Arg
{
    string name;
    string summary;
    string iface;
    ArgType type;
    string enumName;
    bool nullable;

    this (Element el)
    {
        assert(el.tagName == "arg");
        name = el.getAttribute("name");
        summary = el.getAttribute("summary");
        iface = el.getAttribute("interface");
        enumName = el.getAttribute("enum");
        switch (el.getAttribute("type"))
        {
            case "int":
                type = ArgType.Int;
                break;
            case "uint":
                type = ArgType.UInt;
                break;
            case "fixed":
                type = ArgType.Fixed;
                break;
            case "string":
                type = ArgType.String;
                break;
            case "object":
                type = ArgType.Object;
                break;
            case "new_id":
                type = ArgType.NewId;
                break;
            case "array":
                type = ArgType.Array;
                break;
            case "fd":
                type = ArgType.Fd;
                break;
            default:
                throw new Exception("unknown type: "~el.getAttribute("type"));
        }
        immutable allowNull = el.getAttribute("allow-null");
        enforce (!allowNull.length || (allowNull == "true" || allowNull == "false"));
        nullable = allowNull == "true";
        enforce(!nullable || isNullable(type));
    }

    @property string reqCType() const
    {
        final switch(type) {
            case ArgType.Int:
                return "int";
            case ArgType.UInt:
                return "uint";
            case ArgType.Fixed:
                return "wl_fixed_t";
            case ArgType.String:
                return "const(char)*";
            case ArgType.Object:
                return "wl_proxy*";
            case ArgType.NewId:
                return "uint";
            case ArgType.Array:
                return "wl_array*";
            case ArgType.Fd:
                return "int";
        }
    }

    @property string evCType() const
    {
        final switch(type) {
            case ArgType.Int:
                return "int";
            case ArgType.UInt:
                return "uint";
            case ArgType.Fixed:
                return "wl_fixed_t";
            case ArgType.String:
                return "const(char)*";
            case ArgType.Object:
                if (iface.empty) return "void*";
                else return "wl_proxy*";
            case ArgType.NewId:
                return "uint";
            case ArgType.Array:
                return "wl_array*";
            case ArgType.Fd:
                return "int";
        }
    }

    @property string dType() const
    {
        final switch(type) {
            case ArgType.Int:
                return "int";
            case ArgType.UInt:
                if (enumName.empty) return "uint";
                else return qualfiedTypeName(enumName);
            case ArgType.Fixed:
                return "WlFixed";
            case ArgType.String:
                return "string";
            case ArgType.Object:
                if (iface.length)
                    return ifaceDName(iface);
                else
                    return "WlProxy";
            case ArgType.NewId:
                return "uint";
            case ArgType.Array:
                return "wl_array*"; // ?? let's check this later
            case ArgType.Fd:
                return "int";
        }
    }


    @property string paramName() const
    {
        return validDName(camelName(name));
    }

    @property string cCastExpr() const
    {
        final switch(type) {
            case ArgType.Int:
                return paramName;
            case ArgType.UInt:
                return paramName;
            case ArgType.Fixed:
                return format("%s.raw", paramName);
            case ArgType.String:
                return format("toStringz(%s)", paramName);
            case ArgType.Object:
                return format("%s.proxy", paramName);
            case ArgType.NewId:
                return paramName;
            case ArgType.Array:
                return paramName;
            case ArgType.Fd:
                return paramName;
        }
    }

    string dCastExpr(string parentIface) const
    {
        final switch(type) {
            case ArgType.Int:
                return paramName;
            case ArgType.UInt:
                if (enumName.empty) return paramName;
                else
                {
                    immutable en = (parentIface.empty || enumName.canFind('.')) ?
                            enumName : format("%s.%s", parentIface, enumName);
                    return format("cast(%s)%s", qualfiedTypeName(en), paramName);
                }
            case ArgType.Fixed:
                return format("WlFixed(%s)", paramName);
            case ArgType.String:
                return format("fromStringz(%s).idup", paramName);
            case ArgType.Object:
                auto expr = format("WlProxy.get(%s)", paramName);
                if (iface)
                    return format("cast(%s)%s", ifaceDName(iface), expr);
                else
                    return expr;
            case ArgType.NewId:
                return paramName;
            case ArgType.Array:
                return paramName;
            case ArgType.Fd:
                return paramName;
        }
    }
}


class Message
{
    enum Type
    {
        event,
        request,
    }

    enum ReqType
    {
        void_,
        newObj,
        dynObj,
    }

    string name;
    string ifaceName;
    int since = 1;
    bool isDtor;
    Description description;
    Arg[] args;

    string[] argIfaceTypes;
    size_t ifaceTypeIndex;
    Type type;
    ReqType reqType;

    Arg reqRet;
    string reqRetStr;

    this (Element el, string ifaceName)
    {
        assert(el.tagName == "request" || el.tagName == "event");
        name = el.getAttribute("name");
        this.ifaceName = ifaceName;
        if (el.hasAttribute("since"))
        {
            since = el.getAttribute("since").to!int;
        }
        isDtor = (el.getAttribute("type") == "destructor");
        description = new Description(el);
        foreach (argEl; el.getElementsByTagName("arg"))
        {
            args ~= new Arg(argEl);
        }

        argIfaceTypes = args
            .filter!(a => a.type == ArgType.NewId || a.type == ArgType.Object)
            .map!(a => a.iface)
            .filter!(iface => iface.length != 0)
            .array();

        type = el.tagName == "event" ? Type.event : Type.request;

        if (type == Type.request)
        {
            auto crr = clientReqReturn;
            reqRet = crr[0];
            reqRetStr = crr[1];
            reqType = crr[2];
        }
    }

    @property Tuple!(Arg, string, ReqType) clientReqReturn()
    {
        Arg ret;
        string retStr;
        ReqType rt;
        foreach (arg; args)
        {
            if (arg.type == ArgType.NewId)
            {
                enforce(!ret, "more than 1 new-id for a request");
                ret = arg;
                if (arg.iface.length)
                {
                    retStr = ifaceDName(arg.iface);
                    rt = ReqType.newObj;
                }
                else
                {
                    retStr = "WlProxy";
                    rt = ReqType.dynObj;
                }
            }
        }
        if (!ret)
        {
            retStr = "void";
            rt = ReqType.void_;
        }
        return tuple(ret, retStr, rt);
    }

    @property bool ifaceTypesAllNull() const
    {
        return argIfaceTypes.empty;
    }

    @property size_t nullIfaceTypeLength() const
    {
        return argIfaceTypes.empty ? args.length : 0;
    }

    @property string dReqName()
    {
        return validDName(camelName(name));
    }

    @property string reqOpCode()
    {
        return format("%sOpCode", camelName(name));
    }

    @property string dEvName()
    {
        return "on" ~ titleCamelName(name);
    }

    @property string dEvDgType()
    {
        return "On" ~ titleCamelName(name) ~ "EventDg";
    }

    @property string evOpCode()
    {
        return format("on%sOpCode", titleCamelName(name));
    }

    @property string cEvName()
    {
        return validDName(name);
    }

    @property string signature() const
    {
        string sig;
        if (since > 1)
        {
            sig ~= since.to!string;
        }
        foreach(arg; args)
        {
            if (arg.nullable) sig ~= '?';
            final switch(arg.type)
            {
            case ArgType.Int:
                sig ~= 'i';
                break;
            case ArgType.NewId:
                if (arg.iface.empty)
                    sig ~= "su";
                sig ~= "n";
                break;
            case ArgType.UInt:
                sig ~= "u";
                break;
            case ArgType.Fixed:
                sig ~= "f";
                break;
            case ArgType.String:
                sig ~= "s";
                break;
            case ArgType.Object:
                sig ~= "o";
                break;
            case ArgType.Array:
                sig ~= "a";
                break;
            case ArgType.Fd:
                sig ~= "h";
                break;
            }
        }
        return sig;
    }

    void writeSig(SourceFile sf, string ret, string name, string[] rtArgs,
                    string[] ctArgs=[], string constraint="")
    {
        immutable ctSig = ctArgs.length ? format("!(%(%s, %))", ctArgs) : "";
        immutable fstLine = format("%s %s%s(", ret, name, ctSig);
        immutable indent = ' '.repeat(fstLine.length).array();
        sf.write(fstLine);
        foreach (i, rta; rtArgs)
        {
            if (i != 0)
            {
                sf.writeln(",");
                sf.write(indent);
            }
            sf.write(rta);
        }
        sf.writeln(")");
        if (constraint.length)
        {
            sf.writeln("if (%s)", constraint);
        }
    }

    void writeBody(SourceFile sf, string[] preStmts, string mainStmt,
                    string[] expr, string[] postStmt)
    {
        sf.bracedBlock!({
            foreach (ps; preStmts)
            {
                sf.writeln(ps);
            }
            sf.writeln("%s(", mainStmt);
            foreach (i, e; expr)
            {
                if (i == 0) sf.write("    ");
                else sf.write(", ");
                sf.write(e);
            }
            sf.writeln();
            sf.writeln(");");
            foreach (ps; postStmt)
            {
                sf.writeln(ps);
            }
        });
    }

    void writeVoidReqDefinitionCode(SourceFile sf)
    {
        string[] prepArgs;
        string[] prepExpr = [
            "proxy", reqOpCode
        ];
        foreach(arg; args)
        {
            prepArgs ~= (arg.dType ~ " " ~ arg.paramName);
            prepExpr ~= arg.cCastExpr;
        }
        string[] postStmt = isDtor ? ["super.destroyNotify();"] : [];

        description.writeCode(sf);
        writeSig(sf, "void", dReqName, prepArgs);
        writeBody(sf, [], "wl_proxy_marshal", prepExpr, postStmt);
    }

    void writeNewObjReqDefinitionCode(SourceFile sf)
    {
        string[] prepArgs;
        string[] prepExpr = [
            "proxy", reqOpCode, format("%s.iface.native", ifaceDName(reqRet.iface))
        ];
        foreach(arg; args)
        {
            if (arg is reqRet)
            {
                prepExpr ~= "null";
            }
            else
            {
                prepArgs ~= format("%s %s", arg.dType, arg.paramName);
                prepExpr ~= arg.cCastExpr;
            }
        }
        description.writeCode(sf);
        writeSig(sf, reqRetStr, dReqName, prepArgs);
        writeBody(sf, [],
            "auto _pp = wl_proxy_marshal_constructor", prepExpr,
            [   "if (!_pp) return null;",
                "auto _p = WlProxy.get(_pp);",
                format("if (_p) return cast(%s)_p;", reqRetStr),
                format("return new %s(_pp);", reqRetStr)    ]
        );
    }

    void writeDynObjReqDefinitionCode(SourceFile sf)
    {
        string[] prepArgs;
        string[] prepExpr = [
            "proxy", reqOpCode, "iface.native", "ver"
        ];
        foreach(arg; args)
        {
            if (arg is reqRet)
            {
                prepArgs ~= [ "immutable(WlProxyInterface) iface", "uint ver" ];
                prepExpr ~= [ "iface.native.name", "ver" ];
            }
            else
            {
                prepArgs ~= format("%s %s", arg.dType, arg.paramName);
                prepExpr ~= arg.cCastExpr;
            }
        }
        description.writeCode(sf);
        writeSig(sf, reqRetStr, dReqName, prepArgs);
        writeBody(sf, [],
            "auto _pp = wl_proxy_marshal_constructor_versioned", prepExpr,
            [   "if (!_pp) return null;",
                "auto _p = WlProxy.get(_pp);",
                "if (_p) return _p;",
                "return iface.makeProxy(_pp);"  ]
        );
    }

    void writeClientRequestCode(SourceFile sf)
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

    void writeClientEventDgAlias(SourceFile sf)
    {
        sf.writeln("/// Event delegate signature of %s.%s.", ifaceDName(ifaceName), dEvName);
        immutable fstLine = format("alias %s = void delegate (", dEvDgType);
        immutable indent = ' '.repeat(fstLine.length).array();
        string eol = args.length ? "," : ");";
        sf.writeln("%s%s %s%s", fstLine, ifaceDName(ifaceName), camelName(ifaceName), eol);
        foreach(i, arg; args)
        {
            eol = i == args.length-1 ? ");" : ",";
            sf.writeln("%s%s %s%s", indent, arg.dType, arg.paramName, eol);
        }
    }

    void writeClientEventDgAccessor(SourceFile sf)
    {
        description.writeCode(sf);
        sf.writeln("@property void %s(%s dg)", dEvName, dEvDgType);
        sf.bracedBlock!({
            sf.writeln("_%s = dg;", dEvName);
        });
    }

    void writePrivIfaceMsg(SourceFile sf)
    {
        sf.writeln(
            "wl_message(\"%s\", \"%s\", &msgTypes[%d]),",
            name, signature, ifaceTypeIndex
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
        foreach(i, arg; args)
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
        foreach(i, arg; args)
        {
            eol = i == args.length-1 ? ")" : ",";
            sf.writeln("%s%s %s%s", indent, arg.evCType, arg.paramName, eol);
        }
        sf.bracedBlock!({
            sf.writeln("nothrowFnWrapper!({");
            sf.indentedBlock!({
                sf.writeln("auto _p = WlProxy.get(proxy);");
                sf.writeln("assert(_p, \"listener stub without proxy\");");
                sf.writeln("auto _i = cast(%s)_p;", ifaceDName(ifaceName));
                sf.writeln("assert(_i, \"listener stub proxy is not %s\");", ifaceDName(ifaceName));
                sf.writeln("if (_i._%s)", dEvName);
                sf.bracedBlock!({
                    string sep = args.length ? ", " : "";
                    sf.write("_i._%s(_i%s", dEvName, sep);
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


class Interface
{
    string protocol;
    string name;
    string ver;
    Description description;
    Message[] requests;
    Message[] events;
    Enum[] enums;

    // indicate that is created by server rather than by client request.
    // protocal eventually set to false after all interfaces are parsed
    bool isGlobal = true;

    this (Element el, string protocol)
    {
        assert(el.tagName == "interface");
        this.protocol = protocol;
        name = el.getAttribute("name");
        ver = el.getAttribute("version");
        description = new Description(el);
        foreach (rqEl; el.getElementsByTagName("request"))
        {
            requests ~= new Message(rqEl, name);
        }
        foreach (evEl; el.getElementsByTagName("event"))
        {
            events ~= new Message(evEl, name);
        }
        foreach (enEl; el.getElementsByTagName("enum"))
        {
            enums ~= new Enum(enEl, name);
        }
    }

    @property string dName() const
    {
        return ifaceDName(name);
    }

    @property bool writeEvents()
    {
        return events.length && name != "wl_display";
    }

    @property size_t nullIfaceTypeLength()
    {
        size_t max =0;
        foreach (tl; chain(requests, events)
                .map!(msg => msg.nullIfaceTypeLength))
        {
            if (tl > max) max = tl;
        }
        return max;
    }

    void writeConstants(SourceFile sf)
    {
        if (requests.length)
        {
            sf.writeln();
            foreach(i, msg; requests)
            {
                sf.writeln("/// Op-code of %s.%s.", dName, msg.dReqName);
                sf.writeln("enum %s = %d;", msg.reqOpCode, i);
            }
            sf.writeln();
            foreach(msg; requests)
            {
                sf.writeln(
                    "/// Version of %s protocol introducing %s.%s.",
                    protocol, dName, msg.dReqName
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
                    protocol, dName, msg.dEvName
                );
                sf.writeln("enum %sSinceVersion = %d;", msg.dEvName, msg.since);
            }
        }
    }

    void writeClientDtorCode(SourceFile sf)
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

    void writeClientCode(SourceFile sf)
    {
        description.writeCode(sf);

        sf.writeln("final class %s : %s", dName,
            name == "wl_display" ?
                "WlDisplayBase" :
                "WlProxy");
        sf.bracedBlock!(
        {
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
                        "wl_proxy_add_listener(proxy, cast(void_func_t*)&the%sListener, null);",
                        titleCamelName(name)
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
                foreach(msg; events)
                {
                    msg.writeClientEventDgAlias(sf);
                }
            }
            foreach (en; enums)
            {
                sf.writeln();
                en.writeCode(sf);
            }
            writeClientDtorCode(sf);
            foreach (msg; requests)
            {
                sf.writeln();
                msg.writeClientRequestCode(sf);
            }
            if (writeEvents)
            {
                foreach(msg; events)
                {
                    sf.writeln();
                    msg.writeClientEventDgAccessor(sf);
                }

                sf.writeln();
                foreach(msg; events)
                {
                    sf.writeln("private %s _%s;", msg.dEvDgType, msg.dEvName);
                }
            }
        });
    }

    void writeServerGlobalCode(SourceFile sf)
    {
        sf.writeln("class Global : WlGlobal");
        sf.bracedBlock!({
            sf.writeln("this(wl_global* native)");
            sf.bracedBlock!({
                sf.writeln("super(native);");
            });
        });
    }

    void writeServerResourceCode(SourceFile sf)
    {
        sf.writeln("class Resource : WlResource");
        sf.bracedBlock!({
            sf.writeln("this(wl_resource* native)");
            sf.bracedBlock!({
                sf.writeln("super(native);");
            });
        });
    }

    void writeServerCode(SourceFile sf)
    {
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
            else
            {
                if (isGlobal)
                {
                    writeServerGlobalCode(sf);
                    sf.writeln();
                }
                writeServerResourceCode(sf);
            }
        });
    }

    void writePrivClientListener(SourceFile sf)
    {
        if (!writeEvents) return;

        sf.writeln("struct %s_listener", name);
        sf.bracedBlock!({
            foreach(ev; events)
            {
                ev.writePrivListenerSig(sf);
            }
        });

        sf.writeln();
        immutable fstLine = format("__gshared the%sListener = %s_listener (", titleCamelName(name), name);
        immutable indent = ' '.repeat(fstLine.length).array();
        foreach (i, ev; events)
        {
            sf.writeln("%s&wl_d_on_%s_%s%s", (i == 0 ? fstLine : indent),
                                        name, ev.name,
                                        (i == events.length-1) ? ");" : ",");
        }
    }

    void writePrivClientListenerStubs(SourceFile sf)
    {
        if (!writeEvents) return;

        foreach(ev; events)
        {
            sf.writeln();
            ev.writePrivListenerStub(sf);
        }
    }

    void writePrivIfaceMsgs(SourceFile sf, Message[] msgs, in string suffix)
    {
        if (msgs.empty) return;

        sf.writeln("auto %s_%s = [", name, suffix);
        sf.indentedBlock!({
            foreach(msg; msgs)
            {
                msg.writePrivIfaceMsg(sf);
            }
        });
        sf.writeln("];");
    }

    void writePrivIfacePopulate(SourceFile sf)
    {
        writePrivIfaceMsgs(sf, requests, "requests");
        writePrivIfaceMsgs(sf, events, "events");
        immutable memb = format("ifaces[%s]", indexSymbol(name));
        sf.writeln(`%s.name = "%s";`, memb, name);
        sf.writeln("%s.version_ = %s;", memb, ver);

        if (requests.length)
        {
            sf.writeln("%s.method_count = %d;", memb, requests.length);
            sf.writeln("%s.methods = %s_requests.ptr;", memb, name);
        }
        if (events.length)
        {
            sf.writeln("%s.event_count = %d;", memb, events.length);
            sf.writeln("%s.events = %s_events.ptr;", memb, name);
        }
    }
}


class Protocol
{
    string name;
    string copyright;
    Interface[] ifaces;

    this(Element el)
    {
        enforce(el.tagName == "protocol");
        name = el.getAttribute("name");
        foreach (cr; el.getElementsByTagName("copyright"))
        {
            copyright = cr.getElText();
            break;
        }
        Interface[string] ifaceMap;
        foreach (ifEl; el.getElementsByTagName("interface"))
        {
            auto iface = new Interface(ifEl, name);
            ifaceMap[iface.name] = iface;
            ifaces ~= iface;
        }

        foreach(iface; ifaces)
        {
            foreach(req; iface.requests)
            {
                foreach(arg; req.args)
                {
                    if (arg.type == ArgType.NewId)
                    {
                        auto ifp = arg.iface in ifaceMap;
                        if (ifp) ifp.isGlobal = false;
                    }
                }
            }
        }
    }

    bool isLocalIface(string name)
    {
        return ifaces.map!(iface => iface.name).canFind(name);
    }

    void writeHeader(SourceFile sf, in Options opt)
    {
        import std.path : baseName;
        sf.writeDoc(
            "Module generated by wayland-d:scanner-%s for %s protocol\n" ~
            "  xml protocol:   %s\n" ~
            "  generated code: %s",
                scannerVersion, name,
                (opt.inFile.length ? baseName(opt.inFile) : "stdin"),
                opt.code.to!string
        );
        sf.writeln("module %s;", opt.moduleName);
        sf.writeComment(
            "Protocol copyright:\n\n%s", copyright
        );
        sf.writeComment(
            "Bindings copyright:\n\n%s", bindingsCopyright
        );
    }

    void writeClientCode(SourceFile sf, in Options opt)
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
            iface.writeClientCode(sf);
            sf.writeln();
        }

        // writing private code
        sf.writeln("private:");
        sf.writeln();

        writePrivClientIfaces(sf);
        sf.writeln();

        sf.writeln("extern(C) nothrow");
        sf.bracedBlock!({
            foreach(i, iface; ifaces)
            {
                if (i != 0) sf.writeln();
                iface.writePrivClientListener(sf);
                iface.writePrivClientListenerStubs(sf);
            }
        });
    }

    void writeServerCode(SourceFile sf, in Options opt)
    {
        writeHeader(sf, opt);
        if (name == "wayland") sf.writeln("import wayland.server.core;");
        else sf.writeln("import wayland.server;");
        sf.writeln("import wayland.native.server;");
        sf.writeln("import wayland.native.util;");
        sf.writeln("import wayland.util;");
        sf.writeln();

        foreach(iface; ifaces)
        {
            iface.writeServerCode(sf);
            sf.writeln();
        }

        // writing private code
        sf.writeln("private:");
        sf.writeln();

        //writePrivServerIfaces(sf);
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

    void writePrivClientIfaces(SourceFile sf)
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
        sf.writeln();
        sf.writeln("immutable wl_interface[] wl_ifaces;");
        sf.writeln();
        foreach (i, iface; ifaces)
        {
            sf.writeln("enum %s = %d;", indexSymbol(iface.name), i);
        }
        sf.writeln();
        sf.writeln("shared static this()");
        sf.bracedBlock!({
            sf.writeln("auto ifaces = new wl_interface[%d];", ifaces.length);
            sf.writeln();
            writePrivMsgTypes(sf);
            sf.writeln();
            foreach (iface; ifaces)
            {
                iface.writePrivIfacePopulate(sf);
                sf.writeln();
            }
            sf.writeln("import std.exception : assumeUnique;");
            sf.writeln("wl_ifaces = assumeUnique(ifaces);");
            sf.writeln();
            foreach (iface; ifaces)
            {
                sf.writeln("%sIface = new immutable %sIface( &wl_ifaces[%s] );",
                        camelName(iface.name),
                        titleCamelName(iface.name),
                        indexSymbol(iface.name));
            }
        });
    }

    void writePrivMsgTypes(SourceFile sf)
    {
        size_t max =0;
        foreach (l; ifaces.map!(iface => iface.nullIfaceTypeLength))
        {
            if (l > max) max = l;
        }

        immutable nullLength = max;
        size_t typeIndex = 0;

        sf.writeln("auto msgTypes = [");
        sf.indentedBlock!({
            foreach(i; 0..nullLength)
            {
                sf.writeln("null,");
            }
            foreach (iface; ifaces)
            {
                foreach(msg; chain(iface.requests, iface.events))
                {
                    if (msg.ifaceTypesAllNull)
                    {
                        msg.ifaceTypeIndex = 0;
                        continue;
                    }
                    msg.ifaceTypeIndex = nullLength + typeIndex;
                    typeIndex += msg.args.length;
                    foreach (arg; msg.args)
                    {
                        if (!arg.iface.empty &&
                            (arg.type == ArgType.NewId ||
                                arg.type == ArgType.Object))
                        {
                            if (isLocalIface(arg.iface))
                                sf.writeln("&ifaces[%s],", indexSymbol(arg.iface));
                            else
                                sf.writeln("cast(wl_interface*)%s.iface.native,", ifaceDName(arg.iface));
                        }
                        else
                        {
                            sf.writeln("null,");
                        }
                    }

                }
            }
        });
        sf.writeln("];");
    }
}


// for private wl_interface array
string indexSymbol(in string name) pure
{
    return camelName(name, "index");
}

string ifaceDName(in string name) pure
{
    return titleCamelName(name);
}

string validDName(in string name) pure
{
    switch (name)
    {
        case "class": return "class_";
        case "default": return "default_";
        case "interface": return "iface";
        case "version": return "version_";
        default:
        {
            if (name[0] >= '0' && name[0] <= '9') return "_" ~ name;
            else return name;
        }
    }
}

string getElText(Element el)
{
    string fulltxt;
    foreach (child; el.children)
    {
        if (child.nodeType == NodeType.Text)
        {
            fulltxt ~= child.nodeValue;
        }
    }

    string[] lines;
    string offset;
    bool offsetdone = false;
    foreach (l; fulltxt.split('\n'))
    {
        immutable bool allwhite = l.all!isWhite;
        if (!offsetdone && allwhite) continue;

        if (!offsetdone && !allwhite)
        {
            offsetdone = true;
            offset = l
                    .until!(c => !c.isWhite)
                    .to!string;
        }

        if (l.startsWith(offset))
        {
            l = l[offset.length .. $];
        }

        lines ~= l;
    }

    foreach_reverse(l; lines) {
        if (l.all!isWhite) {
            lines = lines[0..$-1];
        }
        else break;
    }

    return lines.join("\n");
}


class SourceFile
{
    File _output;
    int _indentLev = 0;
    bool _indentNext = true;

    invariant()
    {
        assert(_indentLev >= 0);
    }

    this(File output)
    {
        _output = output;
    }

    @property File output()
    {
        return _output;
    }

    @property int indentLev() const
    {
        return _indentLev;
    }

    void indent()
    {
        _indentLev += 1;
    }

    void unindent()
    {
        _indentLev -= 1;
    }

    void write(Args...)(string codeFmt, Args args)
    {
        immutable code = format(codeFmt, args);
        immutable iStr = indentStr(_indentLev);
        if (_indentNext) _output.write(iStr);
        _output.write(code.replace("\n", "\n"~iStr));
        _indentNext = false;
    }

    void writeln()
    {
        _output.writeln();
        _indentNext = true;
    }

    /++
    +   writes indented code and adds a final '\n'
    +/
    void writeln(Args...)(string codeFmt, Args args)
    {
        immutable code = format(codeFmt, args);
        immutable iStr = indentStr(_indentLev);
        if (_indentNext) _output.write(iStr);
        _output.writeln(code.replace("\n", "\n"~iStr));
        _indentNext = true;
    }

    void writeComment(Args...)(string textFmt, Args args)
    {
        immutable text = format(textFmt, args);
        immutable indStr = indentStr(_indentLev);
        _output.writeln(indStr, "/+");
        foreach (l; text.split("\n")) {
            if (l.empty) _output.writeln(indStr, " +");
            else _output.writeln(indStr, " +  ", l);
        }
        _output.writeln(indStr, " +/");
    }

    void writeDoc(Args...)(string textFmt, Args args)
    {
        immutable text = format(textFmt, args);
        immutable indStr = indentStr(_indentLev);
        _output.writeln(indStr, "/++");
        foreach (l; text.split("\n")) {
            if (l.empty) _output.writeln(indStr, " +");
            else _output.writeln(indStr, " +  ", l);
        }
        _output.writeln(indStr, " +/");
    }
}


void bracedBlock(alias writeF)(SourceFile sf)
{
    sf.writeln("{");
    sf.indent();
    writeF();
    sf.unindent();
    sf.writeln("}");
}

void indentedBlock(alias writeF)(SourceFile sf)
{
    sf.indent();
    writeF();
    sf.unindent();
}


/// Build a camel name from components
string buildCamelName(in string comp, in bool tit) pure
{
    string name;
    bool cap = tit;
    foreach(char c; comp.toLower())
    {
        if (c != '_')
        {
            name ~= cap ? c.toUpper() : c;
            cap = false;
        }
        else
        {
            cap = true;
        }
    }
    return name;
}

string camelName(in string comp) pure
{
    return buildCamelName(comp, false);
}

string titleCamelName(in string comp) pure
{
    return buildCamelName(comp, true);
}

string camelName(in string[] comps...) pure
{
    string name = buildCamelName(comps[0], false);
    foreach (c; comps[1 .. $])
    {
        name ~= buildCamelName(c, true);
    }
    return name;
}

string titleCamelName(in string[] comps...) pure
{
    string name = buildCamelName(comps[0], true);
    foreach (c; comps[1 .. $])
    {
        name ~= buildCamelName(c, true);
    }
    return name;
}

string indentStr(int indent) pure
{
    return "    ".replicate(indent);
}

string qualfiedTypeName(in string name) pure
{
    return name
            .splitter(".")
            .map!(part => titleCamelName(part))
            .join(".");
}

string splitLinesForWidth(string input, in string suffix, in string indent, in size_t width=80) pure
{
    string res;
    size_t w;
    foreach(i, word; input.split(" "))
    {
        if (i != 0)
        {
            string spacer = " ";
            if (w + word.length + suffix.length >= width)
            {
                spacer = suffix ~ "\n" ~ indent;
                w = indent.length;
            }
            res ~= spacer;
        }
        res ~= word;
        w += word.length;
    }
    return res;
}
