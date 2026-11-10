const std = @import("std");
const httpz = @import("httpz");
const App = @import("../app.zig");
const Layout = @import("../layout/layout.zig");
const Slider = @import("../block/slider.zig");

fn parceTemplate() type {
    comptime {
        @setEvalBranchQuota(100_000);
        const html: []const u8 = @embedFile("index.html");

        const block_slider = "<TPL:SLIDER />";
        const block_content = "<TPL:CONTENT />";

        var index: usize = 0;

        // Блок слайдера
        if (std.mem.find(u8, html, block_slider)) |i| {
            index = i;
        } else @compileError("Не нейдено кллючевое слово <TPL::SLIDER />");

        const _before = html[0..index];
        var html_slice: []const u8 = html[index + block_slider.len ..];

        // Блок контента
        if (std.mem.find(u8, html_slice, block_content)) |i| {
            index = i;
        } else @compileError("Не нейдено кллючевое слово <TPL::CONTENT />");

        const _after_slider = html_slice[0..index];
        const _after = html_slice[index + block_content.len ..];

        return struct {
            pub const before: [_before.len]u8 = _before.*;
            pub const after_slider: [_after_slider.len]u8 = _after_slider.*;
            pub const after: [_after.len]u8 = _after.*;
        };
    }
}
pub const Template = parceTemplate();

pub fn handle(app: *App, _: *httpz.Request, res: *httpz.Response) !void {
    const writer = res.writer();
    try writer.writeAll(Layout.Header);

    try writer.writeAll(Template.before[0..]);
    const images_ids = [_]u8{ 0, 1, 2 };
    try Slider.write(writer, images_ids[0..]);
    try writer.writeAll(Template.after_slider[0..]);
    {
        const waiting_html = @embedFile("waiting.html");
        const letsgame_html = @embedFile("letsgame.html");
        try app.lock();
        defer app.unlock();
        if (app.is_game_started) {
            try writer.writeAll(letsgame_html[0..]);
        } else try writer.print(waiting_html, .{ app.ready_count, app.users.count() });
    }
    try writer.writeAll(Template.after[0..]);

    try writer.writeAll(Layout.Footer);
}
