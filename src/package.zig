const builtin = @import("builtin");
const std = @import("std");

const signature = @import("signature.zig");
const version_module = @import("version.zig");

const assert = std.debug.assert;

pub const Author = struct {
    email: ?[]const u8,
    name: []const u8,
};

pub const EntryGroup = struct {
    entries: []const EntryPoint,
    group: []const u8,
};

pub const EntryPoint = struct {
    name: []const u8,
    target: []const u8,
};

pub const Extra = struct {
    dependencies: []const []const u8,
    name: []const u8,
};

pub const Link = struct {
    label: []const u8,
    url: []const u8,
};

pub const Metadata = struct {
    authors: []const Author,
    classifiers: []const []const u8,
    content_type: ?[]const u8,
    dependencies: []const []const u8 = &.{},
    dynamic: []const []const u8 = &.{},
    extras: []const Extra = &.{},
    keywords: []const []const u8,
    license_expression: ?[]const u8,
    license_files: []const []const u8,
    links: []const Link,
    maintainers: []const Author = &.{},
    name: []const u8,
    obsoletes: []const []const u8 = &.{},
    provides: []const []const u8 = &.{},
    python_version_min: version_module.Version = version_module.floor,
    requires_python: ?[]const u8 = null,
    summary: ?[]const u8,
    version: []const u8,
};

pub const Problem = enum {
    dependency_invalid,
    distribution_invalid,
    dynamic_invalid,
    entry_point_invalid,
    extra_invalid,
    license_file_invalid,
    module_invalid,
    requires_python_below_minimum,
    requires_python_invalid,
    version_invalid,
};

pub const distribution_bytes_max: u32 = 256;
pub const list_count_max: u32 = 256;
pub const metadata_bytes_max: u32 = 64 * 1024;

pub const specifier_count_max: u32 = 16;
pub const tag_count_max: u32 = 8;
pub const version_bytes_max: u32 = 64;
pub const wheel_bytes_max: u32 = 1024;
const generator = "lacuna 0.1.0 (zig " ++ builtin.zig_version_string ++ ")";

const dynamic_fields = [_][]const u8{
    "Author",
    "Author-email",
    "Classifier",
    "Description",
    "Description-Content-Type",
    "Keywords",
    "License",
    "License-Expression",
    "License-File",
    "Maintainer",
    "Maintainer-email",
    "Obsoletes-Dist",
    "Platform",
    "Project-URL",
    "Provides-Dist",
    "Provides-Extra",
    "Requires-Dist",
    "Requires-External",
    "Requires-Python",
    "Summary",
    "Supported-Platform",
};

const specifier_operators = [_][]const u8{ "===", "==", "!=", "~=", ">=", "<=", ">", "<" };

const name_characters =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-";

comptime {
    assert(metadata_bytes_max > wheel_bytes_max);
    assert(distribution_bytes_max <= metadata_bytes_max);
}

pub fn problem_of(metadata: *const Metadata, module_name: []const u8) ?Problem {
    assert(metadata.license_files.len <= list_count_max);
    assert(module_name.len < 1 << 16);

    if (!signature.module_name_valid(module_name)) return .module_invalid;
    if (!distribution_valid(metadata.name)) return .distribution_invalid;
    if (!version_valid(metadata.version)) return .version_invalid;

    for (metadata.license_files) |file| {
        if (file.len == 0) return .license_file_invalid;
        if (std.mem.findAny(u8, file, "/\\") != null) return .license_file_invalid;
    }

    for (metadata.dependencies) |dependency| {
        if (!requirement_valid(dependency)) return .dependency_invalid;
    }

    for (metadata.extras) |extra| {
        if (!distribution_valid(extra.name)) return .extra_invalid;

        for (extra.dependencies) |dependency| {
            if (!requirement_valid(dependency)) return .dependency_invalid;
        }
    }

    return relations_problem(metadata);
}

fn relations_problem(metadata: *const Metadata) ?Problem {
    assert(metadata.provides.len <= list_count_max);
    assert(metadata.obsoletes.len <= list_count_max);

    for (metadata.provides) |provided| {
        if (!requirement_valid(provided)) return .dependency_invalid;
    }

    for (metadata.obsoletes) |obsoleted| {
        if (!requirement_valid(obsoleted)) return .dependency_invalid;
    }

    for (metadata.dynamic) |field| {
        if (!dynamic_valid(field)) return .dynamic_invalid;
    }

    const requires_python = metadata.requires_python orelse return null;
    return requires_python_problem(requires_python, metadata.python_version_min);
}

