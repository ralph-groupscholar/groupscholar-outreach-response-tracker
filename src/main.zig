const std = @import("std");
const root = @import("root.zig");

const SchemaName = "groupscholar_outreach_response_tracker";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "help")) {
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, command, "init")) {
        try runSqlFile(allocator, "sql/schema.sql");
        return;
    }

    if (std.mem.eql(u8, command, "seed")) {
        try runSqlFile(allocator, "sql/seed.sql");
        return;
    }

    if (std.mem.eql(u8, command, "import")) {
        if (args.len < 3) {
            std.debug.print("Missing CSV path.\n", .{});
            try printUsage();
            return;
        }
        try importCsv(allocator, args[2]);
        return;
    }

    if (std.mem.eql(u8, command, "log")) {
        try logEntry(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, command, "report")) {
        try runReport(allocator);
        return;
    }

    if (std.mem.eql(u8, command, "queue")) {
        try runQueue(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, command, "triage")) {
        try runTriage(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, command, "sla")) {
        try runSla(allocator, args[2..]);
        return;
    }

    std.debug.print("Unknown command: {s}\n", .{command});
    try printUsage();
}

fn printUsage() !void {
    const out = std.io.getStdOut().writer();
    const usage =
        "Groupscholar Outreach Response Tracker\n\n" ++
        "Usage:\n" ++
        "  outreach-tracker init\n" ++
        "  outreach-tracker seed\n" ++
        "  outreach-tracker import <csv_path>\n" ++
        "  outreach-tracker log --scholar <id> --channel <channel> --sent <timestamp> [--responded <timestamp>] [--response-type <type>] [--notes <notes>]\n" ++
        "  outreach-tracker report\n\n" ++
        "  outreach-tracker queue [--hours <n>] [--limit <n>] [--channel <name>]\n\n" ++
        "  outreach-tracker triage [--days <n>] [--min-attempts <n>] [--limit <n>] [--channel <name>]\n\n" ++
        "  outreach-tracker sla [--channel <name>] [--since-days <n>]\n\n" ++
        "Environment:\n" ++
        "  GS_DB_URL  PostgreSQL connection string.\n\n";
    try out.print("{s}", .{usage});
}

fn getDbUrl(allocator: std.mem.Allocator) ![]u8 {
    const env = std.process.getEnvVarOwned(allocator, "GS_DB_URL") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            std.debug.print("GS_DB_URL is not set.\n", .{});
        }
        return err;
    };
    return env;
}

fn runSqlFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const db_url = try getDbUrl(allocator);
    defer allocator.free(db_url);

    const sql = try std.fs.cwd().readFileAlloc(allocator, path, 1_000_000);
    defer allocator.free(sql);

    try runPsql(allocator, db_url, sql, &.{});
}

fn runPsql(
    allocator: std.mem.Allocator,
    db_url: []const u8,
    sql: []const u8,
    extra_args: []const []const u8,
) !void {
    var args = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer args.deinit();

    try args.append("psql");
    try args.append(db_url);
    try args.append("-v");
    try args.append("ON_ERROR_STOP=1");
    for (extra_args) |arg| {
        try args.append(arg);
    }
    try args.append("-c");
    try args.append(sql);

    var child = std.process.Child.init(args.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.PsqlFailed,
        else => return error.PsqlFailed,
    }
}

