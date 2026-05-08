pub const Options = struct {};

pub fn optionsFor(comptime T: type) Options {
    _ = T;
    return .{};
}

pub fn validate(comptime T: type, comptime options: Options) void {
    _ = T;
    _ = options;
}