fn major_only(release: []const u8) ?version_module.Version {
    assert(release.len <= version_module.text_bytes_max);
    assert(release.len > 0);

    const major = std.fmt.parseInt(u8, release, 10) catch return null;
    if (major == 0) return null;
    return .{ .major = major, .minor = 0 };
}

fn dynamic_valid(field: []const u8) bool {
    assert(field.len < 1 << 16);
    assert(dynamic_fields.len > 0);

    for (dynamic_fields) |allowed| {
        if (std.ascii.eqlIgnoreCase(allowed, field)) return true;
    }

    return false;
}

pub fn requires_python_problem(
    specifier: []const u8,
    minimum: version_module.Version,
) ?Problem {
    assert(specifier.len < 1 << 16);
    assert(minimum.major == 3);

    var clauses = std.mem.splitScalar(u8, specifier, ',');
    var lower: ?version_module.Version = null;

    for (0..specifier_count_max + 1) |_| {
        const clause = clauses.next() orelse break;
        const bound = clause_lower_bound(std.mem.trim(u8, clause, " ")) orelse {
            return .requires_python_invalid;
        };

        if (bound.lower) |version| lower = version;
    } else return .requires_python_invalid;

    const found = lower orelse return .requires_python_below_minimum;
    if (found.rank() < minimum.rank()) return .requires_python_below_minimum;
    return null;
}

const Bound = struct {
    lower: ?version_module.Version,
};

fn clause_lower_bound(clause: []const u8) ?Bound {
    assert(clause.len < 1 << 16);
    assert(specifier_operators.len == 8);

    const operator = for (specifier_operators) |candidate| {
        if (std.mem.startsWith(u8, clause, candidate)) break candidate;
    } else return null;

    const text = std.mem.trim(u8, clause[operator.len..], " ");
    const release = std.mem.trimEnd(u8, text, ".*");
    if (release.len == 0) return null;
    if (release.len > version_module.text_bytes_max) return null;
    if (std.mem.findNone(u8, release, "0123456789.") != null) return null;

    const version = version_module.parse(release) orelse major_only(release) orelse return null;
    const bounding = operator[0] == '>' or operator[0] == '~' or operator[0] == '=';

    return .{ .lower = if (bounding) version else null };
}

pub fn entry_points_problem(groups: []const EntryGroup) ?Problem {
    assert(groups.len <= list_count_max);
    assert(list_count_max > 0);

    for (groups) |group| {
        if (!dotted_valid(group.group)) return .entry_point_invalid;

        for (group.entries) |entry| {
            if (!entry_name_valid(entry.name)) return .entry_point_invalid;
            if (!entry_target_valid(entry.target)) return .entry_point_invalid;
        }
    }

    return null;
}

pub fn requirement_valid(requirement: []const u8) bool {
    assert(requirement.len < 1 << 16);
    assert(distribution_bytes_max > 0);

    const name_end = std.mem.findNone(u8, requirement, name_characters) orelse requirement.len;
    if (!distribution_valid(requirement[0..name_end])) return false;
    if (std.mem.findAny(u8, requirement, "\r\n") != null) return false;

    for (requirement) |character| {
        if (character < ' ') return false;
        if (character > '~') return false;
    }

    return true;
}

fn entry_name_valid(name: []const u8) bool {
    assert(name.len < 1 << 16);
    assert(name_characters.len > 0);

    if (name.len == 0) return false;
    if (name[0] == '[') return false;
    return std.mem.findNone(u8, name, name_characters) == null;
}

fn entry_target_valid(target: []const u8) bool {
    assert(target.len < 1 << 16);
    assert(name_characters.len > 0);

    const colon = std.mem.findScalar(u8, target, ':') orelse return dotted_valid(target);
    if (!dotted_valid(target[0..colon])) return false;
    return dotted_valid(target[colon + 1 ..]);
}

fn dotted_valid(text: []const u8) bool {
    assert(text.len < 1 << 16);
    assert(name_characters.len > 0);

    if (text.len == 0) return false;

    var parts = std.mem.splitScalar(u8, text, '.');

    for (0..text.len) |_| {
        const part = parts.next() orelse break;
        if (!signature.identifier_valid(part)) return false;
    }

    return true;
}

pub fn entry_points_write(
    writer: *std.Io.Writer,
    groups: []const EntryGroup,
) std.Io.Writer.Error!void {
    assert(entry_points_problem(groups) == null);
    assert(writer.buffer.len > 0);

    for (groups) |group| {
        try writer.print("[{s}]\n", .{group.group});

        for (group.entries) |entry| try writer.print("{s} = {s}\n", .{ entry.name, entry.target });

        try writer.writeByte('\n');
    }
}

