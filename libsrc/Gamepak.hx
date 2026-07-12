package;
import haxe.Json;
import haxe.io.BytesBuffer;
#if lua
import lua.Coroutine;
#end
import haxe.io.Bytes;
import haxe.ds.StringMap;
import sys.io.File;
import sys.FileSystem;
#if lua
#else
import org.msgpack.MsgPack;
#end
class Gamepak {

    public var snbprojPath: String;
    public var projDirPath: String = "";

    public var sprojJson: ProjectFile;

    public var zipOutputPath: String = "";

    public var haxePath: String = "haxe"; // Default path to Haxe compiler

    public var markExecutable: Bool = true; // Whether to mark the output as executable

    public var resourceFormats = [
        ".vscn",
        ".vpfb",
        ".vres",
        ".vchr",
        ".vclt",
        ".vhw",
        ".vdrs",
        ".smdl",
        ".ftd",
    ];

    public function new() {}

    public var chmodder: (String)->Void;

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
            this.sprojJson = haxe.Json.parse(json);
            if (this.sprojJson.language == null || this.sprojJson.language == "")
                this.sprojJson.language = "haxe";
            Sys.println("Successfully loaded project JSON.");

            Sys.println("Project name: " + this.sprojJson.name);
            Sys.println("Project version: " + this.sprojJson.version);
            Sys.println("Project type: " + this.sprojJson.type);
            Sys.println("Script directory: " + this.sprojJson.scriptdir);
            Sys.println("Assets directory: " + this.sprojJson.assetsdir);
            Sys.println("API symbols enabled: " + this.sprojJson.apisymbols);
            Sys.println("Source map enabled: " + this.sprojJson.sourcemap);
            Sys.println("Entrypoint: " + this.sprojJson.entrypoint);
            Sys.println("Lua binary: " + this.sprojJson.luabin);
            Sys.println("Libraries: " + this.sprojJson.libraries.join(", "));
            Sys.println("Compiler flags: " + this.sprojJson.compilerFlags.join(", "));

            if (sprojJson.type == "executable") {
                if (zipOutputPath == "") {
                    zipOutputPath = this.projDirPath + "/bin/" + this.sprojJson.name + ".snb";
                }
                else if (StringTools.endsWith(zipOutputPath, ".slib")) {
                    Sys.println("Warning: Output path ends with .slib, changing to .snb");
                    zipOutputPath = StringTools.replace(zipOutputPath, ".slib", ".snb");
                }
                else if (StringTools.endsWith(zipOutputPath, ".snb")) {
                    // Do nothing, already correct
                }
                else {
                    zipOutputPath += ".snb";
                }
            }
            else if (sprojJson.type == "library" || sprojJson.type == "plugin") {
                if (zipOutputPath == "") {
                    zipOutputPath = this.projDirPath + "/bin/" + this.sprojJson.name + ".slib";
                }
                else if (StringTools.endsWith(zipOutputPath, ".snb")) {
                    Sys.println("Warning: Output path ends with .snb, changing to .slib");
                    zipOutputPath = StringTools.replace(zipOutputPath, ".snb", ".slib");
                }
                else if (StringTools.endsWith(zipOutputPath, ".slib")) {
                    // Do nothing, already correct
                }
                else {
                    zipOutputPath += ".slib";
                }
            } else {
                Sys.println("Unknown project type: " + this.sprojJson.type);
                Sys.exit(1);
                return;
            }

            var mainLuaPath: String = "";
            var mainLuaContent: Bytes = null;

