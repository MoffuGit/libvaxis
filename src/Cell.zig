const std = @import("std");
const Image = @import("Image.zig");

const Self = @This();

const Vec3 = @Vector(3, f32);

fn u8Tof32(int: u8) f32 {
    return @as(f32, @floatFromInt(int)) / 255.0;
}

fn f32Tou8(float: f32) u8 {
    return @as(u8, @intFromFloat(std.math.round(float * 255.0)));
}

char: Character = .{},
style: Style = .{},
link: Hyperlink = .{},
image: ?Image.Placement = null,
default: bool = false,
/// Set to true if this cell is the last cell printed in a row before wrap. Vaxis will determine if
/// it should rely on the terminal's autowrap feature which can help with primary screen resizes
wrapped: bool = false,
scale: Scale = .{},

/// Segment is a contiguous run of text that has a constant style
pub const Segment = struct {
    text: []const u8,
    style: Style = .{},
    link: Hyperlink = .{},
};

pub const Character = struct {
    grapheme: []const u8 = " ",
    /// width should only be provided when the application is sure the terminal
    /// will measure the same width. This can be ensure by using the gwidth method
    /// included in libvaxis. If width is 0, libvaxis will measure the glyph at
    /// render time
    width: u8 = 1,
};

pub const CursorShape = enum {
    default,
    block_blink,
    block,
    underline_blink,
    underline,
    beam_blink,
    beam,
};

pub const Hyperlink = struct {
    uri: []const u8 = "",
    /// ie "id=app-1234"
    params: []const u8 = "",
};

pub const Scale = packed struct {
    scale: u3 = 1,
    // The spec allows up to 15, but we limit to 7
    numerator: u4 = 1,
    // The spec allows up to 15, but we limit to 7
    denominator: u4 = 1,
    vertical_alignment: enum(u2) {
        top = 0,
        bottom = 1,
        center = 2,
    } = .top,

    pub fn eql(self: Scale, other: Scale) bool {
        const a_scale: u13 = @bitCast(self);
        const b_scale: u13 = @bitCast(other);
        return a_scale == b_scale;
    }
};

pub const Style = struct {
    pub const Underline = enum {
        off,
        single,
        double,
        curly,
        dotted,
        dashed,
    };

    fg: Color = .default,
    bg: Color = .default,
    ul: Color = .default,
    ul_style: Underline = .off,

    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    blink: bool = false,
    reverse: bool = false,
    invisible: bool = false,
    strikethrough: bool = false,

    pub fn eql(a: Style, b: Style) bool {
        const SGRBits = packed struct {
            bold: bool,
            dim: bool,
            italic: bool,
            blink: bool,
            reverse: bool,
            invisible: bool,
            strikethrough: bool,
        };
        const a_sgr: SGRBits = .{
            .bold = a.bold,
            .dim = a.dim,
            .italic = a.italic,
            .blink = a.blink,
            .reverse = a.reverse,
            .invisible = a.invisible,
            .strikethrough = a.strikethrough,
        };
        const b_sgr: SGRBits = .{
            .bold = b.bold,
            .dim = b.dim,
            .italic = b.italic,
            .blink = b.blink,
            .reverse = b.reverse,
            .invisible = b.invisible,
            .strikethrough = b.strikethrough,
        };
        return a_sgr == b_sgr and
            Color.eql(a.fg, b.fg) and
            Color.eql(a.bg, b.bg) and
            Color.eql(a.ul, b.ul) and
            a.ul_style == b.ul_style;
    }

    pub fn canBlend(self: Style) bool {
        return self.bg.isRgb() or self.fg.isRgb() or self.ul.isRgb();
    }

    pub fn isOpaque(self: Style) bool {
        return self.bg.isOpaque() and self.fg.isOpaque() and self.ul.isOpaque();
    }

    pub fn isTransparent(self: Style) bool {
        return self.bg.isTransparent() and self.fg.isTransparent() and self.ul.isTransparent();
    }
};