pub fn data_name_valid(name: []const u8) bool {
    assert(name.len <= std.math.maxInt(u32));
    assert(list_count_max > 0);

    if (name.len == 0) return false;
    if (name.len > distribution_bytes_max) return false;
    if (name[0] == '/') return false;
    if (std.mem.findScalar(u8, name, '\\') != null) return false;

    const body = if (name[name.len - 1] == '/') name[0 .. name.len - 1] else name;

    if (body.len == 0) return false;

    var parts = std.mem.splitScalar(u8, body, '/');

    for (0..body.len + 1) |_| {
        const part = parts.next() orelse return true;

        if (part.len == 0) return false;
        if (std.mem.eql(u8, part, ".")) return false;
        if (std.mem.eql(u8, part, "..")) return false;
    }

    unreachable;
}

pub fn distribution_valid(name: []const u8) bool {
    assert(name.len < 1 << 16);
    assert(distribution_bytes_max > 0);

    if (name.len == 0) return false;
    if (name.len > distribution_bytes_max) return false;
    if (!std.ascii.isAlphanumeric(name[0])) return false;
    if (!std.ascii.isAlphanumeric(name[name.len - 1])) return false;

    for (name) |character| {
        if (!distribution_character(character)) return false;
    }

    return true;
}

fn distribution_character(character: u8) bool {
    assert(character <= std.math.maxInt(u8));
    assert(distribution_bytes_max > 0);

    if (std.ascii.isAlphanumeric(character)) return true;
    if (character == '-') return true;
    if (character == '_') return true;
    return character == '.';
}

pub fn version_valid(version: []const u8) bool {
    assert(version.len < 1 << 16);
    assert(version_bytes_max > 0);

    if (version.len > version_bytes_max) return false;

    var rest = release_skip(version) orelse return false;

    inline for (.{ "a", "b", "rc" }) |prefix| {
        if (std.mem.startsWith(u8, rest, prefix)) {
            rest = digits_skip(rest[prefix.len..]) orelse return false;

            break;
        }
    }

    if (std.mem.startsWith(u8, rest, ".post")) rest = digits_skip(rest[5..]) orelse return false;
    if (std.mem.startsWith(u8, rest, ".dev")) rest = digits_skip(rest[4..]) orelse return false;
    return rest.len == 0;
}

fn release_skip(version: []const u8) ?[]const u8 {
    assert(version.len <= version_bytes_max);
    assert(version_bytes_max > 0);

    var rest = digits_skip(version) orelse return null;

    for (0..version_bytes_max) |_| {
        if (rest.len < 2) break;
        if (rest[0] != '.') break;
        if (!std.ascii.isDigit(rest[1])) break;

        rest = digits_skip(rest[1..]) orelse return null;
    } else unreachable;

    assert(rest.len < version.len);

    return rest;
}

fn digits_skip(text: []const u8) ?[]const u8 {
    assert(text.len <= version_bytes_max);
    assert(version_bytes_max > 0);

    var count: usize = 0;

    for (text) |character| {
        if (!std.ascii.isDigit(character)) break;

        count += 1;
    }

    if (count == 0) return null;

    if (count > 1) {
        if (text[0] == '0') return null;
    }

    return text[count..];
}

pub fn distribution_normalize(name: []const u8, buffer: *[distribution_bytes_max]u8) []const u8 {
    assert(distribution_valid(name));
    assert(buffer.len == distribution_bytes_max);

    var length: usize = 0;
    var separator = false;

    for (name) |character| {
        if (std.ascii.isAlphanumeric(character)) {
            if (separator) {
                buffer[length] = '_';
                length += 1;
            }

            separator = false;
            buffer[length] = std.ascii.toLower(character);
            length += 1;
        } else {
            separator = true;
        }
    }

    assert(length <= name.len);

    return buffer[0..length];
}

