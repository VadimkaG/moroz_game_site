const std = @import("std");
const httpz = @import("httpz");

pub const User = struct {
    // Идентификатор
    uid: []const u8,
    // Кому дарит подарок
    target: []const u8,
    // Готов ли пользователь
    is_ready: bool,
};

active: bool,
io: std.Io,
allocator: std.mem.Allocator,
mutex: std.Io.Mutex,
admin_login: [2][]u8,
is_game_started: bool,
users: std.StringHashMap(User),
ready_count: u8,

/// Инициализация контекста приложения
pub fn init(io: std.Io, allocator: std.mem.Allocator) @This() {
    return .{
        .active = true,
        .io = io,
        .allocator = allocator,
        .mutex = .init,
        .admin_login = .{ &.{}, &.{} },
        .is_game_started = false,
        .users = std.StringHashMap(User).init(allocator),
        .ready_count = 0,
    };
}
pub fn deinit(self: *@This()) void {
    var key_it = self.users.keyIterator();
    while (key_it.next()) |key_ptr| {
        self.allocator.free(key_ptr.*);
    }
    self.allocator.free(self.admin_login[0]);
    self.allocator.free(self.admin_login[1]);
    self.users.deinit();
}
pub fn clearUsers(self: *@This()) void {
    var key_it = self.users.keyIterator();
    while (key_it.next()) |key_ptr| {
        self.allocator.free(key_ptr.*);
    }
    self.users.clearRetainingCapacity();
}
/// Страница не найдена
pub fn notFound(_: *@This(), _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 404;
    res.body = "Page not found!";
}
/// Неизвестная ошибка
pub fn uncaughtError(_: *@This(), req: *httpz.Request, res: *httpz.Response, errr: anyerror) void {
    std.debug.print("uncaught http error at {s}: {}\n", .{ req.url.path, errr });

    res.headers.add("content-type", "text/html; charset=utf-8");
    res.status = 505;
    res.body = "<!DOCTYPE html>(╯°□°)╯︵ ┻━┻";
}
/// Синхронизация мультипоточности
pub fn lock(self: *@This()) !void {
    try self.mutex.lock(self.io);
}
/// Выход из синхронизхации мультипоточности
pub fn unlock(self: *@This()) void {
    self.mutex.unlock(self.io);
}
/// Сохранить состояние в файл
pub fn save(self: *@This()) !void {
    const cwd = std.Io.Dir.cwd();

    const file = try cwd.createFile(self.io, "state", .{});
    defer file.close(self.io);

    var file_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(self.io, &file_buffer);

    try file_writer.interface.writeAll(self.admin_login[0]);
    try file_writer.interface.writeByte('\t');
    try file_writer.interface.writeAll(self.admin_login[1]);
    try file_writer.interface.writeByte('\n');

    try file_writer.interface.writeByte(if (self.is_game_started) '1' else '0');
    try file_writer.interface.writeByte('\n');

    var iter = self.users.valueIterator();
    while (iter.next()) |value| {
        try file_writer.interface.writeAll(value.uid);
        try file_writer.interface.writeByte('\t');
        try file_writer.interface.writeByte(if (value.is_ready) '1' else '0');
        try file_writer.interface.writeByte('\t');
        if (value.target.len > 0)
            try file_writer.interface.writeAll(value.target);
        try file_writer.interface.writeByte('\n');
    }
    try file_writer.flush();
}
/// Прочитать конфигурацию с сайта
pub fn load(self: *@This()) !void {
    self.ready_count = 0;
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();

    const cwd = std.Io.Dir.cwd();
    var file_opt: ?std.Io.File = cwd.openFile(self.io, "state", .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (file_opt) |*file| {
        defer file.close(self.io);
        const file_stat = try file.stat(self.io);
        const file_buffer = try arena_allocator.alloc(u8, file_stat.size);
        const len = try file.readPositionalAll(self.io, file_buffer, 0);

        var slice = file_buffer[0..len];

        // Логин админа
        if (std.mem.find(u8, slice, "\t")) |i| {
            self.admin_login[0] = try self.allocator.alloc(u8, i);
            @memcpy(self.admin_login[0], slice[0..i]);
            if (i + 1 > slice.len)
                return;
            slice = slice[i + 1 ..];
        } else return;

        // Пароль админа
        if (std.mem.find(u8, slice, "\n")) |i| {
            self.admin_login[1] = try self.allocator.alloc(u8, i);
            @memcpy(self.admin_login[1], slice[0..i]);
            if (i + 1 > slice.len)
                return;
            slice = slice[i + 1 ..];
        } else return;

        // Начата ли игра
        if (std.mem.find(u8, slice, "\n")) |i| {
            if (slice[i - 1] == '1') {
                self.is_game_started = true;
            } else self.is_game_started = false;
            slice = slice[i + 1 ..];
        } else return;

        const TargetField = struct {
            uid: []u8,
            target: []const u8,
        };
        var targets_list = try std.ArrayList(TargetField).initCapacity(arena_allocator, 20);

        defer {
            for (targets_list.items) |item| {
                if (self.users.getPtr(item.uid)) |user| {
                    if (self.users.get(item.target)) |target_user| {
                        user.target = target_user.uid;
                    }
                }
            }
        }

        // Перебираем пользователей
        while (true) {
            var uid: []u8 = undefined;
            var is_ready = false;

            // uid
            if (std.mem.find(u8, slice, "\t")) |i| {
                uid = try self.allocator.alloc(u8, i);
                @memcpy(uid, slice[0..i]);
                if (i + 1 > slice.len)
                    return;
                slice = slice[i + 1 ..];
            } else return;

            // Готов ли пользователь
            if (std.mem.find(u8, slice, "\t")) |i| {
                if (slice[i - 1] == '1') {
                    is_ready = true;
                    self.ready_count += 1;
                } else is_ready = false;
                slice = slice[i + 1 ..];
            } else return;

            // Target
            if (std.mem.find(u8, slice, "\n")) |i| {
                try targets_list.append(arena_allocator, .{
                    .uid = uid,
                    .target = slice[0..i],
                });
                if (i + 1 > slice.len)
                    return;
                slice = slice[i + 1 ..];
            } else return;

            try self.users.put(uid, .{ .uid = uid, .target = &.{}, .is_ready = is_ready });
        }
    }
}
