const std = @import("std");
const httpz = @import("httpz");
const App = @import("../app.zig");
const Layout = @import("../layout/layout.zig");
const Slider = @import("../block/slider.zig");
const IndexPage = @import("index.zig");

const LETTERS_DIR_NAME = "letters";

fn htmlEscape(allocator: std.mem.Allocator, dest: *std.ArrayList(u8), src: []const u8) !void {
    for (src) |b| {
        switch (b) {
            '<' => try dest.appendSlice(allocator, "&lt;"),
            '>' => try dest.appendSlice(allocator, "&gt;"),
            '&' => try dest.appendSlice(allocator, "&amp;"),
            '"' => try dest.appendSlice(allocator, "&quot;"),
            '\'' => try dest.appendSlice(allocator, "&#x27;"),
            else => try dest.append(allocator, b),
        }
    }
}
fn htmlEscapeN(allocator: std.mem.Allocator, dest: *std.ArrayList(u8), src: []const u8) !void {
    for (src) |b| {
        switch (b) {
            '<' => try dest.appendSlice(allocator, "&lt;"),
            '>' => try dest.appendSlice(allocator, "&gt;"),
            '&' => try dest.appendSlice(allocator, "&amp;"),
            '"' => try dest.appendSlice(allocator, "&quot;"),
            '\'' => try dest.appendSlice(allocator, "&#x27;"),
            '\n' => try dest.appendSlice(allocator, "<br>"),
            else => try dest.append(allocator, b),
        }
    }
}

