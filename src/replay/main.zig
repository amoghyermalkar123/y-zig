const std = @import("std");
const cl = @import("clay");
const rl = @import("raylib");
const clayrl = @import("raylib_backend.zig");
const ID = @import("./replay.zig").ID;
const Replay = @import("./replay.zig").Replay;
const InternalEventType = @import("./replay.zig").InternalEventType(ID);

const font_id_body_16: u16 = 0;

const Colors = struct {
    const Color = struct {
        r: f32,
        g: f32,
        b: f32,
        a: f32,
    };

    // Base color definitions
    const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };

    // Convert to Clay color type
    fn toClay(color: Color) cl.Color {
        return .{
            .r = color.r,
            .g = color.g,
            .b = color.b,
            .a = color.a,
        };
    }

    // Convert to Raylib color type
    fn toRaylib(color: Color) rl.Color {
        return .{
            .r = @intFromFloat(color.r),
            .g = @intFromFloat(color.g),
            .b = @intFromFloat(color.b),
            .a = @intFromFloat(color.a),
        };
    }
};

// Error handling function for Clay
fn handleClayError(error_data: cl.ErrorData(void)) void {
    std.debug.print("Clay error: {s}\n", .{error_data.error_text});
}

// Track time and squares
var elapsed_time: f32 = 0;
var num_squares: usize = 0;

pub fn update(delta_time: f32) void {
    elapsed_time += delta_time;

    // Add new square every second
    if (elapsed_time >= 1.0) {
        elapsed_time = 0;
        num_squares += 1;
    }
}

pub fn main() !void {
    // Initialize raylib window
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();
    rl.initWindow(screen_width, screen_height, "Clay Rectangle Example");
    defer rl.closeWindow();

    // Set target FPS
    rl.setTargetFPS(60);

    // Create memory arena for Clay
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Clay with minimum required memory
    const mem_size = cl.minMemorySize();
    const memory = try allocator.alloc(u8, mem_size);
    defer allocator.free(memory);

    // Create Clay arena and initialize
    const arena = cl.createArenaWithCapacityAndMemory(memory);
    cl.initialize(arena, .{ .width = @floatFromInt(screen_width), .height = @floatFromInt(screen_height) }, void, .{ .handler_function = handleClayError, .user_data = undefined });

    cl.setMeasureTextFunction(clayrl.measureText);
    clayrl.fonts = std.ArrayList(clayrl.Font).init(std.heap.c_allocator);
    defer clayrl.fonts.?.deinit();
    try clayrl.fonts.?.append(.{
        .font = rl.loadFontEx("/home/amogh/tinkers/clay-ui-tinkers/resources/Roboto-Regular.ttf", 48, null),
        .id = font_id_body_16,
    });
    rl.setTextureFilter(clayrl.fonts.?.items[font_id_body_16].font.texture, .bilinear);
    defer rl.unloadFont(clayrl.fonts.?.items[font_id_body_16].font);

    // cl.C.Clay_SetDebugModeEnabled(true);

    // Create text arena for rendering
    var text_arena = std.heap.ArenaAllocator.init(allocator);
    defer text_arena.deinit();

    var alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc.deinit();

    var internal_events_list = std.ArrayList(InternalEventType).init(alloc.allocator());
    var r = Replay.init(&internal_events_list);
    try r.parse_log(alloc.allocator(), "/home/amogh/projects/y-zig/test.log");

    // Main game loop
    while (!rl.windowShouldClose()) {
        cl.setLayoutDimensions(.{
            .width = @floatFromInt(rl.getScreenWidth()),
            .height = @floatFromInt(rl.getScreenHeight()),
        });
        // Begin drawing
        rl.beginDrawing();
        defer rl.endDrawing();

        // Clear background
        rl.clearBackground(Colors.toRaylib(Colors.white));

        // BEGIN
        const layout = cl.beginLayout();
        thing();
        // END
        var commands = layout.end();

        // Render the Clay commands using Clay's raylib backend
        clayrl.render(&commands, &text_arena);
        const delta = 1.0 / 60.0; // 60 FPS
        update(delta);
    }
}

