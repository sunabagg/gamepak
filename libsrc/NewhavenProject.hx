package;

typedef NewhavenProject = {
    var name: String;
    var version: String;
    var rootUrl: String;
    var type: String;
    var scriptdir: String;
    var assetsdir: String;
    var apisymbols: Bool;
    var sourcemap: Bool;
    var entrypoint: String;
    var pluginEntrypoint: String;
    var luabin: String;
    var libraries: Array<String>;
    var compilerFlags: Array<String>;
}