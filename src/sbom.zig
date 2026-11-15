const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

pub const Error = error{
    DependenciesTooMany,
    ManifestInvalid,
    ManifestTooLarge,
    OutOfMemory,
    Usage,
} || std.Io.Dir.ReadFileError || std.Io.Dir.WriteFileError || std.Io.Writer.Error;

pub const Dependency = struct {
    hash: ?[]const u8,
    lazy: bool,
    name: []const u8,
    path: ?[]const u8,
    url: ?[]const u8,
};

pub const Dependencies = struct {
    items: [dependency_count_max]Dependency,
    count: u32,

    pub const empty: Dependencies = .{ .items = undefined, .count = 0 };

    pub fn slice(dependencies: *const Dependencies) []const Dependency {
        assert(dependencies.count <= dependency_count_max);
        assert(dependencies.items.len == dependency_count_max);

        return dependencies.items[0..dependencies.count];
    }
};

pub const Component = struct {
    children: []const u32,
    dependency: Dependency,
    key: []const u8,
    reference: []const u8,
    resolved: bool,
    version: ?[]const u8,
};

pub const Graph = struct {
    components: [dependency_count_max]Component,
    count: u32,
    direct: []const u32,
    manifests: [dependency_count_max + 1][]const u8,
    manifest_count: u32,

    pub const empty: Graph = .{
        .components = undefined,
        .count = 0,
        .direct = &.{},
        .manifests = undefined,
        .manifest_count = 0,
    };

    pub fn slice(graph: *const Graph) []const Component {
        assert(graph.count <= dependency_count_max);
        assert(graph.direct.len <= graph.count);

        return graph.components[0..graph.count];
    }
};

pub const Location = struct {
    cache_root: []const u8,
    manifest: []const u8,
};

const Manifest = union(enum) {
    absent,
    present: ManifestFile,
};

const ManifestFile = struct {
    path: []const u8,
    text: [:0]const u8,
};

pub const Parsed = struct {
    dependencies: Dependencies,
    version: ?[]const u8,

    pub const empty: Parsed = .{ .dependencies = .empty, .version = null };
};

pub const Subject = struct {
    distribution: []const u8,
    version: []const u8,
};

pub const dependency_count_max: u32 = 256;
pub const manifest_bytes_max: u32 = 1 << 20;

const Pending = struct {
    base: []const u8,
    dependency: Dependency,
    origin: []const u8,
    parent: ?u32,
};

const Collection = struct {
    arena: std.mem.Allocator,
    buffer: []u8,
    graph: *Graph,
    io: std.Io,
    location: Location,
    queue: *[dependency_count_max]Pending,
    tail: u32,
};

const Extension = struct {
    base: []const u8,
    dependencies: []const Dependency,
    origin: []const u8,
    parent: ?u32,
};

const Owner = union(enum) {
    component: u32,
    subject: []const u8,
};

const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .default_file,
    .resolve_beneath = false,
};

pub fn main(init: std.process.Init) Error!void {
    assert(init.minimal.args.vector.len > 0);
    assert(manifest_bytes_max > 0);

    const arena = init.arena.allocator();
    const arguments = init.minimal.args.toSlice(arena) catch return error.Usage;
    if (arguments.len != 7) return error.Usage;

    const subject: Subject = .{ .distribution = arguments[3], .version = arguments[4] };
    if (!text_plain(subject.distribution)) return error.Usage;
    if (!text_plain(subject.version)) return error.Usage;

    const location: Location = .{ .cache_root = arguments[5], .manifest = arguments[2] };

    var graph: Graph = .empty;

    try graph_collect(init.io, arena, location, &graph);

    const text = try document_text(arena, subject, &graph);
    const manifests = graph.manifests[0..graph.manifest_count];
    const depfile = try depfile_text(arena, arguments[1], manifests);
    const cwd = std.Io.Dir.cwd();

    const document: std.Io.Dir.WriteFileOptions = .{
        .sub_path = arguments[1],
        .data = text,
        .flags = create_flags,
    };

    const listing: std.Io.Dir.WriteFileOptions = .{
        .sub_path = arguments[6],
        .data = depfile,
        .flags = create_flags,
    };

    try cwd.writeFile(init.io, document);
    try cwd.writeFile(init.io, listing);
}

