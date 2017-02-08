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

    enforce(opt.code == GenCode.client, "Only client generator is implemented at this time");

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
        p.writeClientCode(new SourceFile(output), opt);
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


interface ClientCodeGen
{
    void writeClientCode(SourceFile sf);
}

interface ClientPrivCodeGen
{
    void writePrivClientCode(SourceFile sf);
}


class Description : ClientCodeGen
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

    override void writeClientCode(SourceFile sf)
    {
        if (empty) return;
        sf.writeDoc("%s\n\n%s", summary, text);
    }
}


class EnumEntry : ClientCodeGen
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

    override void writeClientCode(SourceFile sf)
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


class Enum : ClientCodeGen
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

    override void writeClientCode(SourceFile sf)
    {
        description.writeClientCode(sf);
        sf.writeln("enum %s : uint", dName);
        sf.bracedBlock!({
            foreach(entry; entries)
            {
                entry.writeClientCode(sf);
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
                    return titleCamelName(iface);
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
                //return format("%s.proxy", paramName);
                return "null"; // FIXME!
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
    string name;
    string ifaceName;
    int since = 1;
    bool isDtor;
    Description description;
    Arg[] args;

    string[] argIfaceTypes;
    size_t ifaceTypeIndex;

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
    }

    @property bool ifaceTypesAllNull() const
    {
        return argIfaceTypes.empty;
    }

    @property size_t nullIfaceTypeLength() const
    {
        return argIfaceTypes.empty ? args.length : 0;
    }

    @property string dEvName()
    {
        return validDName(camelName(name));
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
                {
                    stderr.writeln("NewId to be checked");
                    sig ~= "su";
                }
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

    @property Tuple!(Arg, string) clientReqReturn()
    {
        Arg ret;
        string retStr;
        foreach (arg; args)
        {
            if (arg.type == ArgType.NewId)
            {
                enforce(!ret, "more than 1 new-id for a request");
                ret = arg;
                if (arg.iface.length)
                {
                    retStr = titleCamelName(arg.iface);
                }
                else
                {
                    retStr = "WlProxy";
                }
            }
        }
        if (!ret) retStr = "void";
        return tuple(ret, retStr);
    }

    void writeClientRequestCode(SourceFile sf)
    {
        description.writeClientCode(sf);
        // writing sig
        auto ret = clientReqReturn;
        immutable fstLine = format("%s %s(", ret[1], camelName(name));
        immutable indent = ' '.repeat().take(fstLine.length).array();
        sf.write(fstLine);
        bool hadLine;
        foreach (i, arg; args)
        {
            if (hadLine) sf.writeln(","); // write previous comma

            string line;
            if (arg.type == ArgType.NewId && arg.iface.empty)
                line = "immutable(WlInterface) iface, uint ver";
            else if (arg.type != ArgType.NewId)
                line = format("%s %s", arg.dType, arg.paramName);

            if (hadLine && line) sf.write(indent);
            sf.write(line);
            if (line.length) hadLine = true;
        }
        sf.writeln(")");
        // writing body
        sf.bracedBlock!({
            if (ret[0] && ret[0].iface.empty)
            {
                sf.writeln("return (cast(immutable(ClientWlInterface))iface)");
                sf.writeln("    .makeProxy(wl_proxy_marshal_constructor_versioned(");
                sf.write("        proxy, %sOpcode, iface.native, ver", camelName(name));
            }
            else if (ret[0])
            {
                sf.writeln("return new %s(wl_proxy_marshal_constructor(", ret[1]);
                sf.write("    proxy, %sOpcode, %sInterface.native",
                        camelName(name), camelName(ifaceName));
            }
            else
            {
                if (isDtor) sf.writeln("super.destroyNotify();");
                sf.writeln("wl_proxy_marshal(");
                sf.write("    proxy, %sOpcode", camelName(name));
            }
            foreach (arg; args)
            {
                if (arg.type == ArgType.NewId)
                {
                    if (arg.iface.empty)
                        sf.write(", iface.native.name, ver");
                    sf.write(", null");
                }
                else
                {
                    sf.write(", %s", arg.cCastExpr);
                }
            }
            sf.writeln();
            if (ret[0] && ret[0].iface.empty)
                sf.writeln("    )");
            else if (ret[0])
                sf.write(")");
            sf.writeln(");");
        });
    }

    void writeClientEventSig(SourceFile sf)
    {
        description.writeClientCode(sf);
        immutable fstLine = format("void %s(", dEvName);
        immutable indent = ' '.repeat().take(fstLine.length).array();
        string eol = args.length ? "," : ");";
        sf.writeln("%s%s %s%s", fstLine, titleCamelName(ifaceName), camelName(ifaceName), eol);
        foreach(i, arg; args)
        {
            eol = i == args.length-1 ? ");" : ",";
            sf.writeln("%s%s %s%s", indent, arg.dType, arg.paramName, eol);
        }
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
        immutable lstEol = format(") %s;", validDName(name));

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
        immutable fstLine = format("void on_%s_%s(", ifaceName, name);
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
            sf.writeln("auto _p = enforce(cast(%s)WlProxy.get(proxy));", titleCamelName(ifaceName));
            string sep = args.length ? ", " : "";
            sf.write("_p.listener.%s(_p%s", dEvName, sep);
            foreach (i, arg; args)
            {
                sep = (i == args.length-1) ? "" : ", ";
                sf.write("%s%s", arg.dCastExpr(ifaceName), sep);
            }
            sf.writeln(");");
        });
    }
}


class Interface : ClientCodeGen
{
    string name;
    string ver;
    Description description;
    Message[] requests;
    Message[] events;
    Enum[] enums;

    this (Element el)
    {
        assert(el.tagName == "interface");
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
        return titleCamelName(name);
    }

    @property size_t nullIfaceTypeLength()
    {
        return chain(requests, events)
            .map!(msg => msg.nullIfaceTypeLength)
            .maxElement();
    }

    void writeConstants(SourceFile sf)
    {
        foreach(i, msg; requests)
        {
            sf.writeln("enum %sOpcode = %d;", camelName(msg.name), i);
        }
        sf.writeln();
        foreach(msg; chain(events, requests))
        {
            sf.writeln("enum %sSinceVersion = %d;", camelName(msg.name), msg.since);
        }
    }

    void writeVersionCode(SourceFile sf)
    {
        sf.writeln("override @property uint ver()");
        sf.bracedBlock!({
            sf.writeln("return wl_proxy_get_version(proxy);");
        });
    }

    void writeClientDtorCode(SourceFile sf)
    {
        immutable hasDtor = requests.canFind!(rq => rq.isDtor);
        immutable hasDestroy = requests.canFind!(rq => rq.name == "destroy");

        enforce(!hasDestroy || hasDtor);

        if (!hasDestroy && name != "wl_display")
        {
            sf.writeln();
            sf.writeln("void destroy()");
            sf.bracedBlock!({
                sf.writeln("super.destroyNotify();");
                sf.writeln("wl_proxy_destroy(proxy);");
            });
        }
    }

    override void writeClientCode(SourceFile sf)
    {
        description.writeClientCode(sf);

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
            });

            sf.writeln();
            writeConstants(sf);
            sf.writeln();
            writeVersionCode(sf);
            foreach (en; enums)
            {
                sf.writeln();
                en.writeClientCode(sf);
            }
            writeClientDtorCode(sf);
            foreach (msg; requests)
            {
                sf.writeln();
                msg.writeClientRequestCode(sf);
            }
            if (events.length)
            {
                sf.writeln();
                sf.writeln("/// interface listening to events issued from a %s", dName);
                sf.writeln("interface Listener");
                sf.bracedBlock!({
                    foreach (i, msg; events)
                    {
                        if (i != 0) sf.writeln();
                        msg.writeClientEventSig(sf);
                    }
                });
                sf.writeln();
                sf.writeln("private Listener _listener;");
                sf.writeln();
                sf.writeln("/// Get the listener bound to this object.");
                sf.writeln("@property Listener listener()");
                sf.bracedBlock!({
                    sf.writeln("return _listener;");
                });
                sf.writeln();
                sf.writeln("/// Bind the supplied listener to this object and start listening.");
                sf.writeln("///");
                sf.writeln("/// It is an error to rebind an already bound listener.");
                sf.writeln("@property void listener(Listener listener)");
                sf.bracedBlock!({
                    sf.writeln("assert(!_listener);");
                    sf.writeln("_listener = listener;");
                });
            }
        });
    }

    void writePrivListener(SourceFile sf)
    {
        if (events.empty) return;

        sf.writeln("struct %s_listener", name);
        sf.bracedBlock!({
            foreach(ev; events)
            {
                ev.writePrivListenerSig(sf);
            }
        });
        sf.writeln();
    }

    void writePrivListenerStubs(SourceFile sf)
    {
        foreach(ev; events)
        {
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
        foreach (ifEl; el.getElementsByTagName("interface"))
        {
            ifaces ~= new Interface(ifEl);
        }
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
        sf.writeln("import wayland.client.core;");
        sf.writeln("import wayland.native.client;");
        sf.writeln("import wayland.native.util;");
        sf.writeln("import wayland.util;");
        sf.writeln();
        sf.writeln("import std.exception : enforce;");
        sf.writeln("import std.string : fromStringz, toStringz;");
        sf.writeln();
        foreach(iface; ifaces)
        {
            sf.writeln("immutable WlInterface %sInterface;", camelName(iface.name));
        }
        sf.writeln();

        foreach(iface; ifaces)
        {
            iface.writeClientCode(sf);
            sf.writeln();
        }

        // writing private code
        sf.writeln("private:");
        sf.writeln();

        writePrivIfaces(sf);
        sf.writeln();

        sf.writeln("extern(C) nothrow");
        sf.bracedBlock!({
            foreach(iface; ifaces)
            {
                iface.writePrivListener(sf);
            }
        });

        sf.writeln();
        foreach(iface; ifaces)
        {
            iface.writePrivListenerStubs(sf);
        }
    }

    void writePrivIfaces(SourceFile sf)
    {
        foreach (iface; ifaces)
        {
            sf.writeln("immutable final class %sInterface : ClientWlInterface",
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
                        sf.writeln("return new %s(proxy);", titleCamelName(iface.name));
                });
            });
            sf.writeln();
        }
        sf.writeln("immutable wl_interface[] wl_interfaces;");
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
            sf.writeln("wl_interfaces = assumeUnique(ifaces);");
            sf.writeln();
            foreach (iface; ifaces)
            {
                sf.writeln("%sInterface = new immutable %sInterface( &wl_interfaces[%s] );",
                        camelName(iface.name),
                        titleCamelName(iface.name),
                        indexSymbol(iface.name));
            }
        });
    }

    void writePrivMsgTypes(SourceFile sf)
    {
        immutable nullLength = ifaces
            .map!(iface => iface.nullIfaceTypeLength)
            .maxElement();
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
                            sf.writeln("&ifaces[%s],", indexSymbol(arg.iface));
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
