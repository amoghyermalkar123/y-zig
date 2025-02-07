const clay = @import("clay");
const raylib = @import("raylib");
const std = @import("std");

/// Font wrapper for raylib renderer.
pub const Font = struct {
    /// Font ID for clay.
    id: u32,
    /// Raylib font information.
    font: raylib.Font,
};

/// Global font list.
pub var fonts: ?std.ArrayList(Font) = null;

/// Convert a clay color to a raylib one.
/// * `color` - Color to convert to a raylib one.
pub fn clayColorToRaylib(color: clay.Color) raylib.Color {
    return .{
        .r = @intFromFloat(color.r),
        .g = @intFromFloat(color.g),
        .b = @intFromFloat(color.b),
        .a = @intFromFloat(color.a),
    };
}

/// Callback for clay to get the dimensions of text data.
/// * `text` - Input text to measure.
/// * `config` - Configuration properties of the input text.
pub fn measureText(text: []const u8, config: clay.TextElementConfig) clay.Dimensions {
    if (fonts == null) {
        std.debug.print("Global font list has not been initialized.\n", .{});
        return .{};
    }
    if (config.font_id >= fonts.?.items.len) {
        std.debug.print("Font ID {d} is invalid.\n", .{config.font_id});
        return .{};
    }

    var text_size = clay.Dimensions{ .width = 0, .height = 0 };

    var max_text_width: f32 = 0;
    var line_text_width: f32 = 0;

    const text_height = config.font_size;
    const font = fonts.?.items[config.font_id].font;
    const scale_factor = @as(f32, @floatFromInt(config.font_size)) / @as(f32, @floatFromInt(font.baseSize));

    for (0..text.len) |ind| {
        if (text[ind] == '\n') {
            max_text_width = @max(max_text_width, line_text_width);
            line_text_width = 0;
            continue;
        }
        const index = text[ind] - 32;
        if (font.glyphs[index].advanceX != 0) {
            line_text_width += @floatFromInt(font.glyphs[index].advanceX);
        } else {
            line_text_width += font.recs[index].width + @as(f32, @floatFromInt(font.glyphs[index].offsetX));
        }
    }

    max_text_width = @max(max_text_width, line_text_width);

    text_size.width = max_text_width * scale_factor;
    text_size.height = @floatFromInt(text_height);

    return text_size;
}

/// Initialize the clay-raylib renderer with the given configuration flags and window info.
/// * `width` - Initial window width.
/// * `height` - Initial window height.
/// * `title` - Initial window title.
/// * `config_flags` - Configuration flags for the window.
pub fn initialize(width: i32, height: i32, title: [*:0]const u8, config_flags: raylib.ConfigFlags) void {
    raylib.setConfigFlags(config_flags);
    raylib.initWindow(width, height, title);
}