pub fn graph_collect(
    io: std.Io,
    arena: std.mem.Allocator,
    location: Location,
    graph: *Graph,
) Error!void {
    assert(graph.count == 0);
    assert(location.manifest.len > 0);

    var queue: [dependency_count_max]Pending = undefined;

    var collection: Collection = .{
        .arena = arena,
        .buffer = try arena.alloc(u8, manifest_bytes_max + 1),
        .graph = graph,
        .io = io,
        .location = location,
        .queue = &queue,
        .tail = 0,
    };

    const source = switch (try manifest_read(&collection, location.manifest)) {
        .absent => return error.ManifestInvalid,
        .present => |file| file.text,
    };

    var parsed: Parsed = .empty;

    try dependencies_parse(arena, source, &parsed);

    graph.manifests[0] = location.manifest;
    graph.manifest_count = 1;

    try queue_extend(&collection, .{
        .base = std.Io.Dir.path.dirname(location.manifest) orelse ".",
        .dependencies = parsed.dependencies.slice(),
        .origin = ".",
        .parent = null,
    });

    var children: [dependency_count_max]std.ArrayList(u32) = @splat(.empty);
    var direct: std.ArrayList(u32) = .empty;

    for (0..dependency_count_max) |head| {
        if (head == collection.tail) break;

        const pending = queue[head];
        const index = try component_place(&collection, pending);

        if (pending.parent) |parent| {
            try children[parent].append(arena, index);
        } else {
            try direct.append(arena, index);
        }
    }

    for (graph.components[0..graph.count], children[0..graph.count]) |*component, list| {
        component.children = list.items;
    }

    graph.direct = direct.items;
}

fn queue_extend(collection: *Collection, extension: Extension) Error!void {
    assert(collection.tail <= dependency_count_max);
    assert(extension.base.len > 0);

    if (extension.dependencies.len > dependency_count_max - collection.tail) {
        return error.DependenciesTooMany;
    }

    for (extension.dependencies) |dependency| {
        collection.queue[collection.tail] = .{
            .base = extension.base,
            .dependency = dependency,
            .origin = extension.origin,
            .parent = extension.parent,
        };

        collection.tail += 1;
    }
}

fn component_place(collection: *Collection, pending: Pending) Error!u32 {
    const graph = collection.graph;

    assert(graph.count <= dependency_count_max);
    assert(pending.base.len > 0);

    const arena = collection.arena;
    const dependency = pending.dependency;
    const key = try key_of(arena, pending);

    for (graph.components[0..graph.count], 0..) |component, position| {
        if (!std.mem.eql(u8, component.key, key)) continue;

        const found: u32 = @intCast(position);

        assert(found < graph.count);

        return found;
    }

    if (graph.count == dependency_count_max) return error.DependenciesTooMany;

    const manifest = try manifest_of(collection, pending);
    const origin = try origin_of(arena, pending);
    const index = graph.count;

    var parsed: Parsed = .empty;

    switch (manifest) {
        .absent => {},
        .present => |file| {
            try dependencies_parse(arena, file.text, &parsed);
            graph.manifests[graph.manifest_count] = file.path;
            graph.manifest_count += 1;

            try queue_extend(collection, .{
                .base = std.Io.Dir.path.dirname(file.path) orelse ".",
                .dependencies = parsed.dependencies.slice(),
                .origin = origin,
                .parent = index,
            });
        },
    }

    graph.components[index] = .{
        .children = &.{},
        .dependency = dependency,
        .key = key,
        .reference = try arena.print("zig:{s}@{s}", .{ dependency.name, origin }),
        .resolved = manifest == .present,
        .version = parsed.version,
    };

    graph.count += 1;

    return index;
}

fn key_of(arena: std.mem.Allocator, pending: Pending) Error![]const u8 {
    assert(pending.base.len > 0);
    assert(pending.dependency.name.len > 0);

    const dependency = pending.dependency;

    if (dependency.hash) |hash| return hash;

    if (dependency.path) |path| {
        return std.Io.Dir.path.resolveAlloc(arena, &.{ pending.base, path });
    }

    return arena.print("{s}@{s}", .{ dependency.name, dependency.url orelse "" });
}

fn origin_of(arena: std.mem.Allocator, pending: Pending) Error![]const u8 {
    assert(pending.origin.len > 0);
    assert(pending.dependency.name.len > 0);

    const dependency = pending.dependency;

    if (dependency.hash) |hash| return hash;

    if (dependency.path) |path| {
        return std.Io.Dir.path.resolveAllocPosix(arena, &.{ pending.origin, path });
    }

    return dependency.url orelse dependency.name;
}

