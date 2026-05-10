const std = @import("std");
const zerde = @import("zerde");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const input =
        \\id,name,note
        \\1,Ada,
        \\2,Bob,ok
        \\3,Steve,ok
    ;

    var reader: std.Io.Reader = .fixed(input);
    var csv_decoder = try zerde.csv.decoder(&reader, allocator, .{});
    defer csv_decoder.deinit();

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var json_encoder = zerde.json.encoderWithOptions(&out.writer, .{ .pretty = true, .indent = 2 });

    try zerde.events.pipe(allocator, &csv_decoder, &json_encoder);
    try csv_decoder.finish();
    try json_encoder.finish();

    std.debug.print("csv:\n{s}\n\njson:\n{s}\n", .{ input, out.writer.buffered() });
}
