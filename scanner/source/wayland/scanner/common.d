// Copyright © 2017-2021 Rémi Thebault
/++
 +  Wayland scanner for D.
 +  Generation of common protocol code.
 +/
module wayland.scanner.common;

import wayland.scanner;

import arsd.dom;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import std.uni;

interface Factory
{
    Protocol makeProtocol(Element el);
    Interface makeInterface(Element el, Protocol protocol);
    Message makeMessage(Element el, Interface iface);
    Arg makeArg(Element el);
}

Factory fact;


void writeMultilineParenthesis(SourceFile sf, in string before,
            in string[] args, in string after)
{
    immutable indent = ' '.repeat(before.length+1).array();
    sf.write("%s(", before);
    foreach (i, a; args)
    {
        if (i != 0)
        {
            sf.writeln(",");
            sf.write(indent);
        }
        sf.write(a);
    }
    sf.writeln(")%s", after);
}

void writeDelegateAlias(SourceFile sf, string name, string ret, string[] rtArgs)
{
    immutable fstLine = format("alias %s = %s delegate(", name, ret);
    immutable indent = ' '.repeat(fstLine.length).array();
    sf.write(fstLine);
    foreach(i, rta; rtArgs)
    {
        if (i != 0)
        {
            sf.writeln(",");
            sf.write(indent);
        }
        sf.write(rta);
    }
    sf.writeln(");");
}

void writeFnSigRaw(SourceFile sf, string qualifiers, string ret, string name,
                string[] rtArgs, string[] ctArgs=[], string constraint="")
{
    immutable ctSig = ctArgs.length ? format("!(%(%s, %))", ctArgs) : "";
    immutable qual = qualifiers.length ? format("%s ", qualifiers) : "";
    immutable fstLine = format("%s%s %s%s(", qual, ret, name, ctSig);
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
    sf.write(")");
    if (constraint.length)
    {
        sf.write("if (%s)", constraint);
    }
}

void writeFnSig(SourceFile sf, string ret, string name, string[] rtArgs,
                string[] ctArgs=[], string constraint="")
{
    writeFnSigRaw(sf, "", ret, name, rtArgs, ctArgs, constraint);
    sf.writeln();
}

void writeFnExpr(SourceFile sf, string stmt, string[] exprs)
{
    sf.writeln("%s(", stmt);
    sf.indentedBlock!({
        immutable ic = sf.indentChars;
        int width = ic;
        foreach (i, e; exprs)
        {
            if (i != 0)
            {
                sf.write(",");
                width += 1;
            }
            width += e.length;
            if (width > wrapWidth)
            {
                sf.writeln();
                width = ic;
            }
            else if (i != 0)
            {
                sf.write(" ");
                width += 1;
            }
            sf.write(e);
        }
    });
    sf.writeln();
    sf.writeln(");");
}

void writeFnPointer(SourceFile sf, string name, string ret, string[] args)
{
    writeMultilineParenthesis(
        sf, format("%s function", ret), args, format(" %s;", name)
    );
}

void writeFnBody(SourceFile sf, string[] preStmts, string mainStmt,
                string[] exprs, string[] postStmt)
{
    sf.bracedBlock!({
        foreach (ps; preStmts)
        {
            sf.writeln(ps);
        }
        writeFnExpr(sf, mainStmt, exprs);
        foreach (ps; postStmt)
        {
            sf.writeln(ps);
        }
    });
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
            summary = replace(summary, "\n", " ");
            summary = tr(summary, " ", " ", "s");
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



abstract class Arg
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

    abstract @property string dType() const
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
            case ArgType.NewId:
                assert(false, "must be implemented in subclasses");
            case ArgType.Array:
                return "wl_array*"; // ?? let's check this later
            case ArgType.Fd:
                return "int";
            case ArgType.Object:
                assert(false, "must be implemented in subclasses");
        }
    }

    abstract @property string cType() const
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
                assert(false, "unimplemented");
            case ArgType.NewId:
                assert(false, "must be implemented in subclasses");
            case ArgType.Array:
                return "wl_array*";
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
            case ArgType.NewId:
                return paramName;
            case ArgType.Array:
                return paramName;
            case ArgType.Fd:
                return paramName;
            case ArgType.Object:
                assert(false, "must be implemented in subclasses");
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
                assert(false, "unimplemented");
            case ArgType.NewId:
                return paramName;
            case ArgType.Array:
                return paramName;
            case ArgType.Fd:
                return paramName;
        }
    }
}