fn manifest_of(collection: *Collection, pending: Pending) Error!Manifest {
    assert(collection.location.cache_root.len > 0);
    assert(pending.base.len > 0);

    const arena = collection.arena;
    const dependency = pending.dependency;

    const path = if (dependency.hash) |hash|
        try std.Io.Dir.path.join(arena, &.{
            collection.location.cache_root,
            "p",
            hash,
            "build.zig.zon",
        })
    else if (dependency.path) |relative|
        try std.Io.Dir.path.join(arena, &.{ pending.base, relative, "build.zig.zon" })
    else
        return .absent;

    return manifest_read(collection, path);
}

fn manifest_read(collection: *Collection, path: []const u8) Error!Manifest {
    assert(path.len > 0);
    assert(collection.buffer.len == manifest_bytes_max + 1);

    const cwd = std.Io.Dir.cwd();
    const read = cwd.readFile(collection.io, path, collection.buffer) catch |err| switch (err) {
        error.FileNotFound => return .absent,
        else => return err,
    };

    if (read.len > manifest_bytes_max) return error.ManifestTooLarge;

    const text = try collection.arena.dupeSentinel(u8, read, 0);

    return .{ .present = .{ .path = path, .text = text } };
}

pub fn dependencies_parse(
    arena: std.mem.Allocator,
    source: [:0]const u8,
    parsed: *Parsed,
) Error!void {
    assert(source.len <= manifest_bytes_max);
    assert(parsed.dependencies.count == 0);

    const dependencies = &parsed.dependencies;

    const tree = try std.zig.Ast.parse(arena, source, .{ .mode = .zon, .recover = false });
    if (tree.errors.len > 0) return error.ManifestInvalid;

    const zoir = try std.zig.ZonGen.generate(arena, tree, .{ .parse_str_lits = true });
    if (zoir.hasCompileErrors()) return error.ManifestInvalid;

    const root = std.zig.Zoir.Node.Index.root.get(&zoir);
    if (root != .struct_literal) return error.ManifestInvalid;

    parsed.version = if (field_find(&zoir, root, "version")) |node| try text_of(node) else null;

    const listed = field_find(&zoir, root, "dependencies") orelse return;

    switch (listed) {
        .empty_literal => return,
        .struct_literal => |literal| {
            if (literal.names.len > dependency_count_max) return error.DependenciesTooMany;

            for (literal.names, 0..) |name, index| {
                const entry = literal.vals.at(@intCast(index)).get(&zoir);

                dependencies.items[index] = try dependency_of(&zoir, name.get(&zoir), entry);
                dependencies.count += 1;
            }
        },
        else => return error.ManifestInvalid,
    }

    assert(dependencies.count <= dependency_count_max);
}

fn dependency_of(
    zoir: *const std.zig.Zoir,
    name: []const u8,
    entry: std.zig.Zoir.Node,
) Error!Dependency {
    assert(name.len > 0);
    assert(zoir.nodes.len > 0);

    if (entry != .struct_literal) return error.ManifestInvalid;

    const lazy = if (field_find(zoir, entry, "lazy")) |node| switch (node) {
        .true => true,
        .false => false,
        else => return error.ManifestInvalid,
    } else false;

    const hash = field_find(zoir, entry, "hash");
    const path = field_find(zoir, entry, "path");
    const url = field_find(zoir, entry, "url");

    return .{
        .hash = if (hash) |node| try text_of(node) else null,
        .lazy = lazy,
        .name = name,
        .path = if (path) |node| try text_of(node) else null,
        .url = if (url) |node| try text_of(node) else null,
    };
}

fn text_of(node: std.zig.Zoir.Node) Error![]const u8 {
    assert(@tagName(node).len > 0);
    if (node == .string_literal) assert(node.string_literal.len <= manifest_bytes_max);

    if (node != .string_literal) return error.ManifestInvalid;
    if (node.string_literal.len == 0) return error.ManifestInvalid;
    return node.string_literal;
}

fn field_find(
    zoir: *const std.zig.Zoir,
    entry: std.zig.Zoir.Node,
    name: []const u8,
) ?std.zig.Zoir.Node {
    assert(entry == .struct_literal);
    assert(name.len > 0);

    const literal = entry.struct_literal;

    for (literal.names, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate.get(zoir), name)) {
            return literal.vals.at(@intCast(index)).get(zoir);
        }
    }

    return null;
}

