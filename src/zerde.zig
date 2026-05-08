pub const json = @import("formats/json.zig");
pub const debug = @import("formats/debug.zig");

pub const Codec = @import("codec.zig").Codec;

pub const serialize = @import("serialize.zig").serialize;
pub const deserialize = @import("deserialize.zig").deserialize;
pub const deinit = @import("deinit.zig").deinit;

test {
    _ = json;
    _ = debug;
    _ = Codec;
    _ = serialize;
    _ = deserialize;
    _ = deinit;
    _ = @import("meta.zig");
    _ = @import("schema.zig");
    _ = @import("internal/rename.zig");
    _ = @import("internal/testing.zig");
    _ = @import("internal/traits.zig");
}
