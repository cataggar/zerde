# Zerde Examples

Each example is a single Zig file that imports the local `zerde` module. Build all examples from the repository root:

```sh
zig build examples
```

The binaries are installed to `zig-out/bin` and can be run directly, for example:

```sh
./zig-out/bin/basic-json
./zig-out/bin/events-api
./zig-out/bin/events-csv-to-json
```

## Examples

- `basic_json.zig` / `basic-json`: reads and writes JSON with field metadata and pretty output.
- `bytes.zig` / `bytes`: demonstrates `zerde.Bytes`, `.bytes = true`, JSON base64 byte fields, and MessagePack output printed as base64.
- `codec_formats.zig` / `codec-formats`: uses `zerde.Codec(T)` to write JSON, ZON, and MessagePack, printing MessagePack as base64.
- `custom_field_hook.zig` / `custom-field-hook`: maps a Zig `bool` field to wire strings such as `"yes"` and `"no"`.
- `events_api.zig` / `events-api`: full structural events example covering event tracing, `readAlloc`, and JSON-to-MessagePack transcoding.
- `events_csv_to_json.zig` / `events-csv-to-json`: consumes CSV rows through `zerde.events.pipe` and writes JSON without an application struct.
- `metadata.zig` / `metadata`: demonstrates `rename_all`, explicit field renames, skipped fields, defaulted fields, and unknown-field denial.
- `schema_debug.zig` / `schema-debug`: prints schema output in human, JSON, TOML, and MessagePack for structs, arrays, slices, maps, enums, and tagged unions.
- `tagged_unions.zig` / `tagged-unions`: compares external, adjacent, and internal tagged union representations.
- `toml_config.zig` / `toml-config`: reads and writes a realistic TOML config with nested tables, arrays of tables, defaults, and date/time values.

## Notes

- Text formats encode raw byte fields as standard padded RFC 4648 base64.
- MessagePack is binary, so examples that print MessagePack encode it with `zerde.base64.encodeAlloc` first.
- JSON inputs are intentionally embedded in each file so examples remain self-contained.