/// Handle rendering a clay command list.
/// * `commands` - Render commands provided from `.end()` for a `Layout`.
/// * `text_arena` - Arena to allocate text from.
pub fn render(commands: *clay.RenderCommandArray, text_arena: *std.heap.ArenaAllocator) void {
    var iter = commands.iter();
    while (iter.next()) |command| {
        switch (command.config) {
            .none => {},
            .text => |text| {
                const allocator = text_arena.allocator();
                const cloned = allocator.allocSentinel(u8, command.text.?.len, 0) catch unreachable;
                defer _ = text_arena.reset(.retain_capacity);
                std.mem.copyForwards(u8, cloned, command.text.?);
                const font = fonts.?.items[text.font_id].font;
                raylib.drawTextEx(
                    font,
                    cloned,
                    .{ .x = command.bounding_box.x, .y = command.bounding_box.y },
                    @floatFromInt(text.font_size),
                    @floatFromInt(text.letter_spacing),
                    clayColorToRaylib(text.text_color),
                );
            },
            .image => |image| {
                const image_texture = @as(*raylib.Texture2D, @ptrCast(@alignCast(image.image_data))).*;
                raylib.drawTextureEx(
                    image_texture,
                    .{ .x = command.bounding_box.x, .y = command.bounding_box.y },
                    0,
                    command.bounding_box.width / @as(f32, @floatFromInt(image_texture.width)),
                    raylib.Color.white,
                );
            },
            .scissor_start => {
                raylib.beginScissorMode(
                    @intFromFloat(@round(command.bounding_box.x)),
                    @intFromFloat(@round(command.bounding_box.y)),
                    @intFromFloat(@round(command.bounding_box.width)),
                    @intFromFloat(@round(command.bounding_box.height)),
                );
            },
            .scissor_end => {
                raylib.endScissorMode();
            },
            .rectangle => |rect| {
                if (rect.corner_radius.top_left > 0) {
                    const radius = rect.corner_radius.top_left * 2 / (if (command.bounding_box.width > command.bounding_box.height) command.bounding_box.height else command.bounding_box.width);
                    raylib.drawRectangleRounded(
                        .{
                            .x = command.bounding_box.x,
                            .y = command.bounding_box.y,
                            .width = command.bounding_box.width,
                            .height = command.bounding_box.height,
                        },
                        radius,
                        8,
                        clayColorToRaylib(rect.color),
                    );
                } else {
                    raylib.drawRectangle(
                        @intFromFloat(command.bounding_box.x),
                        @intFromFloat(command.bounding_box.y),
                        @intFromFloat(command.bounding_box.width),
                        @intFromFloat(command.bounding_box.height),
                        clayColorToRaylib(rect.color),
                    );
                }
            },
            .border => |border| {

                // Left border.
                if (border.left.width > 0) {
                    raylib.drawRectangle(
                        @intFromFloat(@round(command.bounding_box.x)),
                        @intFromFloat(@round(command.bounding_box.y + border.corner_radius.top_left)),
                        @intCast(border.left.width),
                        @intFromFloat(@round(command.bounding_box.height - border.corner_radius.top_left - border.corner_radius.bottom_left)),
                        clayColorToRaylib(border.left.color),
                    );
                }

                // Right border.
                if (border.right.width > 0) {
                    raylib.drawRectangle(
                        @as(i32, @intFromFloat(@round(command.bounding_box.x + command.bounding_box.width))) - @as(i32, @intCast(border.right.width)),
                        @intFromFloat(@round(command.bounding_box.y + border.corner_radius.top_right)),
                        @intCast(border.right.width),
                        @intFromFloat(@round(command.bounding_box.height - border.corner_radius.top_right - border.corner_radius.bottom_right)),
                        clayColorToRaylib(border.right.color),
                    );
                }

                // Top border.
                if (border.top.width > 0) {
                    raylib.drawRectangle(
                        @intFromFloat(@round(command.bounding_box.x + border.corner_radius.top_left)),
                        @intFromFloat(@round(command.bounding_box.y)),
                        @intFromFloat(@round(command.bounding_box.width - border.corner_radius.top_left - border.corner_radius.top_right)),
                        @intCast(border.top.width),
                        clayColorToRaylib(border.top.color),
                    );
                }

                // Bottom border.
                if (border.bottom.width > 0) {
                    raylib.drawRectangle(
                        @intFromFloat(@round(command.bounding_box.x + border.corner_radius.bottom_left)),
                        @as(i32, @intFromFloat(@round(command.bounding_box.y + command.bounding_box.height))) - @as(i32, @intCast(border.bottom.width)),
                        @intFromFloat(@round(command.bounding_box.width - border.corner_radius.bottom_left - border.corner_radius.bottom_right)),
                        @intCast(border.bottom.width),
                        clayColorToRaylib(border.bottom.color),
                    );
                }

                // Rings.
                if (border.corner_radius.top_left > 0) {
                    raylib.drawRing(
                        .{
                            .x = @round(command.bounding_box.x + border.corner_radius.top_left),
                            .y = @round(command.bounding_box.y + border.corner_radius.top_left),
                        },
                        @round(border.corner_radius.top_left) - @as(f32, @floatFromInt(border.top.width)),
                        border.corner_radius.top_left,
                        180,
                        270,
                        10,
                        clayColorToRaylib(border.top.color),
                    );
                }
                if (border.corner_radius.top_right > 0) {
                    raylib.drawRing(
                        .{
                            .x = @round(command.bounding_box.x + command.bounding_box.width - border.corner_radius.top_right),
                            .y = @round(command.bounding_box.y + border.corner_radius.top_right),
                        },
                        @round(border.corner_radius.top_right) - @as(f32, @floatFromInt(border.top.width)),
                        border.corner_radius.top_right,
                        270,
                        360,
                        10,
                        clayColorToRaylib(border.top.color),
                    );
                }
                if (border.corner_radius.bottom_left > 0) {
                    raylib.drawRing(
                        .{
                            .x = @round(command.bounding_box.x + border.corner_radius.bottom_left),
                            .y = @round(command.bounding_box.y + command.bounding_box.height - border.corner_radius.bottom_left),
                        },
                        @round(border.corner_radius.bottom_left) - @as(f32, @floatFromInt(border.top.width)),
                        border.corner_radius.bottom_left,
                        90,
                        180,
                        10,
                        clayColorToRaylib(border.bottom.color),
                    );
                }
                if (border.corner_radius.bottom_right > 0) {
                    raylib.drawRing(
                        .{
                            .x = @round(command.bounding_box.x + command.bounding_box.width - border.corner_radius.bottom_right),
                            .y = @round(command.bounding_box.y + command.bounding_box.height - border.corner_radius.bottom_right),
                        },
                        @round(border.corner_radius.bottom_right) - @as(f32, @floatFromInt(border.bottom.width)),
                        border.corner_radius.bottom_right,
                        0.1,
                        90,
                        10,
                        clayColorToRaylib(border.bottom.color),
                    );
                }
            },
            .custom => {
                std.debug.print("Unsupported render command \"Custom\"\n", .{});
            },
        }
    }
}
