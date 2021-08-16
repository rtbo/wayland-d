// Copyright © 2017-2021 Rémi Thebault
/++
 +  Wayland scanner for D.
 +  Scan wayland XML protocol and generates client or server code for that protocol.
 +/
module wayland.scanner;

import wayland.scanner.common;
import wayland.scanner.client;
import wayland.scanner.server;

import arsd.dom;

import std.array;
import std.getopt;
import std.stdio;

enum scannerVersion = "v0.3.1";
enum usageIntro = "wayland:scanner-"~scannerVersion~"\n"~
                  "  A Wayland protocol scanner and D code generator.\n\n";
enum bindingsCopyright = "Copyright © 2017-2019 Rémi Thebault";


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

        if (opt.code == GenCode.client)
            fact = new ClientFactory;
        else
            fact = new ServerFactory;

        auto p = fact.makeProtocol(xmlDoc.root);
        p.writeCode(new SourceFile(output), opt);
    }
    catch(Exception ex)
    {
        stderr.writeln("Error: "~ex.msg);
        return 1;
    }

    return 0;
}

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