fn importCsv(allocator: std.mem.Allocator, csv_path: []const u8) !void {
    const db_url = try getDbUrl(allocator);
    defer allocator.free(db_url);

    const contents = try std.fs.cwd().readFileAlloc(allocator, csv_path, 5_000_000);
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    const header_line = lines.next() orelse return error.EmptyCsv;
    const header = try root.parseCsvLine(allocator, std.mem.trimRight(u8, header_line, "\r"));
    defer root.freeCsvRow(allocator, header);

    const required = [_][]const u8{ "scholar_id", "channel", "sent_at", "responded_at", "response_type", "notes" };
    var indices: [required.len]usize = undefined;
    for (required, 0..) |name, idx| {
        const found = findHeaderIndex(header.fields, name) orelse return error.MissingColumn;
        indices[idx] = found;
    }

    var values = std.array_list.AlignedManaged(u8, null).init(allocator);
    defer values.deinit();

    var row_count: usize = 0;
    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, "\r");
        if (line.len == 0) continue;
        const row = try root.parseCsvLine(allocator, line);
        defer root.freeCsvRow(allocator, row);

        if (row.fields.len < header.fields.len) continue;

        if (row_count > 0) try values.appendSlice(",\n");
        try values.append('(');
        for (required, 0..) |_, idx| {
            if (idx > 0) try values.appendSlice(", ");
            const field = row.fields[indices[idx]];
            const value = std.mem.trim(u8, field, " \t");
            if (value.len == 0) {
                try values.appendSlice("NULL");
            } else {
                const escaped = try root.escapeSql(allocator, value);
                defer allocator.free(escaped);
                try values.append('\'');
                try values.appendSlice(escaped);
                try values.append('\'');
            }
        }
        try values.append(')');
        row_count += 1;
    }

    if (row_count == 0) {
        std.debug.print("No rows found to import.\n", .{});
        return;
    }

    const insert_sql = try std.fmt.allocPrint(
        allocator,
        "INSERT INTO {s}.outreach_logs (scholar_id, channel, sent_at, responded_at, response_type, notes) VALUES\n{s};",
        .{ SchemaName, values.items },
    );
    defer allocator.free(insert_sql);

    try runPsql(allocator, db_url, insert_sql, &.{});
}

fn logEntry(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var scholar_id: ?[]const u8 = null;
    var channel: ?[]const u8 = null;
    var sent_at: ?[]const u8 = null;
    var responded_at: ?[]const u8 = null;
    var response_type: ?[]const u8 = null;
    var notes: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--scholar") and i + 1 < args.len) {
            scholar_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--channel") and i + 1 < args.len) {
            channel = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--sent") and i + 1 < args.len) {
            sent_at = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--responded") and i + 1 < args.len) {
            responded_at = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--response-type") and i + 1 < args.len) {
            response_type = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--notes") and i + 1 < args.len) {
            notes = args[i + 1];
            i += 1;
        }
    }

    if (scholar_id == null or channel == null or sent_at == null) {
        std.debug.print("Missing required fields.\n", .{});
        try printUsage();
        return;
    }

    const db_url = try getDbUrl(allocator);
    defer allocator.free(db_url);

    const scholar_sql = try sqlValue(allocator, scholar_id.?);
    defer allocator.free(scholar_sql);
    const channel_sql = try sqlValue(allocator, channel.?);
    defer allocator.free(channel_sql);
    const sent_sql = try sqlValue(allocator, sent_at.?);
    defer allocator.free(sent_sql);
    const responded_sql = try optionalSqlValue(allocator, responded_at);
    defer allocator.free(responded_sql);
    const response_sql = try optionalSqlValue(allocator, response_type);
    defer allocator.free(response_sql);
    const notes_sql = try optionalSqlValue(allocator, notes);
    defer allocator.free(notes_sql);

    const insert_sql = try std.fmt.allocPrint(
        allocator,
        "INSERT INTO {s}.outreach_logs (scholar_id, channel, sent_at, responded_at, response_type, notes) VALUES ({s}, {s}, {s}, {s}, {s}, {s});",
        .{ SchemaName, scholar_sql, channel_sql, sent_sql, responded_sql, response_sql, notes_sql },
    );
    defer allocator.free(insert_sql);

    try runPsql(allocator, db_url, insert_sql, &.{});
}