pub fn metadata_write(writer: *std.Io.Writer, metadata: *const Metadata) std.Io.Writer.Error!void {
    assert(metadata.name.len > 0);
    assert(version_valid(metadata.version));

    try writer.print("Metadata-Version: 2.4\nName: {s}\nVersion: {s}\n", .{
        metadata.name,
        metadata.version,
    });

    if (metadata.summary) |summary| try writer.print("Summary: {s}\n", .{summary});

    for (metadata.authors) |author| try person_write(writer, "Author", author);
    for (metadata.maintainers) |maintainer| try person_write(writer, "Maintainer", maintainer);

    if (metadata.license_expression) |expression| {
        try writer.print("License-Expression: {s}\n", .{expression});
    }

    for (metadata.license_files) |file| try writer.print("License-File: {s}\n", .{file});

    if (metadata.requires_python) |requires_python| {
        try writer.print("Requires-Python: {s}\n", .{requires_python});
    } else {
        try writer.print("Requires-Python: >={d}.{d}\n", .{
            metadata.python_version_min.major,
            metadata.python_version_min.minor,
        });
    }

    for (metadata.dependencies) |dependency| {
        try writer.print("Requires-Dist: {s}\n", .{dependency});
    }

    for (metadata.provides) |provided| try writer.print("Provides-Dist: {s}\n", .{provided});
    for (metadata.obsoletes) |obsoleted| try writer.print("Obsoletes-Dist: {s}\n", .{obsoleted});

    for (metadata.extras) |extra| try extra_write(writer, extra);

    try keywords_write(writer, metadata.keywords);

    for (metadata.classifiers) |classifier| try writer.print("Classifier: {s}\n", .{classifier});

    for (
        metadata.links,
    ) |link| try writer.print("Project-URL: {s}, {s}\n", .{ link.label, link.url });

    if (metadata.content_type) |content_type| {
        try writer.print("Description-Content-Type: {s}\n", .{content_type});
    }

    for (metadata.dynamic) |field| try writer.print("Dynamic: {s}\n", .{field});
}

fn extra_write(writer: *std.Io.Writer, extra: Extra) std.Io.Writer.Error!void {
    assert(distribution_valid(extra.name));
    assert(writer.buffer.len > 0);

    try writer.print("Provides-Extra: {s}\n", .{extra.name});

    for (extra.dependencies) |dependency| {
        if (std.mem.findScalar(u8, dependency, ';')) |semicolon| {
            const requirement = std.mem.trimEnd(u8, dependency[0..semicolon], " ");
            const marker = std.mem.trim(u8, dependency[semicolon + 1 ..], " ");

            try writer.print("Requires-Dist: {s}; ({s}) and extra == \"{s}\"\n", .{
                requirement,
                marker,
                extra.name,
            });
        } else {
            try writer.print("Requires-Dist: {s}; extra == \"{s}\"\n", .{ dependency, extra.name });
        }
    }
}

fn person_write(
    writer: *std.Io.Writer,
    role: []const u8,
    person: Author,
) std.Io.Writer.Error!void {
    assert(person.name.len > 0);
    assert(role.len > 0);

    if (person.email) |email| {
        try writer.print("{s}-email: {s} <{s}>\n", .{ role, person.name, email });
    } else {
        try writer.print("{s}: {s}\n", .{ role, person.name });
    }
}

fn keywords_write(writer: *std.Io.Writer, keywords: []const []const u8) std.Io.Writer.Error!void {
    assert(keywords.len <= list_count_max);
    assert(writer.buffer.len > 0);

    if (keywords.len == 0) return;

    try writer.writeAll("Keywords: ");

    for (keywords, 0..) |keyword, index| {
        if (index > 0) try writer.writeByte(',');

        try writer.writeAll(keyword);
    }

    try writer.writeByte('\n');
}

pub const Tags = struct {
    interpreter: []const u8,
    platform: []const u8,
    purelib: bool,
};

pub fn wheel_write(writer: *std.Io.Writer, tags: Tags) std.Io.Writer.Error!void {
    assert(std.mem.findScalar(u8, tags.platform, '-') == null);
    assert(tags.interpreter.len > 0);
    assert(tags.platform.len > 0);

    const purelib = if (tags.purelib) "true" else "false";

    try writer.print("Wheel-Version: 1.0\nGenerator: {s}\nRoot-Is-Purelib: {s}\n", .{
        generator,
        purelib,
    });

    var parts = std.mem.splitScalar(u8, tags.platform, '.');

    for (0..tag_count_max) |_| {
        const part = parts.next() orelse break;

        try writer.print("Tag: {s}-{s}\n", .{ tags.interpreter, part });
    } else unreachable;
}

