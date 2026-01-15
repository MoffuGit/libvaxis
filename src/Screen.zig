const std = @import("std");
const assert = std.debug.assert;

const Cell = @import("Cell.zig");
const Mouse = @import("Mouse.zig");
const Shape = @import("Mouse.zig").Shape;
const Image = @import("Image.zig");
const Window = @import("Window.zig");
const Winsize = @import("main.zig").Winsize;
const Method = @import("gwidth.zig").Method;
const Buffer = @import("Buffer.zig");

const Screen = @This();

width: u16 = 0,
height: u16 = 0,

width_pix: u16 = 0,
height_pix: u16 = 0,

buf: []Cell = &.{},

cursor_row: u16 = 0,
cursor_col: u16 = 0,
cursor_vis: bool = false,

width_method: Method = .wcwidth,

mouse_shape: Shape = .default,
cursor_shape: Cell.CursorShape = .default,

pub fn init(alloc: std.mem.Allocator, winsize: Winsize) std.mem.Allocator.Error!Screen {
    const w = winsize.cols;
    const h = winsize.rows;
    const self = Screen{
        .buf = try alloc.alloc(Cell, @as(usize, @intCast(w)) * h),
        .width = w,
        .height = h,
        .width_pix = winsize.x_pixel,
        .height_pix = winsize.y_pixel,
    };
    const base_cell: Cell = .{};
    @memset(self.buf, base_cell);
    return self;
}

pub fn deinit(self: *Screen, alloc: std.mem.Allocator) void {
    alloc.free(self.buf);
}

pub fn setCell(self: *Screen, col: u16, row: u16, cell: Cell) void {
    if (col >= self.width or
        row >= self.height)
        return;
    const i = (@as(usize, @intCast(row)) * self.width) + col;
    assert(i < self.buf.len);
    self.buf[i] = cell;
}

pub fn writeCell(self: *Screen, col: u16, row: u16, cell: Cell) void {
    if (self.readCell(col, row)) |other| {
        self.setCell(col, row, cell.blend(other));
    } else {
        self.setCell(col, row, cell);
    }
}

pub fn readCell(self: *const Screen, col: u16, row: u16) ?Cell {
    if (col >= self.width or
        row >= self.height)
        return null;
    const i = (@as(usize, @intCast(row)) * self.width) + col;
    assert(i < self.buf.len);
    return self.buf[i];
}

pub fn clear(self: *Screen) void {
    @memset(self.buf, .{});
}

/// set the mouse shape
pub fn setMouseShape(self: *Screen, shape: Shape) void {
    self.mouse_shape = shape;
}

/// Translate pixel mouse coordinates to cell + offset
pub fn translateMouse(self: *Screen, mouse: Mouse) Mouse {
    if (self.width == 0 or self.height == 0) return mouse;
    var result = mouse;
    std.debug.assert(mouse.xoffset == 0);
    std.debug.assert(mouse.yoffset == 0);
    const xpos = mouse.col;
    const ypos = mouse.row;
    const xextra = self.width_pix % self.width;
    const yextra = self.height_pix % self.height;
    const xcell: i16 = @intCast((self.width_pix - xextra) / self.width);
    const ycell: i16 = @intCast((self.height_pix - yextra) / self.height);
    if (xcell == 0 or ycell == 0) return mouse;
    result.col = @divFloor(xpos, xcell);
    result.row = @divFloor(ypos, ycell);
    result.xoffset = @intCast(@mod(xpos, xcell));
    result.yoffset = @intCast(@mod(ypos, ycell));
    return result;
}

/// returns a Window comprising of the entire terminal screen
pub fn window(self: *Screen) Window {
    return .{
        .x_off = 0,
        .y_off = 0,
        .parent_x_off = 0,
        .parent_y_off = 0,
        .width = self.width,
        .height = self.height,
        .screen = self,
    };
}

pub fn buffer(self: *Screen) Buffer {
    return .{
        .buf = self.buf,
        .height = self.height,
        .width = self.width,
    };
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