pub fn depfile_text(
    arena: std.mem.Allocator,
    output: []const u8,
    manifests: []const []const u8,
) Error![]const u8 {
    assert(output.len > 0);
    assert(manifests.len <= dependency_count_max + 1);

    var text: std.Io.Writer.Allocating = .init(arena);

    try depfile_path_write(&text.writer, output);
    try text.writer.writeByte(':');

    for (manifests) |manifest| {
        try text.writer.writeByte(' ');
        try depfile_path_write(&text.writer, manifest);
    }

    try text.writer.writeByte('\n');

    return text.written();
}

fn depfile_path_write(writer: *std.Io.Writer, path: []const u8) Error!void {
    assert(path.len > 0);
    assert(path.len <= std.math.maxInt(u32));

    for (path) |character| {
        switch (character) {
            ' ', '\\', '#' => try writer.writeByte('\\'),
            '$' => try writer.writeByte('$'),
            else => {},
        }

        try writer.writeByte(character);
    }
}

pub fn document_text(
    arena: std.mem.Allocator,
    subject: Subject,
    graph: *const Graph,
) Error![]const u8 {
    assert(subject.distribution.len > 0);
    assert(graph.count <= dependency_count_max);

    var output: std.Io.Writer.Allocating = .init(arena);
    var json: std.json.Stringify = .{ .writer = &output.writer, .options = json_options };

    try json.beginObject();
    try json.objectField("bomFormat");
    try json.write("CycloneDX");
    try json.objectField("specVersion");
    try json.write("1.6");
    try json.objectField("version");
    try json.write(1);
    try json.objectField("metadata");
    try metadata_write(&json, subject);
    try json.objectField("components");
    try json.beginArray();

    for (graph.slice()) |component| try component_write(&json, component);

    try json.endArray();
    try json.objectField("dependencies");
    try json.beginArray();
    try edges_write(&json, graph, .{ .subject = subject.distribution }, graph.direct);

    for (graph.slice(), 0..) |component, index| {
        if (component.resolved) {
            try edges_write(&json, graph, .{ .component = @intCast(index) }, component.children);
        }
    }

    try json.endArray();
    try json.endObject();
    try output.writer.writeByte('\n');

    return output.written();
}

const json_options: std.json.Stringify.Options = .{
    .emit_null_optional_fields = false,
    .emit_nonportable_numbers_as_strings = false,
    .emit_strings_as_arrays = false,
    .escape_unicode = false,
    .whitespace = .indent_2,
};

fn edges_write(
    json: *std.json.Stringify,
    graph: *const Graph,
    owner: Owner,
    children: []const u32,
) Error!void {
    assert(children.len <= graph.count);
    assert(graph.count <= dependency_count_max);

    assert(switch (owner) {
        .component => |index| index < graph.count,
        .subject => |distribution| distribution.len > 0,
    });

    try json.beginObject();
    try json.objectField("ref");

    switch (owner) {
        .component => |index| try json.write(graph.components[index].reference),
        .subject => |distribution| try json.write(distribution),
    }

    try json.objectField("dependsOn");
    try json.beginArray();

    for (children) |child| try json.write(graph.components[child].reference);

    try json.endArray();
    try json.endObject();
}

fn metadata_write(json: *std.json.Stringify, subject: Subject) Error!void {
    assert(subject.distribution.len > 0);
    assert(subject.version.len > 0);

    try json.beginObject();
    try json.objectField("component");
    try json.beginObject();
    try json.objectField("type");
    try json.write("library");
    try json.objectField("bom-ref");
    try json.write(subject.distribution);
    try json.objectField("name");
    try json.write(subject.distribution);
    try json.objectField("version");
    try json.write(subject.version);
    try json.objectField("purl");
    try purl_write(json, subject);
    try json.endObject();
    try json.objectField("tools");
    try json.beginObject();
    try json.objectField("components");
    try json.beginArray();
    try json.beginObject();
    try json.objectField("type");
    try json.write("application");
    try json.objectField("name");
    try json.write("zig");
    try json.objectField("version");
    try json.write(builtin.zig_version_string);
    try json.endObject();
    try json.endArray();
    try json.endObject();
    try json.endObject();
}