abstract class Message
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
    Interface iface;
    int since = 1;
    bool isDtor;
    Description description;
    Arg[] args;

    string[] argIfaceTypes;
    size_t ifaceTypeIndex;
    Type type;

    ReqType reqType;
    Arg reqRet;

    this (Element el, Interface iface)
    {
        assert(el.tagName == "request" || el.tagName == "event");
        this.iface = iface;
        name = el.getAttribute("name");
        if (el.hasAttribute("since"))
        {
            since = el.getAttribute("since").to!int;
        }
        isDtor = (el.getAttribute("type") == "destructor");
        description = new Description(el);
        foreach (argEl; el.getElementsByTagName("arg"))
        {
            args ~= fact.makeArg(argEl);
        }

        argIfaceTypes = args
            .filter!(a => a.type == ArgType.NewId || a.type == ArgType.Object)
            .map!(a => a.iface)
            .filter!(iface => iface.length != 0)
            .array();

        type = el.tagName == "event" ? Type.event : Type.request;

        if (type == Type.request)
        {
            auto crr = reqReturn;
            reqRet = crr[0];
            reqType = crr[1];
        }
    }

    @property string ifaceName()
    {
        return iface.name;
    }

    @property Tuple!(Arg, ReqType) reqReturn()
    {
        Arg ret;
        ReqType rt;
        foreach (arg; args)
        {
            if (arg.type == ArgType.NewId)
            {
                enforce(!ret, "more than 1 new-id for a request!");
                ret = arg;
                rt = arg.iface.length ? ReqType.newObj : ReqType.dynObj;
            }
        }
        if (!ret)
        {
            rt = ReqType.void_;
        }
        return tuple(ret, rt);
    }

    @property bool ifaceTypesAllNull() const
    {
        return argIfaceTypes.empty;
    }

    @property size_t nullIfaceTypeLength() const
    {
        return argIfaceTypes.empty ? args.length : 0;
    }

    @property string dMethodName()
    {
        return validDName(camelName(name));
    }

    @property string opCodeName()
    {
        return format("%sOpCode", camelName(name));
    }

    @property string onOpCodeName()
    {
        return format("on%sOpCode", titleCamelName(name));
    }

    @property string dHandlerName()
    {
        return "on" ~ titleCamelName(name);
    }

    @property string dEvDgType()
    {
        return "On" ~ titleCamelName(name) ~ "EventDg";
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

    void writePrivIfaceMsg(SourceFile sf)
    {
        sf.writeln(
            "wl_message(\"%s\", \"%s\", &msgTypes[%d]),",
            name, signature, ifaceTypeIndex
        );
    }
}


abstract class Interface
{
    Protocol protocol;
    string name;
    string ver;
    Description description;
    Message[] requests;
    Message[] events;
    Enum[] enums;

    // indicate that is created by server rather than by client request.
    // protocal eventually set to false after all interfaces are parsed
    bool isGlobal = true;


    private static Interface[string] ifaceMap;

    static Interface get(string name)
    {
        auto i = name in ifaceMap;
        if (i) return *i;
        else return null;
    }

    this (Element el, Protocol protocol)
    {
        assert(el.tagName == "interface");
        this.protocol = protocol;
        name = el.getAttribute("name");
        ver = el.getAttribute("version");
        description = new Description(el);
        foreach (rqEl; el.getElementsByTagName("request"))
        {
            requests ~= fact.makeMessage(rqEl, this);
        }
        foreach (evEl; el.getElementsByTagName("event"))
        {
            events ~= fact.makeMessage(evEl, this);
        }
        foreach (enEl; el.getElementsByTagName("enum"))
        {
            enums ~= new Enum(enEl, name);
        }
        ifaceMap[name] = this;
    }

    abstract void writeCode(SourceFile sf);

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

    void writeVersion(SourceFile sf)
    {
        sf.writeln("/// Version of %s.%s", protocol.name, name);
        sf.writeln("enum ver = %s;", ver);
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


abstract class Protocol
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
            auto iface = fact.makeInterface(ifEl, this);
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

    abstract void writeCode(SourceFile sf, in Options opt);

    abstract void writePrivIfaces(SourceFile sf);

    abstract void writeNativeIfacesAssignment(SourceFile sf);

    bool isLocalIface(string name)
    {
        return ifaces.map!(iface => iface.name).canFind(name);
    }

    void writeHeader(SourceFile sf, in Options opt)
    {
        import std.path : baseName;
        sf.writeDoc(
            "Module generated by wayland:scanner-%s for %s protocol\n" ~
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

    void writeNativeIfaces(SourceFile sf)
    {
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
            writeNativeIfacesAssignment(sf);
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
        case "alias": return "alias_";
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

    @property int indentChars() const
    {
        return _indentLev * charsPerIndent;
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
            if (l.empty) {
                _output.writeln(indStr, " +");
            }
            else {
                _output.write(indStr, " +  ");
                foreach (dchar c; l) {
                    switch (c) {
                    case '(': _output.write("$(LPAREN)"); break;
                    case ')': _output.write("$(RPAREN)"); break;
                    case '<': _output.write("&lt;"); break;
                    case '>': _output.write("&gt;"); break;
                    case '&': _output.write("&amp;"); break;
                    default: _output.write(c); break;
                    }
                }
                _output.writeln();
            }
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

enum charsPerIndent = 4;
enum wrapWidth = 80;

string indentStr(int indent) pure
{
    return ' '.repeat(indent * charsPerIndent).array();
}

string qualfiedTypeName(in string name) pure
{
    return name
            .splitter(".")
            .map!(part => titleCamelName(part))
            .join(".");
}

string splitLinesForWidth(string input, in string suffix, in string indent,
                        in size_t width=wrapWidth) pure
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
