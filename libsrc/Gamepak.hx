package;
import haxe.io.BytesBuffer;
#if lua
import lua.Coroutine;
#end
import haxe.io.Bytes;
import haxe.ds.StringMap;
import sys.io.File;
import sys.FileSystem;

class Gamepak {

    public var snbprojPath: String;
    public var projDirPath: String = "";

    public var nhProjJson: NewhavenProject;

    public var zipOutputPath: String = "";

    public var haxePath: String = "haxe"; // Default path to Haxe compiler

    public var markExecutable: Bool = true; // Whether to mark the output as executable

    public function new() {}

    public function build(snbprojPath: String): Void {
        Sys.println("Building project at: " + snbprojPath);

        snbprojPath = FileSystem.absolutePath(snbprojPath);

        // Here you would implement the logic to build the project
        // For now, we just print a message
        this.snbprojPath = snbprojPath;
        var snbProjPathArray = snbprojPath.split("/");
        this.projDirPath = snbProjPathArray.slice(0, snbProjPathArray.length - 1).join("/");
        Sys.println("Project directory path: " + this.projDirPath);
        var binPath = this.projDirPath + "/bin";
        if (!FileSystem.exists(binPath)) {
            FileSystem.createDirectory(binPath);
            Sys.println("Created bin directory: " + binPath);
        } else {
            Sys.println("Bin directory already exists: " + binPath);
        }

        // Load the XML project file
        try {
            var json = sys.io.File.getContent(snbprojPath);
            this.nhProjJson = haxe.Json.parse(json);
            Sys.println("Successfully loaded project JSON.");

            Sys.println("Project name: " + this.nhProjJson.name);
            Sys.println("Project version: " + this.nhProjJson.version);
            Sys.println("Project type: " + this.nhProjJson.type);
            Sys.println("Script directory: " + this.nhProjJson.scriptdir);
            Sys.println("Assets directory: " + this.nhProjJson.assetsdir);
            Sys.println("API symbols enabled: " + this.nhProjJson.apisymbols);
            Sys.println("Source map enabled: " + this.nhProjJson.sourcemap);
            Sys.println("Entrypoint: " + this.nhProjJson.entrypoint);
            Sys.println("Lua binary: " + this.nhProjJson.luabin);
            Sys.println("Libraries: " + this.nhProjJson.libraries.join(", "));
            Sys.println("Compiler flags: " + this.nhProjJson.compilerFlags.join(", "));

            if (nhProjJson.type == "executable") {
                if (zipOutputPath == "") {
                    zipOutputPath = this.projDirPath + "/bin/" + this.nhProjJson.name + ".nhv";
                }
                else if (StringTools.endsWith(zipOutputPath, ".nlib")) {
                    Sys.println("Warning: Output path ends with .nlib, changing to .nhv");
                    zipOutputPath = StringTools.replace(zipOutputPath, ".nlib", ".nhv");
                }
                else if (StringTools.endsWith(zipOutputPath, ".nhv")) {
                    // Do nothing, already correct
                }
                else {
                    zipOutputPath += ".nhv";
                }
            }
            else if (nhProjJson.type == "library") {
                if (zipOutputPath == "") {
                    zipOutputPath = this.projDirPath + "/bin/" + this.nhProjJson.name + ".nlib";
                }
                else if (StringTools.endsWith(zipOutputPath, ".nhv")) {
                    Sys.println("Warning: Output path ends with .nhv, changing to .nlib");
                    zipOutputPath = StringTools.replace(zipOutputPath, ".nhv", ".nlib");
                }
                else if (StringTools.endsWith(zipOutputPath, ".nlib")) {
                    // Do nothing, already correct
                }
                else {
                    zipOutputPath += ".nlib";
                }
            } else {
                Sys.println("Unknown project type: " + this.nhProjJson.type);
                Sys.exit(1);
                return;
            }

            var command = this.generateHaxeBuildCommand();
            Sys.println("Generated Haxe build command: " + command);

            Sys.println("Output path for binary: " + zipOutputPath);

            var hxres = Sys.command("cd " + this.projDirPath + " && " + command);
            
            if (FileSystem.exists(projDirPath + "/build.hxml"))
                FileSystem.deleteFile(projDirPath + "/build.hxml");

            if (hxres != 0) {
                Sys.println("Haxe build command failed with exit code: " + hxres);
                Sys.exit(hxres);
                return;
            }

            Sys.println("Haxe build command executed successfully.");

            var mainLuaPath = this.projDirPath + "/" + this.nhProjJson.luabin;
            if (!FileSystem.exists(mainLuaPath)) {
                Sys.println("Main Lua file does not exist: " + mainLuaPath);
                Sys.exit(1);
                return;
            }

            //Sys.println("Reading main Lua file: " + mainLuaPath);
            var mainLuaContent = File.getBytes(mainLuaPath);

            // Create the zip file using haxe.zip.Writer
            //Sys.println("Creating zip file at: " + zipOutputPath);
            var out = sys.io.File.write(zipOutputPath, true);
            var writer = new haxe.zip.Writer(out);

            // Collect all zip entries in a list
            var entries = new haxe.ds.List<haxe.zip.Entry>();

            //Sys.println("Adding main Lua file to zip: " + this.snbProjJson.luabin);
            // Add main Lua file to the zip
            var entry:haxe.zip.Entry = {
                fileName: this.nhProjJson.luabin,
                fileTime: Date.now(),
                dataSize: mainLuaContent.length,
                fileSize: mainLuaContent.length,
                data: mainLuaContent,
                crc32: haxe.crypto.Crc32.make(mainLuaContent),
                compressed: false
            };
            entries.add(entry);
            FileSystem.deleteFile(mainLuaPath);

            if (this.nhProjJson.sourcemap != false) {
                var sourceMapName = this.nhProjJson.luabin + ".map";
                var sourceMapPath = this.projDirPath + "/" + sourceMapName;
                if (FileSystem.exists(sourceMapPath)) {
                    //Sys.println("Adding source map file: " + sourceMapName);
                    var sourceMapContent = File.getBytes(sourceMapPath);
                    var sourceMapEntry:haxe.zip.Entry = {
                        fileName: sourceMapName,
                        fileSize: sourceMapContent.length,
                        dataSize: sourceMapContent.length,
                        fileTime: Date.now(),
                        data: sourceMapContent,
                        crc32: haxe.crypto.Crc32.make(sourceMapContent),
                        compressed: false
                    };
                    entries.add(sourceMapEntry);
                    FileSystem.deleteFile(sourceMapPath);
                } else {
                    Sys.println("Source map file does not exist, skipping: " + sourceMapName);
                }
            }
            if (this.nhProjJson.apisymbols != false) {
                var typesXmlPath = this.projDirPath + "/types.xml";
                if (FileSystem.exists(typesXmlPath)) {
                    //Sys.println("Adding types XML file: types.xml");
                    var typesXmlContent = File.getBytes(typesXmlPath);
                    var typesXmlEntry:haxe.zip.Entry = {
                        fileName: "types.xml",
                        fileSize: typesXmlContent.length,
                        dataSize: typesXmlContent.length,
                        fileTime: Date.now(),
                        data: typesXmlContent,
                        crc32: haxe.crypto.Crc32.make(typesXmlContent),
                        compressed: false
                    };
                    entries.add(typesXmlEntry);
                    FileSystem.deleteFile(typesXmlPath);
                } else {
                    Sys.println("Types XML file does not exist, skipping.");
                }
            }


            var assetPath = this.projDirPath + "/" + this.nhProjJson.assetsdir;
            if (FileSystem.exists(assetPath)) {
                var assets = this.getAllFiles(assetPath);

                var assetKeys = [];
                for (k in assets.keys()) assetKeys.push(k);
                //Sys.println("Found " + assetKeys.length + " asset files in the project.");

                // Add all asset files to the zip
                for (assetKey in assetKeys) {
                    var assetContent = assets.get(assetKey);
                    //Sys.println("Adding asset file: " + assetKey);
                    var assetEntry:haxe.zip.Entry = {
                        fileName: StringTools.replace(assetKey, "assets/", ""),
                        fileSize: assetContent.length,
                        dataSize: assetContent.length,
                        fileTime: Date.now(),
                        data: assetContent,
                        crc32: haxe.crypto.Crc32.make(assetContent),
                        compressed: false
                    };
                    entries.add(assetEntry);
                }
            }
            

            Sys.println("creating header for zip file");

            var header : HeaderFile = {
                name: this.nhProjJson.name,
                version: this.nhProjJson.version,
                rootUrl: this.nhProjJson.rootUrl,
                luabin: this.nhProjJson.luabin,
                type: this.nhProjJson.type
            };

            var headerJson = haxe.Json.stringify(header);
            Sys.println("Adding header to zip file: header.json");
            var headerContent = haxe.io.Bytes.ofString(headerJson);
            var headerEntry:haxe.zip.Entry = {
                fileName: "header.json",
                fileSize: headerContent.length,
                dataSize: headerContent.length,
                fileTime: Date.now(),
                data: headerContent,
                crc32: haxe.crypto.Crc32.make(headerContent),
                compressed: false
            };
            entries.add(headerEntry);
            

            writer.write(entries);
            // Close the output stream
            out.close();

            if (this.markExecutable) {
                // Mark the output file as executable
                Sys.println("Marking output file as executable: " + zipOutputPath);
                var shebang = "#!/usr/bin/env sunaba\n"; // or "#!/usr/bin/env sh\n"
                var zipBytes = File.getBytes(zipOutputPath);
                var shebangBytes = Bytes.ofString(shebang);
        
                // Combine shebang + zip
                var outputBytes = Bytes.alloc(shebangBytes.length + zipBytes.length);
                outputBytes.blit(0, shebangBytes, 0, shebangBytes.length);
                outputBytes.blit(shebangBytes.length, zipBytes, 0, zipBytes.length);

                // Write to new executable file
                var out = File.write(zipOutputPath, true); // binary mode
                out.write(outputBytes);
                out.close();

                if (nhProjJson.type == "executable") {
                    Sys.println("nhv file created successfully at: " + zipOutputPath);
                }
                else if (nhProjJson.type == "library") {
                    Sys.println("nlib file created successfully at: " + zipOutputPath);
                }
            }

            
            
        } catch (e: Dynamic) {
            Sys.println("Error loading project JSON: " + e);
            Sys.exit(1);
            return;
        }
    }

#if lua
    public function buildCoroutine(snbprojPath: String): lua.Coroutine<()->Void> {
    return Coroutine.create(() -> {

        // ---------------------------------
        // Phase 1: Initial setup and paths
        // ---------------------------------
        Sys.println("Building project at: " + snbprojPath);

        if (StringTools.contains(snbprojPath, "\\")) {
            snbprojPath = StringTools.replace(snbprojPath, "\\", "/");
        }
        this.snbprojPath = snbprojPath;
        var snbProjPathArray = snbprojPath.split("/");
        this.projDirPath = snbProjPathArray.slice(0, snbProjPathArray.length - 1).join("/");
        Sys.println("Project directory path: " + this.projDirPath);

        var binPath = this.projDirPath + "/bin";
        if (!FileSystem.exists(binPath)) {
            FileSystem.createDirectory(binPath);
            Sys.println("Created bin directory: " + binPath);
        } else {
            Sys.println("Bin directory already exists: " + binPath);
        }
        Coroutine.yield(); // ✅ safe yield

        var entries = new haxe.ds.List<haxe.zip.Entry>();

        // ---------------------------
        // Phase 2: Load project JSON
        // ---------------------------
        try {
            var json = sys.io.File.getContent(snbprojPath);
            this.nhProjJson = haxe.Json.parse(json);
            Sys.println("Successfully loaded project JSON.");
            Sys.println("Project name: " + this.nhProjJson.name);
            Sys.println("Project version: " + this.nhProjJson.version);
            Sys.println("Project type: " + this.nhProjJson.type);
        } catch (e: Dynamic) {
            Sys.println("Error loading project JSON: " + e);
            throw "Error loading project JSON: " + e;
            return;
        }
        Coroutine.yield();

        // -------------------------------
        // Phase 3: Determine output path
        // -------------------------------
        if (nhProjJson.type == "executable") {
            if (zipOutputPath == "") {
                zipOutputPath = this.projDirPath + "/bin/" + this.nhProjJson.name + ".nhv";
            } else if (StringTools.endsWith(zipOutputPath, ".nlib")) {
                Sys.println("Warning: Output path ends with .nlib, changing to .nhv");
                zipOutputPath = StringTools.replace(zipOutputPath, ".nlib", ".nhv");
            } else if (!StringTools.endsWith(zipOutputPath, ".nhv")) {
                zipOutputPath += ".nhv";
            }
        } else if (nhProjJson.type == "library") {
            if (zipOutputPath == "") {
                zipOutputPath = this.projDirPath + "/bin/" + this.nhProjJson.name + ".nlib";
            } else if (StringTools.endsWith(zipOutputPath, ".nhv")) {
                Sys.println("Warning: Output path ends with .nhv, changing to .nlib");
                zipOutputPath = StringTools.replace(zipOutputPath, ".nhv", ".nlib");
            } else if (!StringTools.endsWith(zipOutputPath, ".nlib")) {
                zipOutputPath += ".nlib";
            }
        } else {
            Sys.println("Unknown project type: " + this.nhProjJson.type);
            throw "Unknown project type: " + this.nhProjJson.type;
            return;
        }
        Coroutine.yield();

        // -----------------------------
        // Phase 4: Haxe build command
        // -----------------------------
        var command = this.generateHaxeBuildCommand();
        Sys.println("Generated Haxe build command: " + command);

        var hxres = Sys.command("cd " + this.projDirPath + " && " + command);

        if (FileSystem.exists(projDirPath + "/build.hxml"))
                FileSystem.deleteFile(projDirPath + "/build.hxml");

        if (hxres != 0) {
            Sys.println("Haxe build command failed with exit code: " + hxres);
            throw "Haxe build command failed with exit code: " + hxres;
            return;
        }
        Sys.println("Haxe build command executed successfully.");
        Coroutine.yield();

        // ---------------------------------
        // Phase 5: Add main Lua file to zip
        // ---------------------------------
        var mainLuaPath = this.projDirPath + "/" + this.nhProjJson.luabin;
        trace(mainLuaPath, FileSystem.exists(mainLuaPath));
        if (!FileSystem.exists(mainLuaPath)) {
            Sys.println("Main Lua file does not exist: " + mainLuaPath);
            throw "Main Lua file does not exist: " + mainLuaPath;
            return;
        }

        var mainLuaContent = File.getContent(mainLuaPath);
        entries.add({
            fileName: this.nhProjJson.luabin,
            fileTime: Date.now(),
            dataSize: mainLuaContent.length,
            fileSize: mainLuaContent.length,
            data: Bytes.ofString(mainLuaContent),
            crc32: null,
            compressed: false
        });
        FileSystem.deleteFile(mainLuaPath);
        Sys.println("Added File: main.lua");
        Coroutine.yield();

        // --------------------------------
        // Phase 6: Add optional source map
        // --------------------------------
        if (this.nhProjJson.sourcemap != false) {
            var sourceMapName = this.nhProjJson.luabin + ".map";
            var sourceMapPath = this.projDirPath + "/" + sourceMapName;
            if (FileSystem.exists(sourceMapPath)) {
                var sourceMapContent = File.getContent(sourceMapPath);
                entries.add({
                    fileName: sourceMapName,
                    fileSize: sourceMapContent.length,
                    dataSize: sourceMapContent.length,
                    fileTime: Date.now(),
                    data: Bytes.ofString(sourceMapContent),
                    crc32: null,
                    compressed: false
                });
                FileSystem.deleteFile(sourceMapPath);
            }
            Sys.println("Added File: " + sourceMapName);
        }
        Coroutine.yield();

        // --------------------------------
        // Phase 7: Add API symbols if any
        // --------------------------------
        if (this.nhProjJson.apisymbols != false) {
            var typesXmlPath = this.projDirPath + "/types.xml";
            if (FileSystem.exists(typesXmlPath)) {
                var typesXmlContent = File.getContent(typesXmlPath);
                entries.add({
                    fileName: "types.xml",
                    fileSize: typesXmlContent.length,
                    dataSize: typesXmlContent.length,
                    fileTime: Date.now(),
                    data: Bytes.ofString(typesXmlContent),
                    crc32: null,
                    compressed: false
                });
                FileSystem.deleteFile(typesXmlPath);
            }
            Sys.println("Added File: types.xml");
        }
        Coroutine.yield();

        // ----------------------------
        // Phase 8: Add assets to zip
        // ----------------------------
        var assetPath = this.projDirPath + "/" + this.nhProjJson.assetsdir;
        if (FileSystem.exists(assetPath)) {
            var assets = this.getAllFilesCR(assetPath);
            Coroutine.yield();
            for (assetKey in assets.keys()) {
                trace(assetKey);
                var assetContent = assets.get(assetKey);
                entries.add({
                    fileName: StringTools.replace(assetKey, "assets/", ""),
                    fileSize: assetContent.length,
                    dataSize: assetContent.length,
                    fileTime: Date.now(),
                    data: assetContent,
                    crc32: null,
                    compressed: false
                });
                Sys.println("Added File: " + StringTools.replace(assetKey, "assets/", ""));
                Coroutine.yield();
            }
        }
        Coroutine.yield();

        // ------------------------------
        // Phase 9: Add header.json entry
        // ------------------------------
        var header : HeaderFile = {
            name: this.nhProjJson.name,
            version: this.nhProjJson.version,
            rootUrl: this.nhProjJson.rootUrl,
            luabin: this.nhProjJson.luabin,
            type: this.nhProjJson.type
        };
        var headerJson = haxe.Json.stringify(header);
        var headerContent = haxe.io.Bytes.ofString(headerJson);
        entries.add({
            fileName: "header.json",
            fileSize: headerContent.length,
            dataSize: headerContent.length,
            fileTime: Date.now(),
            data: headerContent,
            crc32: null,
            compressed: false
        });
        Sys.println("Added File: header.json");
        Coroutine.yield();

        // ---------------------------------
        // Phase 10: Write zip file to disk
        // ---------------------------------
        var out = sys.io.File.write(zipOutputPath, true);
        var writer = new haxe.zip.Writer(out);
        writer.write(entries);
        out.close();
        Sys.println("Zip file created successfully at: " + zipOutputPath);
        Coroutine.yield();

        // ---------------------------------
        // Phase 11: Mark as executable
        // ---------------------------------
        if (this.markExecutable) {
            var shebang = "#!/usr/bin/env sunaba\n";
            var zipBytes = File.getBytes(zipOutputPath);
            var shebangBytes = Bytes.ofString(shebang);
            var outputBytes = Bytes.alloc(shebangBytes.length + zipBytes.length);
            outputBytes.blit(0, shebangBytes, 0, shebangBytes.length);
            outputBytes.blit(shebangBytes.length, zipBytes, 0, zipBytes.length);

            var outExec = File.write(zipOutputPath, true);
            outExec.write(outputBytes);
            outExec.close();
            Sys.println("Marked as executable: " + zipOutputPath);
        }
        Coroutine.yield();

        Sys.println("Build complete: " + zipOutputPath);
    });
}

#end

