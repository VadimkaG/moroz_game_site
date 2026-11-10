const std = @import("std");
const httpz = @import("httpz");
const builtin = @import("builtin");

const AppContext = @import("app.zig");

const IndexPage = @import("page/index.zig");
const AdminPage = @import("page/admin.zig");
const LetterPage = @import("page/letter.zig");

var global_server: ?*httpz.Server(*AppContext) = null;

pub fn main(init: std.process.Init) !void {
    {
        const posix = std.posix;
        var act = posix.Sigaction{
            .handler = .{ .handler = posixCtrlHandler },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        posix.sigaction(posix.SIG.INT, &act, null);
        posix.sigaction(posix.SIG.TERM, &act, null);
    }

    const allocator = init.gpa;

    var app_context = AppContext.init(init.io, allocator);
    try app_context.load();

    const address: httpz.Config.Address = if (builtin.mode == .debug) .localhost(8000) else .{ .unix = "/var/run/sites/moroz_site.sock" };
    var server = try httpz.Server(*AppContext).init(init.io, allocator, .{
        .address = address,
        .workers = .{ .count = 1 },
        .thread_pool = .{ .count = 2 },
        .request = .{
            .max_form_count = 5,
        },
    }, &app_context);
    global_server = &server;

    defer {
        app_context.active = false;
        server.deinit();
        app_context.deinit();
    }

    var router = try server.router(.{});
    router.get("/", IndexPage.handle, .{});
    router.get("/admin", AdminPage.handle, .{});
    router.post("/admin", AdminPage.handleForm, .{});
    router.get("/l/:uid", LetterPage.handle, .{});
    router.get("/l/:uid/my", LetterPage.handleMy, .{});
    router.post("/l/:uid", LetterPage.handleForm, .{});

    if (builtin.mode == .debug) {
        router.get("/*", serveStaticFiles, .{});
    }

    try server.listen();
}

fn posixCtrlHandler(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    if (global_server) |srv| {
        srv.stop();
        global_server = null;
    }
}

fn serveStaticFiles(app: *AppContext, req: *httpz.Request, res: *httpz.Response) !void {
    if (std.mem.indexOf(u8, req.url.path, "..") != null) {
        res.status = 400;
        res.body = "Bad Request";
        return;
    }
    const prefix = "public/";
    const relative_path: []u8 = try res.arena.alloc(u8, req.url.path.len + prefix.len);
    @memcpy(relative_path[0..prefix.len], prefix);
    @memcpy(relative_path[prefix.len..relative_path.len], req.url.path);
    res.body = std.Io.Dir.cwd().readFileAlloc(app.io, relative_path, res.arena, .limited(50 * 1024 * 1024)) catch {
        res.status = 404;
        res.body = "File Not Found";
        return;
    };

    res.content_type = mimeFromPath(relative_path);
}

fn mimeFromPath(path: []const u8) httpz.ContentType {
    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".css")) return .CSS;
    if (std.mem.eql(u8, ext, ".js")) return .JS;
    if (std.mem.eql(u8, ext, ".webp")) return .WEBP;
    if (std.mem.eql(u8, ext, ".svg")) return .SVG;
    if (std.mem.eql(u8, ext, ".png")) return .PNG;
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return .JPG;
    return .UNKNOWN;
}
