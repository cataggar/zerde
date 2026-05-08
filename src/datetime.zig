//! First-class TOML date and time value types.

const std = @import("std");

/// TOML local date: `YYYY-MM-DD`.
pub const LocalDate = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn parse(input: []const u8) !LocalDate {
        var parser = DateTimeParser{ .input = input };
        const value = try parser.parseDate();
        if (!parser.eof()) return error.InvalidTomlDateTime;
        return value;
    }

    pub fn format(self: LocalDate, writer: *std.Io.Writer) !void {
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }

    pub fn zerdeSerialize(self: LocalDate, enc: anytype) !void {
        var buffer: [16]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try self.format(&writer);
        try emitDateTimeOrString(enc, writer.buffered());
    }

    pub fn zerdeDeserialize(allocator: std.mem.Allocator, dec: anytype) !LocalDate {
        const bytes = try readDateTimeOrString(allocator, dec);
        defer allocator.free(bytes);
        return try parse(bytes);
    }
};

/// TOML local time: `HH:MM:SS[.fraction]`.
pub const LocalTime = struct {
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32 = 0,

    pub fn parse(input: []const u8) !LocalTime {
        var parser = DateTimeParser{ .input = input };
        const value = try parser.parseTime();
        if (!parser.eof()) return error.InvalidTomlDateTime;
        return value;
    }

    pub fn format(self: LocalTime, writer: *std.Io.Writer) !void {
        try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ self.hour, self.minute, self.second });
        try formatFraction(writer, self.nanosecond);
    }

    pub fn zerdeSerialize(self: LocalTime, enc: anytype) !void {
        var buffer: [32]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try self.format(&writer);
        try emitDateTimeOrString(enc, writer.buffered());
    }

    pub fn zerdeDeserialize(allocator: std.mem.Allocator, dec: anytype) !LocalTime {
        const bytes = try readDateTimeOrString(allocator, dec);
        defer allocator.free(bytes);
        return try parse(bytes);
    }
};

/// TOML local date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]`.
pub const LocalDateTime = struct {
    date: LocalDate,
    time: LocalTime,

    pub fn parse(input: []const u8) !LocalDateTime {
        var parser = DateTimeParser{ .input = input };
        const value = try parser.parseLocalDateTime();
        if (!parser.eof()) return error.InvalidTomlDateTime;
        return value;
    }

    pub fn format(self: LocalDateTime, writer: *std.Io.Writer) !void {
        try self.date.format(writer);
        try writer.writeByte('T');
        try self.time.format(writer);
    }

    pub fn zerdeSerialize(self: LocalDateTime, enc: anytype) !void {
        var buffer: [48]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try self.format(&writer);
        try emitDateTimeOrString(enc, writer.buffered());
    }

    pub fn zerdeDeserialize(allocator: std.mem.Allocator, dec: anytype) !LocalDateTime {
        const bytes = try readDateTimeOrString(allocator, dec);
        defer allocator.free(bytes);
        return try parse(bytes);
    }
};

/// TOML offset date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]Z` or with `+/-HH:MM`.
pub const OffsetDateTime = struct {
    date: LocalDate,
    time: LocalTime,
    offset_minutes: i16,

    pub fn parse(input: []const u8) !OffsetDateTime {
        var parser = DateTimeParser{ .input = input };
        const value = try parser.parseOffsetDateTime();
        if (!parser.eof()) return error.InvalidTomlDateTime;
        return value;
    }

    pub fn format(self: OffsetDateTime, writer: *std.Io.Writer) !void {
        try self.date.format(writer);
        try writer.writeByte('T');
        try self.time.format(writer);
        if (self.offset_minutes == 0) {
            try writer.writeByte('Z');
            return;
        }

        const sign: u8 = if (self.offset_minutes < 0) '-' else '+';
        const abs_minutes: u16 = @intCast(if (self.offset_minutes < 0) -self.offset_minutes else self.offset_minutes);
        try writer.print("{c}{d:0>2}:{d:0>2}", .{ sign, abs_minutes / 60, abs_minutes % 60 });
    }

    pub fn zerdeSerialize(self: OffsetDateTime, enc: anytype) !void {
        var buffer: [56]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try self.format(&writer);
        try emitDateTimeOrString(enc, writer.buffered());
    }

    pub fn zerdeDeserialize(allocator: std.mem.Allocator, dec: anytype) !OffsetDateTime {
        const bytes = try readDateTimeOrString(allocator, dec);
        defer allocator.free(bytes);
        return try parse(bytes);
    }
};

fn emitDateTimeOrString(enc: anytype, value: []const u8) !void {
    if (comptime hasTomlDateTimeEmitter(@TypeOf(enc))) {
        try enc.emitTomlDateTime(value);
    } else {
        try enc.emitString(value);
    }
}

fn readDateTimeOrString(allocator: std.mem.Allocator, dec: anytype) ![]u8 {
    if (comptime hasTomlDateTimeReader(@TypeOf(dec))) {
        return try dec.readTomlDateTime(allocator);
    }
    return try dec.readString(allocator);
}

