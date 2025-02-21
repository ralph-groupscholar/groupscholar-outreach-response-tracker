const std = @import("std");

pub const CsvRow = struct {
    fields: [][]u8,
};

pub fn escapeSql(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.array_list.AlignedManaged(u8, null).init(allocator);
    errdefer out.deinit();
    for (value) |ch| {
        if (ch == '\'') {
            try out.append('\'');
            try out.append('\'');
        } else {
            try out.append(ch);
        }
    }
    return out.toOwnedSlice();
}

pub fn parseCsvLine(allocator: std.mem.Allocator, line: []const u8) !CsvRow {
    var fields = std.array_list.AlignedManaged([]u8, null).init(allocator);
    errdefer {
        for (fields.items) |item| allocator.free(item);
        fields.deinit();
    }

    var field = std.array_list.AlignedManaged(u8, null).init(allocator);
    defer field.deinit();

    var in_quotes = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const ch = line[i];
        if (ch == '"') {
            if (in_quotes and i + 1 < line.len and line[i + 1] == '"') {
                try field.append('"');
                i += 1;
            } else {
                in_quotes = !in_quotes;
            }
        } else if (ch == ',' and !in_quotes) {
            try fields.append(try field.toOwnedSlice());
            field.clearRetainingCapacity();
        } else {
            try field.append(ch);
        }
    }

    try fields.append(try field.toOwnedSlice());

    return CsvRow{ .fields = try fields.toOwnedSlice() };
}

pub fn freeCsvRow(allocator: std.mem.Allocator, row: CsvRow) void {
    for (row.fields) |field| allocator.free(field);
    allocator.free(row.fields);
}

test "escapeSql doubles single quotes" {
    const allocator = std.testing.allocator;
    const escaped = try escapeSql(allocator, "O'Hara");
    defer allocator.free(escaped);
    try std.testing.expectEqualStrings("O''Hara", escaped);
}

test "parseCsvLine handles quotes" {
    const allocator = std.testing.allocator;
    const row = try parseCsvLine(allocator, "alpha,\"bravo, charlie\",\"delta\"\"echo\"");
    defer freeCsvRow(allocator, row);
    try std.testing.expectEqual(@as(usize, 3), row.fields.len);
    try std.testing.expectEqualStrings("alpha", row.fields[0]);
    try std.testing.expectEqualStrings("bravo, charlie", row.fields[1]);
    try std.testing.expectEqualStrings("delta\"echo", row.fields[2]);
}