    private function generateHaxeBuildCommand(): String {

        var hxml = generateHaxeBuildHxml();
        var hxmlPath = "" + projDirPath + "/build.hxml";

        File.saveContent(hxmlPath, hxml);

        var command = "" +this.haxePath + " '" + hxmlPath + "'";

        return command;
        /*var command = this.haxePath + " --class-path " + this.projDirPath + "/" + this.snbProjJson.scriptdir + " -main " + this.snbProjJson.entrypoint + " --library sunaba";
        if (this.snbProjJson.apisymbols != false) {
            command += " --xml " + this.projDirPath + "/types.xml";
        }
        if (this.snbProjJson.sourcemap != false) {
            command += " -D source-map";
        }
        command += " -lua " + this.projDirPath + "/" + this.snbProjJson.luabin += " -D lua-vanilla";

        var librariesStr = "";
        for (lib in this.snbProjJson.libraries) {
            librariesStr += " --library " + lib;
        }
        command += " " + this.snbProjJson.compilerFlags.join(" ");
        return command;*/
    }

    var useExternApi = false;

    private function generateHaxeBuildHxml(): String {
        var command = "--class-path '" + this.nhProjJson.scriptdir + "'\n-main " + this.nhProjJson.entrypoint + "\n--library sunaba";
        if (useExternApi)
            command = "--class-path '" + this.nhProjJson.scriptdir + "'\n-main " + this.nhProjJson.entrypoint + "\n--library sunaba-extern";
        if (this.nhProjJson.apisymbols != false) {
            command += "\n--xml types.xml";
        }
        if (this.nhProjJson.sourcemap != false) {
            command += "\n-D source-map";
        }
        command += "\n-lua '" + this.nhProjJson.luabin += "'\n-D lua-vanilla";

        var librariesStr = "";
        for (lib in this.nhProjJson.libraries) {
            librariesStr += "\n--library " + lib;
        }
        command += "\n" + this.nhProjJson.compilerFlags.join("\n");
        return command;
    }

