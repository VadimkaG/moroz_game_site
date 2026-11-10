const std = @import("std");
const httpz = @import("httpz");
const App = @import("../app.zig");
const Layout = @import("../layout/layout.zig");

const LETTERS_DIR_NAME = "letters";

fn parceTemplate() type {
    comptime {
        @setEvalBranchQuota(100_000);
        const html: []const u8 = @embedFile("admin.html");

        const block_start = "<TPL:USER>";
        const block_end = "</TPL:USER>";

        var index: usize = 0;

        // Начало блока
        if (std.mem.find(u8, html, block_start)) |i| {
            index = i;
        } else @compileError("Не найдено начало блока admin user");

        const _before = html[0..index];
        var html_slice: []const u8 = html[index + block_start.len ..];

        // Конец блока
        if (std.mem.find(u8, html_slice, block_end)) |i| {
            index = i;
        } else @compileError("Не найден конец блока admin user");

        const _element = html_slice[0..index];
        const _after = html_slice[index + block_end.len ..];

        return struct {
            pub const before: [_before.len]u8 = _before.*;
            pub const element: [_element.len]u8 = _element.*;
            pub const after: [_after.len]u8 = _after.*;
        };
    }
}
pub const Template = parceTemplate();

/// Проверить авторизацию
fn checkAuth(app: *App, req: *httpz.Request) !bool {
    if (req.header("authorization")) |auth_header| {
        if (std.mem.startsWith(u8, auth_header, "Basic ")) {
            const encoded = auth_header[6..];
            var decode_buf: [128]u8 = undefined;
            const decoder = std.base64.standard.Decoder;
            const decoded_size = decoder.calcSizeForSlice(encoded) catch return false;
            if (decoded_size > decode_buf.len) return false;
            try decoder.decode(&decode_buf, encoded);
            var it = std.mem.splitScalar(u8, decode_buf[0..decoded_size], ':');
            const user = it.next() orelse "";
            const pass = it.next() orelse "";
            if (std.mem.eql(u8, user, app.admin_login[0]) and std.mem.eql(u8, pass, app.admin_login[1]))
                return true;
        }
    }
    return false;
}
/// Обработка GET запроса
pub fn handle(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    try app.lock();
    defer app.unlock();

    if (!try checkAuth(app, req)) {
        res.status = 401;
        res.header("WWW-Authenticate", "Basic realm=\"Admin Area\"");
        res.body = "Необходима авторизация.";
        return;
    }
    const writer = res.writer();
    try writer.writeAll(Layout.Header);

    try writer.writeAll(Template.before[0..]);
    var iter = app.users.valueIterator();
    while (iter.next()) |value| {
        try writer.print(Template.element[0..], .{
            value.uid,
            value.uid,
            if (value.is_ready) "Да" else "Нет",
            value.uid,
        });
    }
    try writer.print(Template.after[0..], .{
        if (app.is_game_started) "started" else if (app.ready_count < app.users.count() or app.users.count() < 3) "not_ready" else "ready",
    });

    try writer.writeAll(Layout.Footer);
}
/// Обработка POST форм
pub fn handleForm(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    try app.lock();
    defer app.unlock();
    if (!try checkAuth(app, req)) {
        res.status = 401;
        res.header("WWW-Authenticate", "Basic realm=\"Admin Area\"");
        res.body = "Необходима авторизация.";
        return;
    }
    var form = try req.formData();

    const cwd = std.Io.Dir.cwd();

    // Добавить одного пользователя
    if (form.get("user_add")) |_| {
        if (app.is_game_started) {
            res.status = 403;
            return;
        }
        if (app.users.count() < 40) {
            var raw_bytes: [16]u8 = undefined;
            var is_unique = false;
            while (!is_unique) {
                app.io.random(&raw_bytes);
                const id = std.fmt.bytesToHex(raw_bytes, .lower);
                if (!app.users.contains(id[0..])) {
                    is_unique = true;
                    const string_slice = try app.allocator.alloc(u8, id.len);
                    @memcpy(string_slice, id[0..]);
                    try app.users.put(string_slice, .{
                        .uid = string_slice,
                        .target = &.{},
                        .is_ready = false,
                    });
                }
            }
            try app.save();
        }

        // Массовое добавление пользователей
    } else if (form.get("generate_users")) |users_count| {
        if (app.is_game_started) {
            res.status = 403;
            return;
        }
        if (app.users.count() > 0) {
            app.clearUsers();
            try cwd.deleteTree(app.io, LETTERS_DIR_NAME);
        }
        const num = try std.fmt.parseInt(usize, users_count, 10);
        if (num > 2 and num <= 40) {
            var raw_bytes: []u8 = try res.arena.alloc(u8, num * 16);
            app.io.random(raw_bytes);
            for (0..num) |i| {
                var is_unique = false;
                while (!is_unique) {
                    const i_mul = i * 16;
                    var bytes: [16]u8 = undefined;
                    @memcpy(bytes[0..], raw_bytes[i_mul .. i_mul + 16]);
                    const id = std.fmt.bytesToHex(bytes, .lower);
                    if (!app.users.contains(id[0..])) {
                        is_unique = true;
                        const string_slice = try app.allocator.alloc(u8, id.len);
                        @memcpy(string_slice, id[0..]);
                        try app.users.put(string_slice, .{
                            .uid = string_slice,
                            .target = &.{},
                            .is_ready = false,
                        });
                    } else app.io.random(raw_bytes);
                }
            }
            try app.save();
        }
        // Удалить пользователя
    } else if (form.get("del_user")) |uid| {
        if (app.is_game_started) {
            res.status = 403;
            return;
        }
        if (app.users.contains(uid)) {
            if (app.users.get(uid)) |user| {
                if (user.is_ready)
                    app.ready_count -= 1;
                const uid_slice = user.uid;
                _ = app.users.remove(uid);
                const dir_opt = cwd.openDir(app.io, LETTERS_DIR_NAME, .{}) catch |err| switch (err) {
                    error.FileNotFound => null,
                    else => return err,
                };
                if (dir_opt) |*dir| {
                    defer dir.close(app.io);
                    try dir.deleteFile(app.io, uid_slice);
                }
                app.allocator.free(uid_slice);
                try app.save();
            }
        }
    } else if (form.get("game_status")) |status| {
        if (std.mem.eql(u8, status, "start") and !app.is_game_started) {
            var keys: [][]const u8 = undefined;
            {
                keys = try res.arena.alloc([]const u8, app.users.count());
                var it = app.users.keyIterator();
                var idx: usize = 0;
                while (it.next()) |key| {
                    keys[idx] = key.*;
                    idx += 1;
                }
            }

            // Алгоритм Саттоло
            {
                var io_source: std.Random.IoSource = .{ .io = app.io };
                const rand = io_source.interface();
                var i: usize = keys.len;
                while (i > 1) {
                    i -= 1;
                    const j = rand.uintLessThan(usize, i);
                    const temp = keys[i];
                    keys[i] = keys[j];
                    keys[j] = temp;
                }
            }

            for (0..keys.len) |i| {
                if (app.users.getPtr(keys[i])) |user| {
                    user.target = keys[(i + 1) % keys.len];
                }
            }
            app.is_game_started = true;
            try app.save();
        } else if (std.mem.eql(u8, status, "stop")) {
            app.is_game_started = false;
            try app.save();
        }
    }

    res.status = 303;
    res.header("Location", req.header("referer") orelse "/");
}