            if (this.sprojJson.language == "haxe") {
                var command = this.generateHaxeBuildCommand();
                Sys.println("Generated Haxe build command: " + command);

                Sys.println("Output path for binary: " + zipOutputPath);

                var hxres = Sys.command("cd \"" + this.projDirPath + "\" && " + command);

                if (hxres != 0) {
                    Sys.println("Haxe build command failed with exit code: " + hxres);
                    Sys.exit(hxres);
                    return;
                }

                Sys.println("Haxe build command executed successfully.");

                mainLuaPath = this.projDirPath + "/" + this.sprojJson.luabin;
                if (!FileSystem.exists(mainLuaPath)) {
                    Sys.println("Main Lua file does not exist: " + mainLuaPath);
                    Sys.exit(1);
                    return;
                }

                //Sys.println("Reading main Lua file: " + mainLuaPath);
                mainLuaContent = File.getBytes(mainLuaPath);
            }

            // Create the zip file using haxe.zip.Writer
            //Sys.println("Creating zip file at: " + zipOutputPath);
            var out = sys.io.File.write(zipOutputPath, true);
            var writer = new haxe.zip.Writer(out);

            var rootFolders: Array<VFolder> = [];
            var rootFiles: Array<VFile> = [];
            var folderMap = new StringMap<VFolder>();

            // Collect all zip entries in a list
            var entries = new haxe.ds.List<haxe.zip.Entry>();