    private function getAllFiles(dir:String): StringMap<Bytes> {
        if (!FileSystem.exists(dir)) {
            throw "Directory does not exist: " + dir;
        }

        var vdir = StringTools.replace(dir, this.projDirPath, "");

        var assets = new StringMap<Bytes>();

        for (f in FileSystem.readDirectory(dir)) {
            var filePath = dir + "/" + f;
            if (FileSystem.isDirectory(filePath)) {
                // Recursively get files from subdirectory
                var subAssets = getAllFiles(filePath);
                for (key in subAssets.keys()) {
                    assets.set(key, subAssets.get(key));
                }
            } else {
                // Read file content
                var content = File.getBytes(filePath);
                var vfilePath = StringTools.replace(filePath, this.projDirPath, "");
                if (StringTools.startsWith(vfilePath, "/")) {
                    vfilePath = vfilePath.substr(1);
                }
                //Sys.println("Adding file to assets: " + vfilePath);
                assets.set(vfilePath, content);
            }
        }

        return assets;
    }

    private function getAllFilesCR(dir:String): StringMap<Bytes> {
        if (!FileSystem.exists(dir)) {
            throw "Directory does not exist: " + dir;
        }

        var vdir = StringTools.replace(dir, this.projDirPath, "");

        var assets = new StringMap<Bytes>();

        for (f in FileSystem.readDirectory(dir)) {
            var filePath = dir + "/" + f;
            if (FileSystem.isDirectory(filePath)) {
                // Recursively get files from subdirectory
                var subAssets = getAllFilesCR(filePath);
                for (key in subAssets.keys()) {
                    assets.set(key, subAssets.get(key));
                }
            } else {
                // Read file content
                var content = File.getContent(filePath);
                var vfilePath = StringTools.replace(filePath, this.projDirPath, "");
                if (StringTools.startsWith(vfilePath, "/")) {
                    vfilePath = vfilePath.substr(1);
                }
                //Sys.println("Adding file to assets: " + vfilePath);
                assets.set(vfilePath, Bytes.ofString(content));
            }
        }

        return assets;
    }
}