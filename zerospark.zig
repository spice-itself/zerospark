const std = @import("std");
const os = std.os;
const process = std.process; 
const linux = std.os.linux;

var child_exited: bool = false;
var allocator = std.heap.page_allocator;

fn handleSigchld(sig: c_int) callconv(.C) void {
    _ = sig;
    child_exited = true;
}

const ServiceConfig = struct {
    command: []const u8,
    args: []const []const u8,
    restart: bool,
};

const RunningService = struct {
    config: ServiceConfig,
    child: *process.Child,
};

fn parseConfig(content: []const u8) !std.ArrayList(ServiceConfig) {
    var services = std.ArrayList(ServiceConfig).init(allocator);
    errdefer services.deinit();

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        
        var parts = std.mem.splitSequence(u8, line, ":");
        const restart_str = parts.first();
        const command_part = parts.rest();

        var args_split = std.mem.splitSequence(u8, command_part, " ");
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();

        while (args_split.next()) |arg| {
            if (arg.len > 0) try args.append(arg);
        }
        if (args.items.len == 0) continue;

        try services.append(.{
            .command = args.items[0],
            .args = args.items[1..],
            .restart = std.mem.eql(u8, restart_str, "true"),
        });
    }
    return services;
}

fn buildArgv(alloc: std.mem.Allocator, command: []const u8, args: []const []const u8) ![]const []const u8 {
    var argv = try std.ArrayList([]const u8).initCapacity(alloc, args.len + 1);
    try argv.append(command);
    try argv.appendSlice(args);
    return argv.toOwnedSlice();
}

pub fn main() !void {
    const config_file = try std.fs.cwd().openFile("init.conf", .{});
    defer config_file.close();

    const config_content = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_content);

    var services = try parseConfig(config_content);
    defer services.deinit();

    var running_services = std.ArrayList(RunningService).init(allocator);
    defer {
        for (running_services.items) |*rs| {
            _ = rs.child.kill() catch {};
            allocator.destroy(rs.child);
        }
        running_services.deinit();
    }

    // Spawn initial services
    for (services.items) |config| {
        var child = try allocator.create(process.Child);
        child.* = .{
            .allocator = allocator,
            .argv = try buildArgv(allocator, config.command, config.args),
            .env_map = null,
            .cwd = null,
            .stdin_behavior = .Inherit,
            .stdout_behavior = .Inherit,
            .stderr_behavior = .Inherit,
            .expand_arg0 = .no_expand,
            .uid = null,
            .gid = null,
            .pgid = null,
            .err_pipe = null,
            .thread_handle = undefined,
            .id = undefined,
            .term = null,
            .stdin = null,
            .stdout = null,
            .stderr = null,
        };
        try child.spawn();
        try running_services.append(.{ .config = config, .child = child });
    }

    // Setup SIGCHLD handler
    const sa = linux.Sigaction{
        .handler = .{ .handler = handleSigchld },
        .mask = linux.empty_sigset,
        .flags = linux.SA.NOCLDSTOP | linux.SA.RESTART,
    };
    _ = linux.sigaction(linux.SIG.CHLD, &sa, null);

    // Main loop
    while (true) {
        if (child_exited) {
            child_exited = false;
            
            // Collect exited processes
            while (true) {
                var status: u32 = undefined;
                const pid = linux.waitpid(-1, &status, linux.W.NOHANG);
                if (pid <= 0) break;

                // Find and handle exited service
                var i: usize = 0;
                while (i < running_services.items.len) {
                    if (running_services.items[i].child.id == pid) {
                        const rs = running_services.swapRemove(i);
                        _ = rs.child.kill() catch {};
                        allocator.destroy(rs.child);

                        const exit_code = linux.W.EXITSTATUS(status);
                        std.log.info("Service '{s}' exited ({})", .{rs.config.command, exit_code});

                        if (rs.config.restart) {
                            std.log.info("Restarting '{s}'...", .{rs.config.command});
                            var new_child = try allocator.create(process.Child);
                            new_child.* = .{
                                .allocator = allocator,
                                .argv = try buildArgv(allocator, rs.config.command, rs.config.args),
                                .env_map = null,
                                .cwd = null,
                                .stdin_behavior = .Inherit,
                                .stdout_behavior = .Inherit,
                                .stderr_behavior = .Inherit,
                                .expand_arg0 = .no_expand,
                                .uid = null,
                                .gid = null,
                                .pgid = null,
                                .err_pipe = null,
                                .thread_handle = undefined,
                                .id = undefined,
                                .term = null,
                                .stdin = null,
                                .stdout = null,
                                .stderr = null,
                            };
                            try new_child.spawn();
                            try running_services.append(.{ .config = rs.config, .child = new_child });
                        }
                        continue;
                    }
                    i += 1;
                }
            }
        }

        // Reduce CPU usage
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}
