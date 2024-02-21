# Smart Card Raw Interface
This library is a thin layer of abstraction above WinSCard on Windows and PCSClite on Linux for communicating with smart cards.

## Usage
Take a look at the example in `example/`.

You'll need to add the library as a dependency:
```
.scraw = .{
    .url = "https://github.com/tomasz-lisowski/scraw/archive/<commit__hash>.tar.gz",
    .hash = "<hash>",
},
```

In your `build.zig` you will also need to add:
```
const dep_scraw = b.dependency("scraw", .{
    .target = target,
    .optimize = optimize,
});
```
```
exe.linkLibC();
if (target.result.os.tag == .windows) {
    exe.linkSystemLibrary("winscard");
} else if (target.result.os.tag == .linux) {
    exe.linkSystemLibrary("pcsclite");
} else {
    @panic("Platform unsupported.");
}
exe.root_module.addImport("scraw", dep_scraw.module("scraw"));
```