fn render_button(text: []const u8) void {
    if (cl.child(&.{
        cl.layout(.{
            .padding = .{ .x = 16, .y = 5 },
        }),
        cl.rectangle(
            .{
                .color = .{ .r = 140, .g = 140, .b = 140, .a = 255 },
                .corner_radius = .{ .top_left = 5, .top_right = 5, .bottom_left = 5, .bottom_right = 5 },
            },
        ),
    })) |btn| {
        cl.text(
            text,
            .{
                .font_id = font_id_body_16,
                .font_size = 24,
                .text_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            },
        );
        defer btn.end();
    }
}

fn thing() void {
    const layout_expand = .{
        .width = cl.sizingGrow(.{}),
        .height = cl.sizingGrow(.{}),
    };

    const content_bg_config = .{
        .color = .{ .r = 90, .g = 90, .b = 90, .a = 255 },
        .corner_radius = .{ .top_left = 8, .top_right = 8, .bottom_left = 8, .bottom_right = 8 },
    };

    if (cl.child(&.{ cl.id("app"), cl.layout(
        .{},
    ) })) |container| {
        defer container.end();
        if (cl.child(&.{
            cl.id("outer-container"),
            cl.rectangle(.{ .color = .{ .r = 44, .g = 41, .b = 51, .a = 255 } }),
            cl.layout(.{
                .sizing = .{
                    .width = cl.sizingGrow(.{
                        .min = @floatFromInt(rl.getScreenWidth()),
                    }),
                    .height = cl.sizingGrow(.{
                        .min = @floatFromInt(rl.getScreenHeight()),
                    }),
                },
                .padding = .{ .x = 16, .y = 16 },
                .layout_direction = .top_to_bottom,
                .child_gap = 16,
            }),
        })) |sq| {
            defer sq.end();
            if (cl.child(&.{
                cl.id("header-bar"),
                cl.rectangle(content_bg_config),
                cl.layout(.{
                    .sizing = .{
                        .width = cl.sizingGrow(.{}),
                        .height = cl.sizingFixed(60),
                    },
                    .padding = .{
                        .x = 16,
                        .y = 8,
                    },
                    .child_gap = 16,
                    .child_alignment = .{
                        .y = .center,
                    },
                }),
            })) |header| {
                defer header.end();

                render_button("Play");
                render_button("Pause");
                render_button("Resume");
            }

            if (cl.child(&.{
                cl.id("lower-content"),
                cl.layout(.{
                    .sizing = layout_expand,
                    .child_gap = 16,
                }),
            })) |lowerContent| {
                defer lowerContent.end();

                // sidebar
                if (cl.child(&.{
                    cl.id("sidebar"),
                    cl.layout(.{
                        .sizing = .{ .width = cl.sizingFixed(250), .height = cl.sizingGrow(.{}) },
                    }),
                    cl.rectangle(content_bg_config),
                })) |sidebar| {
                    defer sidebar.end();
                }

                // main content
                if (cl.child(&.{
                    cl.id("main-content"),
                    cl.layout(.{
                        .sizing = layout_expand,
                    }),
                    cl.rectangle(content_bg_config),
                })) |mainContent| {
                    defer mainContent.end();
                    render_box();
                }
            }
        }
    }
}

fn render_box() void {
    // Container for squares
    if (cl.child(&.{ cl.id("squares-container"), cl.layout(.{
        .layout_direction = .left_to_right,
        .child_gap = 10,
        .padding = .{ .x = 10, .y = 10 },
    }) })) |container| {
        defer container.end();

        // Draw current number of squares
        var i: usize = 0;
        while (i < num_squares) : (i += 1) {
            if (cl.child(&.{
                cl.idi("square", @intCast(i)),
                cl.rectangle(.{
                    .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
                }),
                cl.layout(.{
                    .sizing = .{
                        .width = cl.sizingFixed(50),
                        .height = cl.sizingFixed(50),
                    },
                }),
            })) |square| {
                defer square.end();
            }
        }
    }
}

pub const Cmds = struct {};
fn readLog() void {}
fn cmds() void {}