pub fn handle(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const userId = req.param("uid") orelse {
        res.status = 400;
        return;
    };
    var letter_uid: []const u8 = undefined;
    var is_game_started = false;
    {
        try app.lock();
        defer app.unlock();
        if (!app.users.contains(userId)) {
            res.body = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><title>Дедушка Морозушка</title></head><body><h1>Упс...</h1><p>Похоже что ссылка не действительна.</p></body></html>";
            res.status = 404;
            return;
        }
        is_game_started = app.is_game_started;
        if (app.is_game_started) {
            const user = app.users.get(userId) orelse {
                res.body = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><title>Дедушка Морозушка</title></head><body><h1>Упс...</h1><p>Письмо не дошло до вас =(<br>Похоже на какуюто ошибку. Сообщи Вадиму.</p></body></html>";
                res.status = 400;
                return;
            };
            letter_uid = user.target;
        } else letter_uid = userId;
    }

    const letter_form_html = @embedFile("letter_form.html");

    const writer = res.writer();
    try writer.writeAll(Layout.Header);

    try writer.writeAll(IndexPage.Template.before[0..]);
    const images_ids = [_]u8{ 0, 1, 2 };
    try Slider.write(writer, images_ids[0..]);
    try writer.writeAll(IndexPage.Template.after_slider[0..]);

    const cwd = std.Io.Dir.cwd();
    var dir_opt = cwd.openDir(app.io, LETTERS_DIR_NAME, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (dir_opt) |*dir| {
        defer dir.close(app.io);
        var file_opt: ?std.Io.File = dir.openFile(app.io, letter_uid, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (file_opt) |*file| {
            const file_stat = try file.stat(app.io);
            const file_buffer = try res.arena.alloc(u8, file_stat.size);
            const amt = try file.readPositionalAll(app.io, file_buffer, 0);
            const file_content = file_buffer[0..amt];
            if (file_content.len > 0) {
                var line_iter = std.mem.tokenizeScalar(u8, file_content, '\n');
                const saved_name = line_iter.next() orelse "";
                const saved_message = line_iter.rest();

                var restored_name = try std.ArrayList(u8).initCapacity(res.arena, saved_name.len * 8);
                var restored_message = try std.ArrayList(u8).initCapacity(res.arena, saved_message.len * 8);

                if (is_game_started) {
                    try htmlEscapeN(res.arena, &restored_name, saved_name);
                    try htmlEscapeN(res.arena, &restored_message, saved_message);
                    const letter_html = @embedFile("letter.html");
                    try writer.print(letter_html, .{
                        userId,
                        // Содержимое поля имени
                        restored_name.items,
                        // Содержимое письма
                        restored_message.items,
                    });
                } else {
                    try htmlEscape(res.arena, &restored_name, saved_name);
                    try htmlEscape(res.arena, &restored_message, saved_message);
                    try writer.print(letter_form_html, .{
                        // Содержимое поля имени
                        restored_name.items,
                        // Содержимое письма
                        restored_message.items,
                        // Название кнопки
                        "Отправить письмо",
                    });
                }
                try writer.writeAll(IndexPage.Template.after[0..]);
                try writer.writeAll(Layout.Footer);
                return;
            }
        }
    }

    try writer.print(letter_form_html, .{
        // Содержимое поля имени
        "",
        // Содержимое письма
        "",
        // Название кнопки
        "Отправить письмо",
    });
    try writer.writeAll(IndexPage.Template.after[0..]);
    try writer.writeAll(Layout.Footer);
}
/// Собственное письмо
pub fn handleMy(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const userId = req.param("uid") orelse {
        res.status = 400;
        return;
    };
    var user: App.User = undefined;
    {
        try app.lock();
        defer app.unlock();
        if (!app.is_game_started) {
            res.status = 403;
            return;
        }
        if (!app.users.contains(userId)) {
            res.body = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><title>Дедушка Морозушка</title></head><body><h1>Упс...</h1><p>Похоже что ссылка не действительна.</p></body></html>";
            res.status = 404;
            return;
        }
        user = app.users.get(userId) orelse {
            res.status = 404;
            return;
        };
    }
    const writer = res.writer();

    const cwd = std.Io.Dir.cwd();
    var dir_opt = cwd.openDir(app.io, LETTERS_DIR_NAME, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (dir_opt) |*dir| {
        defer dir.close(app.io);
        var file_opt: ?std.Io.File = dir.openFile(app.io, userId, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (file_opt) |*file| {
            const file_stat = try file.stat(app.io);
            const file_buffer = try res.arena.alloc(u8, file_stat.size);
            const amt = try file.readPositionalAll(app.io, file_buffer, 0);
            const file_content = file_buffer[0..amt];
            if (file_content.len > 0) {
                var line_iter = std.mem.tokenizeScalar(u8, file_content, '\n');
                const saved_name = line_iter.next() orelse "";
                const saved_message = line_iter.rest();

                var restored_name = try std.ArrayList(u8).initCapacity(res.arena, saved_name.len * 8);
                try htmlEscapeN(res.arena, &restored_name, saved_name);

                var restored_message = try std.ArrayList(u8).initCapacity(res.arena, saved_message.len * 8);
                try htmlEscapeN(res.arena, &restored_message, saved_message);

                res.header("Content-Type", "text/html; charset=utf-8");
                try writer.print("<p><b>От кого:</b> {s}</p><p class=\"letter-text\">{s}</p>", .{
                    // Содержимое поля имени
                    restored_name.items,
                    // Содержимое письма
                    restored_message.items,
                });
                return;
            }
        }
    }

    res.status = 404;
}
/// Обработка формы
pub fn handleForm(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const userId = req.param("uid") orelse {
        res.status = 400;
        return;
    };
    {
        try app.lock();
        defer app.unlock();
        if (app.is_game_started) {
            res.status = 403;
            return;
        }
        if (!app.users.contains(userId)) {
            res.body = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><title>Дедушка Морозушка</title></head><body><h1>Упс...</h1><p>Похоже что ссылка не действительна.</p></body></html>";
            res.status = 404;
            return;
        }
    }

    var form = try req.formData();
    if (form.get("name")) |f_name| {
        if (form.get("message")) |f_message| {
            const f_name_len = try std.unicode.utf8CountCodepoints(f_name);
            const f_message_len = try std.unicode.utf8CountCodepoints(f_message);

            // Проверка длинны
            if (f_name_len < 2 or f_name_len > 30 or f_message_len < 10 or f_message_len > 10000) {
                res.status = 400;
                return;
            }

            const cwd = std.Io.Dir.cwd();
            cwd.createDir(app.io, LETTERS_DIR_NAME, .executable_file) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };

            var dir = try cwd.openDir(app.io, LETTERS_DIR_NAME, .{});
            defer dir.close(app.io);

            const file = try dir.createFile(app.io, userId, .{});
            defer file.close(app.io);

            var file_buffer: [4096]u8 = undefined;
            var file_writer = file.writer(app.io, &file_buffer);
            for (f_name) |b| {
                if (b != '\n' and b != '\r') {
                    try file_writer.interface.writeByte(b);
                }
            }
            try file_writer.interface.writeAll("\n");
            try file_writer.interface.writeAll(f_message);

            try file_writer.flush();

            {
                try app.lock();
                defer app.unlock();
                if (form.get("not_ready")) |is_not_ready| {
                    if (app.users.getPtr(userId)) |user| {
                        const is_ready = !(std.mem.eql(u8, is_not_ready, "true") or std.mem.eql(u8, is_not_ready, "on"));
                        if (is_ready and !user.is_ready) {
                            user.is_ready = true;
                            app.ready_count += 1;
                            try app.save();
                        } else if (!is_ready and user.is_ready) {
                            user.is_ready = false;
                            app.ready_count -= 1;
                            try app.save();
                        }
                    }
                } else {
                    if (app.users.getPtr(userId)) |user| {
                        if (!user.is_ready) {
                            user.is_ready = true;
                            app.ready_count += 1;
                            try app.save();
                        }
                    }
                }
            }

            res.body = "Ok.";
            return;
        }
    }

    res.status = 400;
}
