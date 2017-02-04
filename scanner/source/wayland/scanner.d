module wayland.scanner;

import std.stdio;
import std.getopt;
import std.array;

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
        defaultGetoptPrinter("A Wayland protocol scanner and D code generator",
                optHandler.options);
        return 0;
    }

    if (opt.moduleName.empty)
    {
        stderr.writeln("D module name must be supplied with --module or -m");
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
    }
    catch(Exception ex)
    {
        stderr.writeln("Error: "~ex.msg);
        return 1;
    }

    return 0;
}

private:

import arsd.dom;

import std.algorithm;
import std.conv;
import std.uni : toUpper, isWhite;

enum scannerVersion = "v0.0.1";

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

    bool opCast(T)() const if (is(T == bool))
    {
        return !summary.empty || !text.empty;
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

        import std.exception : enforce;
        enforce(!value.empty, "enum entries without value aren't supported");
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
        return ifaceName ~ "_" ~ name;
    }

    bool entriesHaveDoc() const
    {
        return entries.any!(e => !e.summary.empty);
    }

}



class Arg
{
    string name;
    string summary;
    string iface;
    ArgType type;

    this (Element el)
    {
        assert(el.tagName == "arg");
        name = el.getAttribute("name");
        summary = el.getAttribute("summary");
        iface = el.getAttribute("interface");
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
    }

    @property string dType() const
    {
        final switch(type)
        {
            case ArgType.Int:
                return "int ";
            case ArgType.UInt:
                return "uint ";
            case ArgType.Fixed:
                return "wl_fixed_t ";
            case ArgType.String:
                return "const(char) *";
            case ArgType.Object:
                return iface ~ " *";
            case ArgType.NewId:
                return "uint ";
            case ArgType.Array:
                return "wl_array *";
            case ArgType.Fd:
                return "int ";
        }
    }

    @property string dName() const
    {
        if (name == "interface")
        {
            return "iface";
        }
        else if (name == "version")
        {
            return "ver";
        }
        return name;
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
    }

    @property string opCodeSym() const
    {
        return ifaceName.toUpper ~ "_" ~ name.toUpper;
    }


}


class Interface
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


    @property bool haveListener() const
    {
        return !events.empty;
    }

    @property bool haveInterface() const
    {
        return !requests.empty;
    }


}


class Protocol
{
    string name;
    string copyright;
    Interface[] ifaces;

    this(Element el)
    {
        import std.exception : enforce;
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

}


string getElText(Element el)
{
    string fulltxt;
    foreach (child; el.children) {
        if (child.nodeType == NodeType.Text) {
            fulltxt ~= child.nodeValue;
        }
    }

    string[] lines;
    string offset;
    bool offsetdone = false;
    foreach (l; fulltxt.split('\n')) {
        immutable bool allwhite = l.all!isWhite;
        if (!offsetdone && allwhite) continue;

        if (!offsetdone && !allwhite) {
            offsetdone = true;
            offset = l
                    .until!(c => !c.isWhite)
                    .to!string;
        }

        if (l.startsWith(offset)) {
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