            if (this.sprojJson.language == "haxe") {
                //Sys.println("Adding main Lua file to zip: " + this.snbProjJson.luabin);
                // Add main Lua file to the zip
                var entry:haxe.zip.Entry = {
                    fileName: this.sprojJson.luabin,
                    fileTime: Date.now(),
                    dataSize: mainLuaContent.length,
                    fileSize: mainLuaContent.length,
                    data: mainLuaContent,
                    crc32: haxe.crypto.Crc32.make(mainLuaContent),
                    compressed: false
                };
                entries.add(entry);
                rootFiles.push({
                    name: this.sprojJson.luabin,
                    path: this.sprojJson.luabin
                });
                FileSystem.deleteFile(mainLuaPath);

                if (this.sprojJson.sourcemap != false) {
                    var sourceMapName = this.sprojJson.luabin + ".map";
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
                        rootFiles.push({
                            name: sourceMapName,
                            path: sourceMapName
                        });
                        FileSystem.deleteFile(sourceMapPath);
                    } else {
                        Sys.println("Source map file does not exist, skipping: " + sourceMapName);
                    }
                }
                if (this.sprojJson.apisymbols != false) {
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
                        rootFiles.push({
                            name: "types.xml",
                            path: "types.xml"
                        });
                        FileSystem.deleteFile(typesXmlPath);
                    } else {
                        Sys.println("Types XML file does not exist, skipping.");
                    }
                }
            }


            var assetPath = this.projDirPath + "/" + this.sprojJson.assetsdir;
            if (FileSystem.exists(assetPath)) {
                var assets = this.getAllFiles(assetPath);

                var assetKeys = [];
                for (k in assets.keys()) assetKeys.push(k);
                //Sys.println("Found " + assetKeys.length + " asset files in the project.");

                // Add all asset files to the zip
                for (assetKey in assetKeys) {
                    var newAssetPath = StringTools.replace(assetKey, "assets/", "");
                    var newAssetPathArr = newAssetPath.split("/");
                    if (newAssetPathArr.length > 1) {
                        var folderPath = newAssetPathArr.slice(0, newAssetPathArr.length - 1).join("/");
                        var vfolder: VFolder;
                        if (!folderMap.exists(folderPath)) {
                            vfolder = this.ensureVFolder(folderMap, rootFolders, folderPath);
                        } else {
                            vfolder = folderMap.get(folderPath);
                        }
                        vfolder.files.push({
                            name: newAssetPathArr[newAssetPathArr.length - 1],
                            path: newAssetPath
                        });
                    }
                    else {
                        rootFiles.push({
                            name: newAssetPath,
                            path: newAssetPath
                        });
                    }
                    var assetContent = assets.get(assetKey);
                    for (resourceFormat in resourceFormats) {
                        if (StringTools.endsWith(assetKey, resourceFormat)) {
                            newAssetPath += ".dat";
                            var assetStr = assetContent.toString();
                            var assetData = Json.parse(assetStr);
#if lua
#else
                            assetContent = MsgPack.encode(assetData);
#end
                            break;
                        }
                    }
                    Sys.println("Adding asset file: " + assetKey);
                    var assetEntry:haxe.zip.Entry = {
                        fileName: newAssetPath,
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

            var runtime = this.sprojJson.language;
            if (runtime == "lua") {
                runtime = "sunaba-lua";
            }

            var header : HeaderFile = {
                name: this.sprojJson.name,
                version: this.sprojJson.version,
                rootUrl: this.sprojJson.rootUrl,
                luabin: this.sprojJson.luabin,
                runtime: runtime,
                type: this.sprojJson.type
            };
            rootFiles.push({
                name: "header.json",
                path: "header.json"
            });

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

            var vFileSystem: VFileSystem = {
                folders: rootFolders,
                files: rootFiles
            };

            var vfsjson = haxe.Json.stringify(vFileSystem);
            var vfsEntry:haxe.zip.Entry = {
                fileName: "filesystem.json",
                fileSize: vfsjson.length,
                dataSize: vfsjson.length,
                fileTime: Date.now(),
                data: haxe.io.Bytes.ofString(vfsjson),
                crc32: haxe.crypto.Crc32.make(haxe.io.Bytes.ofString(vfsjson)),
                compressed: false
            };
            entries.add(vfsEntry);

            writer.write(entries);
            // Close the output stream
            out.close();

            if (this.markExecutable) {
                // Mark the output file as executable
                Sys.println("Marking output file as executable: " + zipOutputPath);
                /*var shebang = "#!/usr/bin/env sunaba\n"; // or "#!/usr/bin/env sh\n"
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

                if (sprojJson.type == "executable") {
                    Sys.println("snb file created successfully at: " + zipOutputPath);
                }
                else if (sprojJson.type == "library") {
                    Sys.println("slib file created successfully at: " + zipOutputPath);
                }*/
            }

            
            
        } catch (e: Dynamic) {
            Sys.println("Error loading project JSON: " + e);
            Sys.exit(1);
            return;
        }
    }

    private function ensureVFolder(folderMap:StringMap<VFolder>, rootFolders:Array<VFolder>, folderPath:String): VFolder {
        var segments = folderPath.split("/");
        var parent:VFolder = null;
        var currentPath = "";
        for (segment in segments) {
            currentPath = if (currentPath == "") segment else currentPath + "/" + segment;
            var folder:VFolder;
            if (folderMap.exists(currentPath)) {
                folder = folderMap.get(currentPath);
            } else {
                folder = {
                    name: segment,
                    path: currentPath,
                    folders: [],
                    files: []
                };
                folderMap.set(currentPath, folder);
                if (parent == null) {
                    rootFolders.push(folder);
                } else if (!parent.folders.contains(folder)) {
                    parent.folders.push(folder);
                }
            }
            parent = folder;
        }
        return parent;
    }

    public var jsonToMsgpackConverter: (String) -> Bytes;

    public var cnt: Int = 0;

    public function yield() {
        cnt++;
    #if lua
        Coroutine.yield();
    #end
    }

    public var addToZipFile: (String, Bytes)->Void = null;
    public var createZip: (String)->Void = null;
    public var buildZip: (String)->Void = null;

    public var skipAssets: Bool = false;

#if lua
    public function buildCoroutine(snbprojPath: String): lua.Coroutine<()->Void> {
        if (createZip == null) {
            throw "1";
        }
        if (addToZipFile == null) {
            throw "2";
        }
        if (buildZip == null) {
            throw "3";
        }
    return Coroutine.create(() -> {
#else
    public function buildCoroutine(snbprojPath: String): Void {
        if (createZip == null) {
            throw "1";
        }
        if (addToZipFile == null) {
            throw "2";
        }
        if (buildZip == null) {
            throw "3";
        }
#end

        // ---------------------------------
        // Phase 1: Initial setup and paths
        // ---------------------------------
        cnt = 0;
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
        yield(); // ✅ safe yield

        // ---------------------------
        // Phase 2: Load project JSON
        // ---------------------------
        try {
            var json = sys.io.File.getContent(snbprojPath);
            this.sprojJson = haxe.Json.parse(json);
            if (this.sprojJson.language == null || this.sprojJson.language == "")
                this.sprojJson.language = "haxe";
            Sys.println("Successfully loaded project JSON.");
            Sys.println("Project name: " + this.sprojJson.name);
            Sys.println("Project version: " + this.sprojJson.version);
            Sys.println("Project type: " + this.sprojJson.type);
        } catch (e: Dynamic) {
            Sys.println("Error loading project JSON: " + e);
            throw "Error loading project JSON: " + e;
            return;
        }
        yield();

        // -------------------------------
        // Phase 3: Determine output path
        // -------------------------------
        if (sprojJson.type == "executable") {
            if (zipOutputPath == "") {
                zipOutputPath = this.projDirPath + "/bin/" + this.sprojJson.name + ".snb";
            } else if (StringTools.endsWith(zipOutputPath, ".slib")) {
                Sys.println("Warning: Output path ends with .slib, changing to .snb");
                zipOutputPath = StringTools.replace(zipOutputPath, ".slib", ".snb");
            } else if (!StringTools.endsWith(zipOutputPath, ".snb")) {
                zipOutputPath += ".snb";
            }
        } else if (sprojJson.type == "library" || sprojJson.type == "plugin") {
            if (zipOutputPath == "") {
                zipOutputPath = this.projDirPath + "/bin/" + this.sprojJson.name + ".slib";
            } else if (StringTools.endsWith(zipOutputPath, ".snb")) {
                Sys.println("Warning: Output path ends with .snb, changing to .slib");
                zipOutputPath = StringTools.replace(zipOutputPath, ".snb", ".slib");
            } else if (!StringTools.endsWith(zipOutputPath, ".slib")) {
                zipOutputPath += ".slib";
            }
        } else {
            Sys.println("Unknown project type: " + this.sprojJson.type);
            throw "Unknown project type: " + this.sprojJson.type;
            return;
        }
        yield();

        createZip(zipOutputPath);

        // -----------------------------
        // Phase 4: Haxe build command
        // -----------------------------
        if (this.sprojJson.language == "haxe") {
            var command = this.generateHaxeBuildCommand();
            Sys.println("Generated Haxe build command: " + command);

            var hxres = -1;
            if (Sys.systemName() == "Windows") {
                Sys.setCwd(this.projDirPath);
                hxres = Sys.command("cd " + this.projDirPath + " && " + command);
            }
            else {
                var shellscript = "#!/bin/sh\n";
                shellscript += "cd \"" + this.projDirPath + "\"\n";
                shellscript += command;

                var shpath = this.projDirPath + "/.studio/build-game-code.sh";
                if (StringTools.endsWith(this.projDirPath, "/")) {
                    shpath = this.projDirPath + ".studio/build-game-code.sh";
                }

                File.saveContent(shpath, shellscript);

                chmodder(shpath);

                hxres = Sys.command(shpath);
            }

            if (hxres != 0) {
                Sys.println("Haxe build command failed with exit code: " + hxres);
                throw "Haxe build command failed with exit code: " + hxres;
                return;
            }
            Sys.println("Haxe build command executed successfully.");
            yield();
        }


        var rootFolders: Array<VFolder> = [];
        var rootFiles: Array<VFile> = [];
        var folderMap = new StringMap<VFolder>();

        // ---------------------------------
        // Phase 5: Add main Lua file to zip
        // ---------------------------------
        var mainLuaPath = this.projDirPath + "/" + this.sprojJson.luabin;
        if (this.sprojJson.language == "haxe") {
            trace(mainLuaPath, FileSystem.exists(mainLuaPath));
            if (!FileSystem.exists(mainLuaPath)) {
                Sys.println("Main Lua file does not exist: " + mainLuaPath);
                throw "Main Lua file does not exist: " + mainLuaPath;
                return;
            }

            var mainLuaContent = File.getBytes(mainLuaPath);
            addToZipFile(this.sprojJson.luabin, mainLuaContent);
            rootFiles.push({
                name: this.sprojJson.luabin,
                path: this.sprojJson.luabin
            });
            FileSystem.deleteFile(mainLuaPath);
            Sys.println("Added File: main.lua");
            yield();

            // --------------------------------
            // Phase 6: Add optional source map
            // --------------------------------
            if (this.sprojJson.sourcemap != false) {
                var sourceMapName = this.sprojJson.luabin + ".map";
                var sourceMapPath = this.projDirPath + "/" + sourceMapName;
                if (FileSystem.exists(sourceMapPath)) {
                    var sourceMapContent = File.getBytes(sourceMapPath);
                    addToZipFile(sourceMapName, sourceMapContent);
                    FileSystem.deleteFile(sourceMapPath);
                }
                rootFiles.push({
                    name: sourceMapName,
                    path: sourceMapName
                });
                Sys.println("Added File: " + sourceMapName);
            }
            yield();

            // --------------------------------
            // Phase 7: Add API symbols if any
            // --------------------------------
            if (this.sprojJson.apisymbols != false) {
                var typesXmlPath = this.projDirPath + "/types.xml";
                if (FileSystem.exists(typesXmlPath)) {
                    var typesXmlContent = File.getBytes(typesXmlPath);
                    addToZipFile("types.xml", typesXmlContent);
                    FileSystem.deleteFile(typesXmlPath);
                }
                rootFiles.push({
                    name: "types.xml",
                    path: "types.xml"
                });
                Sys.println("Added File: types.xml");
            }
            yield();
        }

        // ----------------------------
        // Phase 8: Add assets to zip
        // ----------------------------
        var assetPath = this.projDirPath + "/" + this.sprojJson.assetsdir;
        if (FileSystem.exists(assetPath) && skipAssets == false) {
            var assets = this.getAllFilesCR(assetPath);
            yield();
            for (assetKey in assets.keys()) {
                trace(assetKey);
                var assetContent = assets.get(assetKey);
                yield();
                var newAssetPath = StringTools.replace(assetKey, "assets/", "");
                var newAssetPathArr = newAssetPath.split("/");
                if (newAssetPathArr.length > 1) {
                    var folderPath = newAssetPathArr.slice(0, newAssetPathArr.length - 1).join("/");
                    var vfolder: VFolder;
                    if (!folderMap.exists(folderPath)) {
                        vfolder = this.ensureVFolder(folderMap, rootFolders, folderPath);
                    } else {
                        vfolder = folderMap.get(folderPath);
                    }
                    vfolder.files.push({
                        name: newAssetPathArr[newAssetPathArr.length - 1],
                        path: newAssetPath
                    });
                }
                else {
                    rootFiles.push({
                        name: newAssetPath,
                        path: newAssetPath
                    });
                }
                yield();
                for (resourceFormat in resourceFormats) {
                    if (StringTools.endsWith(assetKey, resourceFormat)) {
                        newAssetPath += ".dat";
                        yield();
                        var assetStr = assetContent.toString();
                        yield();
                        assetContent = jsonToMsgpackConverter(assetStr);
                    }
                    yield();
                }
                yield();
                addToZipFile(newAssetPath, assetContent);
                Sys.println("Added File: " + newAssetPath);
                yield();
            }
        }
        yield();


        var runtime = this.sprojJson.language;
        if (runtime == "lua") {
            runtime = "sunaba-lua";
        }

        // ------------------------------
        // Phase 9: Add header.json entry
        // ------------------------------
        var header : HeaderFile = {
            name: this.sprojJson.name,
            version: this.sprojJson.version,
            rootUrl: this.sprojJson.rootUrl,
            luabin: this.sprojJson.luabin,
            runtime: runtime,
            type: this.sprojJson.type
        };
        var headerJson = haxe.Json.stringify(header);
        var headerContent = haxe.io.Bytes.ofString(headerJson);
        addToZipFile("header.json", headerContent);
        rootFiles.push({
            name: "header.json",
            path: "header.json"
        });
        Sys.println("Added File: header.json");
        yield();

        var vFileSystem: VFileSystem = {
            folders: rootFolders,
            files: rootFiles
        };

        var vfsjson = haxe.Json.stringify(vFileSystem);
        addToZipFile("filesystem.json", haxe.io.Bytes.ofString(vfsjson));

        // ---------------------------------
        // Phase 10: Write zip file to disk
        // ---------------------------------
        buildZip(zipOutputPath);
        Sys.println("Zip file created successfully at: " + zipOutputPath);
        yield();

        // ---------------------------------
        // Phase 11: Mark as executable
        // ---------------------------------
        if (this.markExecutable) {
            /*var shebang = "#!/usr/bin/env sunaba\n";
            var zipBytes = File.getBytes(zipOutputPath);
            var shebangBytes = Bytes.ofString(shebang);
            var outputBytes = Bytes.alloc(shebangBytes.length + zipBytes.length);
            outputBytes.blit(0, shebangBytes, 0, shebangBytes.length);
            outputBytes.blit(shebangBytes.length, zipBytes, 0, zipBytes.length);

            var outExec = File.write(zipOutputPath, true);
            outExec.write(outputBytes);
            outExec.close();
            Sys.println("Marked as executable: " + zipOutputPath);*/
        }
        yield();

        Sys.println("Build complete: " + zipOutputPath);
#if lua
    });
#else
#end
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
                    yield();
                }
                yield();
            } else {
                // Read file content
                var content = File.getBytes(filePath);
                var vfilePath = StringTools.replace(filePath, this.projDirPath, "");
                if (StringTools.startsWith(vfilePath, "/")) {
                    vfilePath = vfilePath.substr(1);
                }
                //Sys.println("Adding file to assets: " + vfilePath);
                assets.set(vfilePath, content);
                yield();
            }
        }

        return assets;
    }

    public function buildCoroutineCount(snbprojPath: String): Int {
        // ---------------------------------
        // Phase 1: Initial setup and paths
        // ---------------------------------
        var count = 1;

        count++;

        // -------------------------------
        // Phase 3: Determine output path
        // -------------------------------
        count++;

        if (this.sprojJson.language == "haxe") {
            // -----------------------------
            // Phase 4: Haxe build command
            // -----------------------------
            count++;

            // ---------------------------------
            // Phase 5: Add main Lua file to zip
            // ---------------------------------
            count++;

            // --------------------------------
            // Phase 6: Add optional source map
            // --------------------------------
            count++;

            // --------------------------------
            // Phase 7: Add API symbols if any
            // --------------------------------
            count++;
        }



        // ----------------------------
        // Phase 8: Add assets to zip
        // ----------------------------
        var assetPath = this.projDirPath + "/" + this.sprojJson.assetsdir;
        if (FileSystem.exists(assetPath) && skipAssets == false) {
            var assets = this.getAllFiles(assetPath);
            count += this.getAllFilesCount(assetPath);
            count++;
            for (assetKey in assets.keys()) {
                trace(assetKey);
                var assetContent = assets.get(assetKey);
                count++;
                var newAssetPath = assetKey;
                count++;
                for (resourceFormat in resourceFormats) {
                    if (StringTools.endsWith(assetKey, resourceFormat)) {
                        count++;
                        var assetStr = assetContent.toString();
                        count++;
                    }
                    count++;
                }
                count++;
                count++;
            }
        }
        count++;

        // ------------------------------
        // Phase 9: Add header.json entry
        // ------------------------------
        count++;

        // ---------------------------------
        // Phase 10: Write zip file to disk
        // ---------------------------------
        count++;

        // ---------------------------------
        // Phase 11: Mark as executable
        // ---------------------------------
        if (this.markExecutable) {
            /*var shebang = "#!/usr/bin/env sunaba\n";
            var zipBytes = File.getBytes(zipOutputPath);
            var shebangBytes = Bytes.ofString(shebang);
            var outputBytes = Bytes.alloc(shebangBytes.length + zipBytes.length);
            outputBytes.blit(0, shebangBytes, 0, shebangBytes.length);
            outputBytes.blit(shebangBytes.length, zipBytes, 0, zipBytes.length);

            var outExec = File.write(zipOutputPath, true);
            outExec.write(outputBytes);
            outExec.close();
            Sys.println("Marked as executable: " + zipOutputPath);*/
        }
        count++;

        return count;
}

    private function getAllFilesCount(dir:String): Int{
        var count = 0;
        if (!FileSystem.exists(dir)) {
            throw "Directory does not exist: " + dir;
        }

        var vdir = StringTools.replace(dir, this.projDirPath, "");

        var assets = new StringMap<Bytes>();

        for (f in FileSystem.readDirectory(dir)) {
            var filePath = dir + "/" + f;
            if (FileSystem.isDirectory(filePath)) {
                // Recursively get files from subdirectory
                var subAssets = getAllFilesCount(filePath);
                count += subAssets;
            } else {
                count++;
            }
        }

        return count;
    }

    private function generateHaxeBuildCommand(): String {

        var hxml = generateHaxeBuildHxml();
        var hxmlPath = "" + projDirPath + "/build.hxml";

        File.saveContent(hxmlPath, hxml);

        var haxePath: String = this.haxePath;

        if (StringTools.contains(haxePath, " ")) {
            haxePath = "\"" + this.haxePath + "\"";
        }

        var command = "" + haxePath + " \"" + hxmlPath + "\"";

        return command;
        /*var command = this.haxePath + " --class-path " + this.projDirPath + "/" + this.snbProjJson.scriptdir + " -main " + this.snbProjJson.entrypoint + " --library sunaba";
        if (this.snbProjJson.apisymbols != false) {
            command += " --xml " + this.projDirPath + "/types.xml";
        }
        if (this.snbProjJson.sourcemap != false) {
            command += " -D source-map";
        }
        command += " -lua " + this.projDirPath + "/" + this.snbProjJson.luabin += " -D lua-ver 5.4";

        var librariesStr = "";
        for (lib in this.snbProjJson.libraries) {
            librariesStr += " --library " + lib;
        }
        command += " " + this.snbProjJson.compilerFlags.join(" ");
        return command;*/
    }

    var useExternApi = false;

    private function generateHaxeBuildHxml(): String {
        var command = "--class-path \"" + this.sprojJson.scriptdir + "\"\n-main " + this.sprojJson.entrypoint + "\n--library libsunaba";
        if (sprojJson.type == "plugin") {
            command = "--class-path \"" + this.sprojJson.scriptdir + "\"\n-main " + this.sprojJson.pluginEntrypoint + "\n--library libsunaba\n--library sunaba-studio\n--library gamepak";
        }
        if (this.sprojJson.apisymbols != false) {
            command += "\n--xml types.xml";
        }
        if (this.sprojJson.sourcemap != false) {
            command += "\n-D source-map";
        }
        command += "\n-lua \"" + this.sprojJson.luabin += "\"\n-D lua-vanilla";

        var librariesStr = "";
        for (lib in this.sprojJson.libraries) {
            librariesStr += "\n--library " + lib;
        }
        command += "\n" + this.sprojJson.compilerFlags.join("\n");
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
}