pub const Color = union(enum) {
    default,
    index: u8,
    rgb: [3]u8,
    rgba: [4]u8,

    pub const Kind = union(enum) {
        fg,
        bg,
        cursor,
        index: u8,
    };

    /// Returned when querying a color from the terminal
    pub const Report = struct {
        kind: Kind,
        value: [3]u8,
    };

    pub const Scheme = enum {
        dark,
        light,
    };

    pub fn eql(a: Color, b: Color) bool {
        switch (a) {
            .default => return b == .default,
            .index => |a_idx| {
                switch (b) {
                    .index => |b_idx| return a_idx == b_idx,
                    else => return false,
                }
            },
            .rgb => |a_rgb| {
                switch (b) {
                    .rgb => |b_rgb| return a_rgb[0] == b_rgb[0] and
                        a_rgb[1] == b_rgb[1] and
                        a_rgb[2] == b_rgb[2],
                    else => return false,
                }
            },
            .rgba => |a_rgb| {
                switch (b) {
                    .rgba => |b_rgb| return a_rgb[0] == b_rgb[0] and
                        a_rgb[1] == b_rgb[1] and
                        a_rgb[2] == b_rgb[2] and a_rgb[3] == b_rgb[3],
                    else => return false,
                }
            },
        }
    }

    pub fn alpha(self: Color) f32 {
        switch (self) {
            .default, .index, .rgb => return 1.0,
            .rgba => |rgba| {
                return u8Tof32(rgba[3]);
            },
        }
    }

    pub fn isOpaque(self: Color) bool {
        return self.alpha() == 1.0;
    }

    pub fn isTransparent(self: Color) bool {
        return self.alpha() == 0.0;
    }

    pub fn isRgb(self: Color) bool {
        switch (self) {
            .rgb, .rgba => return true,
            else => return false,
        }
    }

    pub fn getVec3(self: Color) Vec3 {
        switch (self) {
            .rgb => |rgb| return Vec3{ u8Tof32(rgb[0]), u8Tof32(rgb[1]), u8Tof32(rgb[2]) },
            .rgba => |rgba| return Vec3{ u8Tof32(rgba[0]), u8Tof32(rgba[1]), u8Tof32(rgba[2]) },
            else => return Vec3{ 0.0, 0.0, 0.0 },
        }
    }

    pub fn blend(self: Color, other: Color) Color {
        if (self.isOpaque() or !other.isRgb()) {
            return self;
        }

        if (self.isTransparent()) {
            return other;
        }

        const a = self.alpha();

        var perceptualAlpha: f32 = undefined;
        if (a > 0.8) {
            const normalizedHighAlpha = (a - 0.8) * 5.0;
            const curvedHighAlpha = std.math.pow(f32, normalizedHighAlpha, 0.2);
            perceptualAlpha = 0.8 + (curvedHighAlpha * 0.2);
        } else {
            perceptualAlpha = std.math.pow(f32, a, 0.9);
        }

        const vec3_s = self.getVec3();
        const vec3_o = other.getVec3();

        const alphaSplat = @as(Vec3, @splat(perceptualAlpha));
        const oneMinusAlpha = @as(Vec3, @splat(1.0 - perceptualAlpha));
        const blended = vec3_s * alphaSplat + vec3_o * oneMinusAlpha;

        return .{ .rgba = .{ f32Tou8(blended[0]), f32Tou8(blended[1]), f32Tou8(blended[2]), f32Tou8(other.alpha()) } };
    }

    pub fn rgbFromUint(val: u24) Color {
        const r_bits = val & 0b11111111_00000000_00000000;
        const g_bits = val & 0b00000000_11111111_00000000;
        const b_bits = val & 0b00000000_00000000_11111111;
        const rgb = [_]u8{
            @truncate(r_bits >> 16),
            @truncate(g_bits >> 8),
            @truncate(b_bits),
        };
        return .{ .rgb = rgb };
    }

    /// parse an XParseColor-style rgb specification into an rgb Color. The spec
    /// is of the form: rgb:rrrr/gggg/bbbb. Generally, the high two bits will always
    /// be the same as the low two bits.
    pub fn rgbFromSpec(spec: []const u8) !Color {
        var iter = std.mem.splitScalar(u8, spec, ':');
        const prefix = iter.next() orelse return error.InvalidColorSpec;
        if (!std.mem.eql(u8, "rgb", prefix)) return error.InvalidColorSpec;

        const spec_str = iter.next() orelse return error.InvalidColorSpec;

        var spec_iter = std.mem.splitScalar(u8, spec_str, '/');

        const r_raw = spec_iter.next() orelse return error.InvalidColorSpec;
        if (r_raw.len != 4) return error.InvalidColorSpec;

        const g_raw = spec_iter.next() orelse return error.InvalidColorSpec;
        if (g_raw.len != 4) return error.InvalidColorSpec;

        const b_raw = spec_iter.next() orelse return error.InvalidColorSpec;
        if (b_raw.len != 4) return error.InvalidColorSpec;

        const r = try std.fmt.parseUnsigned(u8, r_raw[2..], 16);
        const g = try std.fmt.parseUnsigned(u8, g_raw[2..], 16);
        const b = try std.fmt.parseUnsigned(u8, b_raw[2..], 16);

        return .{
            .rgb = [_]u8{ r, g, b },
        };
    }

    test "rgbFromSpec" {
        const spec = "rgb:aaaa/bbbb/cccc";
        const actual = try rgbFromSpec(spec);
        switch (actual) {
            .rgb => |rgb| {
                try std.testing.expectEqual(0xAA, rgb[0]);
                try std.testing.expectEqual(0xBB, rgb[1]);
                try std.testing.expectEqual(0xCC, rgb[2]);
            },
            else => try std.testing.expect(false),
        }
    }
};

pub fn blend(self: Self, other: Self) Self {
    if (!other.style.canBlend() or self.style.isOpaque()) {
        return self;
    }

    if (self.style.isTransparent() or self.style.invisible) {
        return other;
    }

    const preserve = std.mem.eql(u8, self.char.grapheme, " ") or self.style.fg.isTransparent();

    var cell = if (preserve) other else self;
    cell.style.bg = self.style.bg.blend(other.style.bg);
    cell.style.fg = if (preserve) self.style.bg.blend(other.style.fg) else self.style.fg.blend(other.style.bg);
    cell.style.ul = if (preserve) self.style.bg.blend(other.style.ul) else self.style.ul.blend(other.style.bg);

    cell.link = self.link;

    return cell;
}