fn hasTomlDateTimeEmitter(comptime T: type) bool {
    const Target = switch (@typeInfo(T)) {
        .pointer => |pointer| pointer.child,
        else => T,
    };
    return @hasDecl(Target, "emitTomlDateTime");
}

fn hasTomlDateTimeReader(comptime T: type) bool {
    const Target = switch (@typeInfo(T)) {
        .pointer => |pointer| pointer.child,
        else => T,
    };
    return @hasDecl(Target, "readTomlDateTime");
}

fn formatFraction(writer: *std.Io.Writer, nanosecond: u32) !void {
    if (nanosecond == 0) return;
    var buffer: [9]u8 = undefined;
    var fixed: std.Io.Writer = .fixed(&buffer);
    try fixed.print("{d:0>9}", .{nanosecond});
    var len: usize = fixed.buffered().len;
    while (len != 0 and fixed.buffered()[len - 1] == '0') len -= 1;
    try writer.writeByte('.');
    try writer.writeAll(fixed.buffered()[0..len]);
}

const DateTimeParser = struct {
    input: []const u8,
    index: usize = 0,

    fn parseOffsetDateTime(self: *DateTimeParser) !OffsetDateTime {
        const date = try self.parseDate();
        try self.expectDateTimeSeparator();
        const time = try self.parseTime();
        const offset = try self.parseOffset();
        return .{ .date = date, .time = time, .offset_minutes = offset };
    }

    fn parseLocalDateTime(self: *DateTimeParser) !LocalDateTime {
        const date = try self.parseDate();
        try self.expectDateTimeSeparator();
        const time = try self.parseTime();
        return .{ .date = date, .time = time };
    }

    fn parseDate(self: *DateTimeParser) !LocalDate {
        const year = try self.takeDigits(4);
        try self.expectByte('-');
        const month = try self.takeDigits(2);
        try self.expectByte('-');
        const day = try self.takeDigits(2);
        if (!validDate(year, month, day)) return error.InvalidTomlDateTime;
        return .{ .year = @intCast(year), .month = @intCast(month), .day = @intCast(day) };
    }

    fn parseTime(self: *DateTimeParser) !LocalTime {
        const hour = try self.takeDigits(2);
        try self.expectByte(':');
        const minute = try self.takeDigits(2);
        try self.expectByte(':');
        const second = try self.takeDigits(2);
        if (hour > 23 or minute > 59 or second > 59) return error.InvalidTomlDateTime;

        var nanosecond: u32 = 0;
        if (!self.eof() and self.input[self.index] == '.') {
            self.index += 1;
            var digits: usize = 0;
            while (!self.eof() and std.ascii.isDigit(self.input[self.index])) {
                if (digits == 9) return error.InvalidTomlDateTime;
                nanosecond = nanosecond * 10 + (self.input[self.index] - '0');
                digits += 1;
                self.index += 1;
            }
            if (digits == 0) return error.InvalidTomlDateTime;
            while (digits < 9) : (digits += 1) nanosecond *= 10;
        }

        return .{ .hour = @intCast(hour), .minute = @intCast(minute), .second = @intCast(second), .nanosecond = nanosecond };
    }

    fn parseOffset(self: *DateTimeParser) !i16 {
        if (self.eof()) return error.InvalidTomlDateTime;
        const first = self.input[self.index];
        if (first == 'Z' or first == 'z') {
            self.index += 1;
            return 0;
        }
        if (first != '+' and first != '-') return error.InvalidTomlDateTime;
        self.index += 1;
        const hours = try self.takeDigits(2);
        try self.expectByte(':');
        const minutes = try self.takeDigits(2);
        if (hours > 23 or minutes > 59) return error.InvalidTomlDateTime;
        const total: i16 = @intCast(hours * 60 + minutes);
        return if (first == '-') -total else total;
    }

    fn expectDateTimeSeparator(self: *DateTimeParser) !void {
        if (self.eof()) return error.InvalidTomlDateTime;
        switch (self.input[self.index]) {
            'T', 't', ' ' => self.index += 1,
            else => return error.InvalidTomlDateTime,
        }
    }

    fn takeDigits(self: *DateTimeParser, count: usize) !u16 {
        if (self.index + count > self.input.len) return error.InvalidTomlDateTime;
        var value: u16 = 0;
        for (0..count) |_| {
            const byte = self.input[self.index];
            if (!std.ascii.isDigit(byte)) return error.InvalidTomlDateTime;
            value = value * 10 + (byte - '0');
            self.index += 1;
        }
        return value;
    }

    fn expectByte(self: *DateTimeParser, expected: u8) !void {
        if (self.eof() or self.input[self.index] != expected) return error.InvalidTomlDateTime;
        self.index += 1;
    }

    fn eof(self: *DateTimeParser) bool {
        return self.index >= self.input.len;
    }
};

fn validDate(year: u16, month: u16, day: u16) bool {
    if (month < 1 or month > 12) return false;
    const max_day: u16 = switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => unreachable,
    };
    return day >= 1 and day <= max_day;
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
}
