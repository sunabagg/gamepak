package;

import sys.FileSystem;

class Main {
    public static function main() {
        var currentDirectory = Sys.getCwd();
        trace(currentDirectory);

        var args = Sys.args();
        if (args.length < 1 || args[0] == "-h" || args[0] == "--help") {
            Sys.println("Usage: gamepak <project.nhproj>");
            return;
        }

        var gamepak = new Gamepak();

        var arg1 = args[1];
        if (arg1 == "-O" || arg1 == "-o") {
            var arg2 = args[2];
            gamepak.zipOutputPath = FileSystem.absolutePath(arg2);
        }
        
        var snbprojpath = "";
        for (arg in args) {
            if (StringTools.endsWith(arg, ".snbproj")) {
                snbprojpath = arg;
                break;
            }
        }

        if (snbprojpath == "") {
            Sys.println("Usage: gamepak <project.nhproj>");
            return;
        }

        if (StringTools.contains(snbprojpath, "./")) {
            snbprojpath = StringTools.replace(snbprojpath, "./", currentDirectory);
        }

        for (arg in args) {
            if (StringTools.startsWith(arg, "--markExecutable=")) {
                gamepak.markExecutable = StringTools.replace(arg, "--markExecutable=", "") == "true";
            }
            if (arg == "-nmx") {
                gamepak.markExecutable = false;
            }
        }

        gamepak.build(snbprojpath);
    }
}