test problem_of {
    const license_files = [_][]const u8{"LICENSE"};
    const nested = [_][]const u8{"licenses/LICENSE"};

    var metadata: Metadata = .{
        .authors = &.{},
        .classifiers = &.{},
        .content_type = null,
        .keywords = &.{},
        .license_expression = null,
        .license_files = &license_files,
        .links = &.{},
        .name = "faker-zig",
        .summary = null,
        .version = "0.1.0",
    };

    try std.testing.expectEqual(@as(?Problem, null), problem_of(&metadata, "faker"));
    try std.testing.expectEqual(@as(?Problem, .module_invalid), problem_of(&metadata, "fa-ker"));

    metadata.license_files = &nested;

    try std.testing.expectEqual(
        @as(?Problem, .license_file_invalid),
        problem_of(&metadata, "faker"),
    );

    metadata.name = "-faker";

    try std.testing.expectEqual(
        @as(?Problem, .distribution_invalid),
        problem_of(&metadata, "faker"),
    );
}

test requirement_valid {
    try std.testing.expect(requirement_valid("numpy"));
    try std.testing.expect(requirement_valid("numpy>=2.0; python_version >= '3.12'"));
    try std.testing.expect(requirement_valid("faker-zig[full]==0.1.0"));
    try std.testing.expect(!requirement_valid(">=2.0"));
    try std.testing.expect(!requirement_valid("numpy\nVersion: 9"));
    try std.testing.expect(!requirement_valid(""));
}

test entry_points_write {
    const scripts = [_]EntryPoint{.{ .name = "fake", .target = "faker_zig.cli:main" }};
    const groups = [_]EntryGroup{.{ .entries = &scripts, .group = "console_scripts" }};
    const invalid = [_]EntryPoint{.{ .name = "fake", .target = "faker-zig:main" }};
    const rejected = [_]EntryGroup{.{ .entries = &invalid, .group = "console_scripts" }};

    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try entry_points_write(&writer, &groups);

    try std.testing.expectEqualStrings(
        "[console_scripts]\nfake = faker_zig.cli:main\n\n",
        writer.buffered(),
    );

    const problem = entry_points_problem(&rejected);

    try std.testing.expectEqual(@as(?Problem, .entry_point_invalid), problem);
}

test version_valid {
    try std.testing.expect(version_valid("0.1.0"));
    try std.testing.expect(version_valid("2026.10"));
    try std.testing.expect(version_valid("1.0rc2"));
    try std.testing.expect(version_valid("1.0.post1.dev3"));
    try std.testing.expect(!version_valid("1.0-beta"));
    try std.testing.expect(!version_valid("01.0"));
    try std.testing.expect(!version_valid("v1.0"));
    try std.testing.expect(!version_valid("1."));
    try std.testing.expect(!version_valid(""));
}

test distribution_normalize {
    var buffer: [distribution_bytes_max]u8 = undefined;

    try std.testing.expectEqualStrings("faker_zig", distribution_normalize("Faker-Zig", &buffer));
    try std.testing.expectEqualStrings("a_b_c", distribution_normalize("a.-_b__c", &buffer));
    try std.testing.expect(!distribution_valid("faker zig"));
    try std.testing.expect(!distribution_valid("faker-"));
}