fn runReport(allocator: std.mem.Allocator) !void {
    const db_url = try getDbUrl(allocator);
    defer allocator.free(db_url);

    std.debug.print("Response rate by channel:\n", .{});
    try runPsql(
        allocator,
        db_url,
        "SELECT channel, COUNT(*) AS sent, COUNT(responded_at) AS responded, ROUND(COUNT(responded_at)::numeric / NULLIF(COUNT(*),0), 2) AS response_rate FROM " ++ SchemaName ++ ".outreach_logs GROUP BY channel ORDER BY response_rate DESC;",
        &.{ "-F", "\t", "-t" },
    );

    std.debug.print("\nAverage response time (hours) by channel:\n", .{});
    try runPsql(
        allocator,
        db_url,
        "SELECT channel, ROUND(AVG(EXTRACT(EPOCH FROM (responded_at - sent_at)) / 3600), 1) AS avg_hours FROM " ++ SchemaName ++ ".outreach_logs WHERE responded_at IS NOT NULL GROUP BY channel ORDER BY avg_hours ASC;",
        &.{ "-F", "\t", "-t" },
    );
}

fn runQueue(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var hours: u32 = 48;
    var limit: u32 = 25;
    var channel: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--hours") and i + 1 < args.len) {
            hours = try parsePositiveInt(args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--limit") and i + 1 < args.len) {
            limit = try parsePositiveInt(args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--channel") and i + 1 < args.len) {
            channel = args[i + 1];
            i += 1;
        }
    }

    const db_url = try getDbUrl(allocator);
    defer allocator.free(db_url);

    var channel_clause = std.array_list.AlignedManaged(u8, null).init(allocator);
    defer channel_clause.deinit();
    if (channel) |channel_value| {
        const escaped = try root.escapeSql(allocator, channel_value);
        defer allocator.free(escaped);
        try channel_clause.appendSlice(" AND channel = '");
        try channel_clause.appendSlice(escaped);
        try channel_clause.append('\'');
    }

    const query = try std.fmt.allocPrint(
        allocator,
        "SELECT id, scholar_id, channel, sent_at, ROUND(EXTRACT(EPOCH FROM (NOW() - sent_at)) / 3600, 1) AS hours_outstanding FROM {s}.outreach_logs WHERE responded_at IS NULL AND sent_at <= NOW() - INTERVAL '{d} hours'{s} ORDER BY sent_at ASC LIMIT {d};",
        .{ SchemaName, hours, channel_clause.items, limit },
    );
    defer allocator.free(query);

    std.debug.print("Outstanding follow-ups older than {d} hours:\n", .{hours});
    try runPsql(
        allocator,
        db_url,
        query,
        &.{ "-F", "\t", "-t" },
    );
}