fn component_write(json: *std.json.Stringify, component: Component) Error!void {
    assert(component.dependency.name.len > 0);
    assert(component.reference.len > 0);

    try json.beginObject();
    try json.objectField("type");
    try json.write("library");
    try json.objectField("bom-ref");
    try json.write(component.reference);
    try json.objectField("name");
    try json.write(component.dependency.name);

    if (component.version) |version| {
        try json.objectField("version");
        try json.write(version);
    }

    if (component.dependency.url) |url| {
        try json.objectField("externalReferences");
        try json.beginArray();
        try json.beginObject();
        try json.objectField("type");
        try json.write("distribution");
        try json.objectField("url");
        try json.write(url);
        try json.endObject();
        try json.endArray();
    }

    try json.objectField("properties");
    try json.beginArray();

    const dependency = component.dependency;

    if (dependency.hash) |hash| try property_write(json, .{ .name = "zig:hash", .value = hash });
    if (dependency.path) |path| try property_write(json, .{ .name = "zig:path", .value = path });
    if (dependency.lazy) try property_write(json, .{ .name = "zig:lazy", .value = "true" });

    try json.endArray();
    try json.endObject();
}

const Property = struct {
    name: []const u8,
    value: []const u8,
};

fn property_write(json: *std.json.Stringify, property: Property) Error!void {
    assert(property.name.len > 0);
    assert(property.value.len > 0);

    try json.beginObject();
    try json.objectField("name");
    try json.write(property.name);
    try json.objectField("value");
    try json.write(property.value);
    try json.endObject();
}

fn purl_write(json: *std.json.Stringify, subject: Subject) Error!void {
    assert(subject.distribution.len > 0);
    assert(subject.version.len > 0);

    try json.beginWriteRaw();
    try json.writer.writeAll("\"pkg:pypi/");

    var separated = false;

    for (subject.distribution) |character| {
        if (std.mem.findScalar(u8, "-_.", character) == null) {
            try json.writer.writeByte(std.ascii.toLower(character));
            separated = false;
        } else {
            if (!separated) try json.writer.writeByte('-');
            separated = true;
        }
    }

    try json.writer.print("@{s}\"", .{subject.version});
    json.endWriteRaw();
}

fn text_plain(text: []const u8) bool {
    assert(text.len <= manifest_bytes_max);
    assert(manifest_bytes_max > 0);

    if (text.len == 0) return false;

    for (text) |character| {
        if (std.ascii.isAlphanumeric(character)) continue;
        if (std.mem.findScalar(u8, "-_.+!", character) == null) return false;
    }

    return true;
}

test dependencies_parse {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    const source =
        \\.{
        \\    .name = .greeter,
        \\    .version = "0.2.0",
        \\    .dependencies = .{
        \\        .lacuna = .{ .path = "vendor/lacuna" },
        \\        .remote = .{ .url = "https://example.invalid/r.tar.gz", .hash = "N-V-abc" },
        \\        .optional = .{ .url = "https://example.invalid/o.tar.gz", .lazy = true },
        \\    },
        \\    .paths = .{""},
        \\}
    ;

    var parsed: Parsed = .empty;

    try dependencies_parse(arena, source, &parsed);

    const listed = parsed.dependencies.slice();

    try std.testing.expectEqualStrings("0.2.0", parsed.version.?);
    try std.testing.expectEqual(@as(usize, 3), listed.len);
    try std.testing.expectEqualStrings("vendor/lacuna", listed[0].path.?);
    try std.testing.expectEqualStrings("N-V-abc", listed[1].hash.?);
    try std.testing.expect(listed[2].lazy);
    try std.testing.expectEqual(@as(?[]const u8, null), listed[2].hash);

    var bare: Parsed = .empty;
    var broken: Parsed = .empty;

    try dependencies_parse(arena, ".{ .name = .bare, .dependencies = .{} }", &bare);

    try std.testing.expectEqual(@as(?[]const u8, null), bare.version);
    try std.testing.expectEqual(@as(u32, 0), bare.dependencies.count);

    const invalid = ".{ .dependencies = .{ .bad = .{ .url = 7 } } }";

    try std.testing.expectError(error.ManifestInvalid, dependencies_parse(arena, invalid, &broken));
}

