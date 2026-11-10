const std = @import("std");

fn parceTemplate() type {
    comptime {
        @setEvalBranchQuota(100_000);
        const html: []const u8 = @embedFile("slider.html");

        const block_start = "<TPL:IMAGE>";
        const block_end = "</TPL:IMAGE>";

        var index: usize = 0;

        // Начало блока
        if (std.mem.find(u8, html, block_start)) |i| {
            index = i;
        } else @compileError("Не найдено начало блока slider");

        const _before = html[0..index];
        var html_slice: []const u8 = html[index + block_start.len ..];

        // Конец блока
        if (std.mem.find(u8, html_slice, block_end)) |i| {
            index = i;
        } else @compileError("Не найден конец блока slider");

        const _element = html_slice[0..index];
        const _after = html_slice[index + block_end.len ..];

        return struct {
            pub const before: [_before.len]u8 = _before.*;
            pub const element: [_element.len]u8 = _element.*;
            pub const after: [_after.len]u8 = _after.*;
            pub const len: usize = _before.len + _after.len;
            pub const len_el: usize = _element.len;
        };
    }
}
pub const Template = parceTemplate();
pub fn length(elements_length: usize) usize {
    return Template.len + Template.len_el * elements_length;
}
pub fn write(writer: *std.Io.Writer, image_ids: []const u8) !void {
    if (Template.before.len > 0)
        try writer.writeAll(Template.before[0..]);
    for (image_ids) |image_id| {
        try writer.print(Template.element[0..], .{ image_id, image_id, image_id });
    }
    if (Template.after.len > 0)
        try writer.writeAll(Template.after[0..]);
}