test metadata_write {
    const authors = [_]Author{
        .{ .email = "ada@example.com", .name = "Ada" },
        .{ .email = null, .name = "Grace" },
    };

    const keywords = [_][]const u8{ "fake", "data" };
    const links = [_]Link{.{ .label = "Source", .url = "https://example.com/faker" }};
    const license_files = [_][]const u8{"LICENSE"};

    const metadata: Metadata = .{
        .authors = &authors,
        .classifiers = &.{"Programming Language :: Zig"},
        .content_type = "text/markdown",
        .dependencies = &.{"typing-extensions>=4.6"},
        .extras = &.{.{
            .dependencies = &.{"numpy>=2; python_version >= '3.12'"},
            .name = "arrays",
        }},
        .keywords = &keywords,
        .license_expression = "MIT",
        .license_files = &license_files,
        .links = &links,
        .name = "faker-zig",
        .summary = "Fake data from Zig.",
        .version = "0.1.0",
    };

    const expected =
        \\Metadata-Version: 2.4
        \\Name: faker-zig
        \\Version: 0.1.0
        \\Summary: Fake data from Zig.
        \\Author-email: Ada <ada@example.com>
        \\Author: Grace
        \\License-Expression: MIT
        \\License-File: LICENSE
        \\Requires-Python: >=3.11
        \\Requires-Dist: typing-extensions>=4.6
        \\Provides-Extra: arrays
        \\Requires-Dist: numpy>=2; (python_version >= '3.12') and extra == "arrays"
        \\Keywords: fake,data
        \\Classifier: Programming Language :: Zig
        \\Project-URL: Source, https://example.com/faker
        \\Description-Content-Type: text/markdown
        \\
    ;

    var buffer: [metadata_bytes_max]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try metadata_write(&writer, &metadata);
    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test requires_python_problem {
    const minimum: version_module.Version = .{ .major = 3, .minor = 12 };
    const below: ?Problem = .requires_python_below_minimum;
    const invalid: ?Problem = .requires_python_invalid;

    try std.testing.expectEqual(@as(?Problem, null), requires_python_problem(">=3.12", minimum));
    try std.testing.expectEqual(@as(?Problem, null), requires_python_problem(">=3.13,<4", minimum));
    try std.testing.expectEqual(@as(?Problem, null), requires_python_problem("~=3.12", minimum));
    try std.testing.expectEqual(@as(?Problem, null), requires_python_problem("==3.14.*", minimum));
    try std.testing.expectEqual(below, requires_python_problem(">=3.11", minimum));
    try std.testing.expectEqual(below, requires_python_problem("<4", minimum));
    try std.testing.expectEqual(below, requires_python_problem("!=3.11", minimum));
    try std.testing.expectEqual(invalid, requires_python_problem("", minimum));
    try std.testing.expectEqual(invalid, requires_python_problem("3.12", minimum));
    try std.testing.expectEqual(invalid, requires_python_problem(">=three", minimum));
    try std.testing.expectEqual(invalid, requires_python_problem(">=3.12,", minimum));
}

test relations_problem {
    const people = [_]Author{.{ .email = "lin@example.com", .name = "Lin" }};

    var metadata: Metadata = .{
        .authors = &.{},
        .classifiers = &.{},
        .content_type = null,
        .dynamic = &.{"Requires-Dist"},
        .keywords = &.{},
        .license_expression = null,
        .license_files = &.{},
        .links = &.{},
        .maintainers = &people,
        .name = "faker-zig",
        .obsoletes = &.{"faker-c"},
        .provides = &.{"faker"},
        .python_version_min = .{ .major = 3, .minor = 12 },
        .requires_python = ">=3.12",
        .summary = null,
        .version = "0.1.0",
    };

    try std.testing.expectEqual(@as(?Problem, null), problem_of(&metadata, "faker"));

    var buffer: [metadata_bytes_max]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try metadata_write(&writer, &metadata);

    const expected =
        \\Metadata-Version: 2.4
        \\Name: faker-zig
        \\Version: 0.1.0
        \\Maintainer-email: Lin <lin@example.com>
        \\Requires-Python: >=3.12
        \\Provides-Dist: faker
        \\Obsoletes-Dist: faker-c
        \\Dynamic: Requires-Dist
        \\
    ;

    try std.testing.expectEqualStrings(expected, writer.buffered());

    metadata.dynamic = &.{"Name"};

    try std.testing.expectEqual(@as(?Problem, .dynamic_invalid), problem_of(&metadata, "faker"));

    metadata.dynamic = &.{};
    metadata.requires_python = ">=3.11";

    try std.testing.expectEqual(
        @as(?Problem, .requires_python_below_minimum),
        problem_of(&metadata, "faker"),
    );
}

test wheel_write {
    var buffer: [wheel_bytes_max]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try wheel_write(&writer, .{
        .interpreter = "cp311-abi3",
        .platform = "manylinux_2_17_x86_64.manylinux2014_x86_64",
        .purelib = false,
    });

    const expected = "Wheel-Version: 1.0\nGenerator: lacuna 0.1.0 (zig " ++
        builtin.zig_version_string ++ ")\n" ++
        \\Root-Is-Purelib: false
        \\Tag: cp311-abi3-manylinux_2_17_x86_64
        \\Tag: cp311-abi3-manylinux2014_x86_64
        \\
    ;

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test data_name_valid {
    try std.testing.expect(data_name_valid("share/mixed/notes.txt"));
    try std.testing.expect(data_name_valid("include/mixed/"));
    try std.testing.expect(data_name_valid("tool"));
    try std.testing.expect(!data_name_valid(""));
    try std.testing.expect(!data_name_valid("/"));
    try std.testing.expect(!data_name_valid("/etc/passwd"));
    try std.testing.expect(!data_name_valid("share/../../escape"));
    try std.testing.expect(!data_name_valid("share//double"));
    try std.testing.expect(!data_name_valid("./share"));
    try std.testing.expect(!data_name_valid("share\\windows"));
}