test graph_collect {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();
    const io = std.testing.io;

    var temporary = std.testing.tmpDir(.{
        .access_sub_paths = true,
        .follow_symlinks = false,
        .iterate = false,
    });
    defer temporary.cleanup();

    const project_manifest = ".{ .version = \"1.0.0\", .dependencies = .{ " ++
        ".middle = .{ .path = \"../middle\" }, .remote = .{ .url = \"https://e.invalid/r\", " ++
        ".hash = \"N-V-remote\" }, .absent = .{ .url = \"https://e.invalid/a\", " ++
        ".hash = \"N-V-absent\", .lazy = true } } }";
    const middle_manifest = ".{ .version = \"2.0.0\", .dependencies = .{ " ++
        ".remote = .{ .url = \"https://e.invalid/r\", .hash = \"N-V-remote\" } } }";
    const remote_manifest = ".{ .version = \"3.1.4\", .dependencies = .{} }";

    const manifests = [_][2][]const u8{
        .{ "project/build.zig.zon", project_manifest },
        .{ "middle/build.zig.zon", middle_manifest },
        .{ "cache/p/N-V-remote/build.zig.zon", remote_manifest },
    };

    for (manifests) |manifest| {
        try temporary.dir.createDirPath(io, std.Io.Dir.path.dirname(manifest[0]).?);
        try temporary.dir.writeFile(io, .{ .sub_path = manifest[0], .data = manifest[1] });
    }

    const root = try temporary.dir.realPathFileAlloc(io, ".", arena);
    const location: Location = .{
        .cache_root = try std.Io.Dir.path.join(arena, &.{ root, "cache" }),
        .manifest = try std.Io.Dir.path.join(arena, &.{ root, "project", "build.zig.zon" }),
    };

    var graph: Graph = .empty;

    try graph_collect(io, arena, location, &graph);

    const components = graph.slice();

    try std.testing.expectEqual(@as(u32, 3), graph.count);
    try std.testing.expectEqual(@as(u32, 3), graph.manifest_count);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2 }, graph.direct);
    try std.testing.expectEqualStrings("zig:middle@../middle", components[0].reference);
    try std.testing.expectEqualStrings("2.0.0", components[0].version.?);
    try std.testing.expectEqualSlices(u32, &.{1}, components[0].children);
    try std.testing.expectEqualStrings("zig:remote@N-V-remote", components[1].reference);
    try std.testing.expectEqualStrings("3.1.4", components[1].version.?);
    try std.testing.expect(!components[2].resolved);
    try std.testing.expectEqual(@as(?[]const u8, null), components[2].version);

    const subject: Subject = .{ .distribution = "project", .version = "1.0.0" };
    const text = try document_text(arena, subject, &graph);

    try std.testing.expect(std.mem.find(u8, text, root) == null);
    try std.testing.expect(std.mem.find(u8, text, "\"version\": \"3.1.4\"") != null);

    const depfile = try depfile_text(arena, "out dir/sbom.json", graph.manifests[0..3]);

    try std.testing.expect(std.mem.startsWith(u8, depfile, "out\\ dir/sbom.json: "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, depfile, "\n"));
}

test document_text {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    var graph: Graph = .empty;

    graph.components[0] = .{
        .children = &.{},
        .dependency = .{
            .hash = "N-V-abc",
            .lazy = false,
            .name = "remote",
            .path = null,
            .url = "https://example.invalid/r.tar.gz",
        },
        .key = "N-V-abc",
        .reference = "zig:remote@N-V-abc",
        .resolved = false,
        .version = null,
    };

    graph.count = 1;
    graph.direct = &.{0};

    const subject: Subject = .{ .distribution = "greeter", .version = "0.2.0" };
    const text = try document_text(arena, subject, &graph);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{
        .allocate = .alloc_always,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .max_value_len = text.len,
        .parse_numbers = true,
    });
    const component = parsed.object.get("components").?.array.items[0].object;
    const edges = parsed.object.get("dependencies").?.array.items;

    try std.testing.expectEqualStrings("CycloneDX", parsed.object.get("bomFormat").?.string);
    try std.testing.expectEqualStrings("zig:remote@N-V-abc", component.get("bom-ref").?.string);
    try std.testing.expectEqual(@as(usize, 1), edges.len);
    try std.testing.expect(std.mem.find(u8, text, "\"version\": null") == null);

    var none: Graph = .empty;

    const named: Subject = .{ .distribution = "My_Package..Tool", .version = "1.0" };
    const renamed = try document_text(arena, named, &none);
    const purl = "\"purl\": \"pkg:pypi/my-package-tool@1.0\"";

    try std.testing.expect(std.mem.find(u8, renamed, purl) != null);
    try std.testing.expect(text_plain("1.0rc1+local"));
    try std.testing.expect(!text_plain("bad\"name"));
}