fn runTriage(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var days: u32 = 30;
    var min_attempts: u32 = 2;
    var limit: u32 = 20;
    var channel: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--days") and i + 1 < args.len) {
            days = try parsePositiveInt(args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--min-attempts") and i + 1 < args.len) {
            min_attempts = try parsePositiveInt(args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--limit") and i + 1 < args.len) {
            limit = try parsePositiveInt(args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--channel") and i + 1 < args.len) {
            channel = args[i + 1];
            i += 1;
        }
    }

    const db_url = try getDbUrl(allocator);
    defer allocator.free(db_url);

    var channel_clause = std.array_list.AlignedManaged(u8, null).init(allocator);
    defer channel_clause.deinit();
    if (channel) |channel_value| {
        const escaped = try root.escapeSql(allocator, channel_value);
        defer allocator.free(escaped);
        try channel_clause.appendSlice(" AND channel = '");
        try channel_clause.appendSlice(escaped);
        try channel_clause.append('\'');
    }

    const query = try std.fmt.allocPrint(
        allocator,
        "SELECT scholar_id, COUNT(*) AS outstanding, MAX(sent_at) AS last_sent_at, ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(sent_at))) / 3600, 1) AS hours_since_last, string_agg(DISTINCT channel, ', ' ORDER BY channel) AS channels FROM {s}.outreach_logs WHERE responded_at IS NULL AND sent_at >= NOW() - INTERVAL '{d} days'{s} GROUP BY scholar_id HAVING COUNT(*) >= {d} ORDER BY outstanding DESC, last_sent_at ASC LIMIT {d};",
        .{ SchemaName, days, channel_clause.items, min_attempts, limit },
    );
    defer allocator.free(query);

    std.debug.print("Scholars with >= {d} unanswered attempts in last {d} days:\n", .{ min_attempts, days });
    try runPsql(
        allocator,
        db_url,
        query,
        &.{ "-F", "\t", "-t" },
    );
}

fn runSla(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var channel: ?[]const u8 = null;
    var since_days: ?u32 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--channel") and i + 1 < args.len) {
            channel = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--since-days") and i + 1 < args.len) {
            since_days = try parsePositiveInt(args[i + 1]);
            i += 1;
        }
    }

    const db_url = try getDbUrl(allocator);
    defer allocator.free(db_url);

    var where_clause = std.array_list.AlignedManaged(u8, null).init(allocator);
    defer where_clause.deinit();
    if (channel) |channel_value| {
        const escaped = try root.escapeSql(allocator, channel_value);
        defer allocator.free(escaped);
        try where_clause.appendSlice(" AND channel = '");
        try where_clause.appendSlice(escaped);
        try where_clause.append('\'');
    }
    if (since_days) |days| {
        const days_str = try std.fmt.allocPrint(allocator, "{d}", .{days});
        defer allocator.free(days_str);
        try where_clause.appendSlice(" AND sent_at >= NOW() - INTERVAL '");
        try where_clause.appendSlice(days_str);
        try where_clause.appendSlice(" days'");
    }

    const query = try std.fmt.allocPrint(
        allocator,
        "SELECT channel, COUNT(*) AS sent, COUNT(responded_at) AS responded, " ++
            "ROUND(100.0 * COUNT(*) FILTER (WHERE responded_at IS NOT NULL AND responded_at - sent_at <= INTERVAL '24 hours') / NULLIF(COUNT(*),0), 1) AS pct_24h, " ++
            "ROUND(100.0 * COUNT(*) FILTER (WHERE responded_at IS NOT NULL AND responded_at - sent_at <= INTERVAL '48 hours') / NULLIF(COUNT(*),0), 1) AS pct_48h, " ++
            "ROUND(100.0 * COUNT(*) FILTER (WHERE responded_at IS NOT NULL AND responded_at - sent_at <= INTERVAL '72 hours') / NULLIF(COUNT(*),0), 1) AS pct_72h, " ++
            "ROUND(100.0 * COUNT(*) FILTER (WHERE responded_at IS NULL) / NULLIF(COUNT(*),0), 1) AS pct_outstanding " ++
            "FROM {s}.outreach_logs WHERE 1=1{s} GROUP BY channel ORDER BY pct_48h DESC, sent DESC;",
        .{ SchemaName, where_clause.items },
    );
    defer allocator.free(query);

    std.debug.print("Response SLA coverage by channel (24h/48h/72h/outstanding):\n", .{});
    try runPsql(
        allocator,
        db_url,
        query,
        &.{ "-F", "\t", "-t" },
    );
}

fn findHeaderIndex(headers: [][]u8, name: []const u8) ?usize {
    for (headers, 0..) |header, idx| {
        if (std.mem.eql(u8, std.mem.trim(u8, header, " \t"), name)) return idx;
    }
    return null;
}

fn sqlValue(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const escaped = try root.escapeSql(allocator, value);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "'{s}'", .{escaped});
}

fn optionalSqlValue(allocator: std.mem.Allocator, value: ?[]const u8) ![]u8 {
    if (value == null) return allocator.dupe(u8, "NULL");
    const trimmed = std.mem.trim(u8, value.?, " \t");
    if (trimmed.len == 0) return allocator.dupe(u8, "NULL");
    return sqlValue(allocator, trimmed);
}

fn parsePositiveInt(value: []const u8) !u32 {
    const parsed = try std.fmt.parseInt(u32, value, 10);
    if (parsed == 0) return error.InvalidValue;
    return parsed;
}

test "parsePositiveInt rejects zero" {
    const result = parsePositiveInt("0");
    try std.testing.expectError(error.InvalidValue, result);
}

test "parsePositiveInt rejects negative numbers" {
    const result = parsePositiveInt("-1");
    try std.testing.expectError(error.Overflow, result);
}
