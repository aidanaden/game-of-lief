const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const UnitPoint = struct {
    x: i32,
    y: i32,
};
const NEIGHBOR_UNITS = [8]UnitPoint{
    .{ .x = 0, .y = 1 },
    .{ .x = 1, .y = 1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 1, .y = -1 },
    .{ .x = 0, .y = -1 },
    .{ .x = -1, .y = -1 },
    .{ .x = -1, .y = 0 },
    .{ .x = -1, .y = 1 },
};

const Point = struct {
    x: u32,
    y: u32,
};

const Grid = struct {
    live_points: std.AutoHashMap(Point, bool),
    size: u32,
    fn seed(self: *Grid, rand: *const std.rand.Random, num_lives: u32, num_neighbours: u32) Allocator.Error!void {
        const start = @as(i32, @intCast(0));
        const window = rand.intRangeAtMost(u32, 4, 12);
        const min_x = self.size / window;
        const max_x = self.size - min_x;
        const min_y = min_x;
        const max_y = max_x;

        for (start..num_lives) |_| {
            const x = rand.intRangeAtMost(u32, min_x, max_x);
            const y = rand.intRangeAtMost(u32, min_y, max_y);

            try self.live_points.put(Point{ .x = x, .y = y }, true);

            const neighbors: u32 = if (num_neighbours > 8) 8 else num_neighbours;
            for (0..neighbors) |_| {
                const unit_idx = rand.intRangeAtMost(u32, 0, 7);
                const neighbor = NEIGHBOR_UNITS[unit_idx];

                const calculated_x: i32 = @as(i32, @intCast(x)) + neighbor.x;
                const new_x = @as(u32, @intCast(calculated_x));

                const calculated_y: i32 = @as(i32, @intCast(y)) + neighbor.y;
                const new_y = @as(u32, @intCast(calculated_y));

                try self.live_points.put(Point{ .x = new_x, .y = new_y }, true);
            }
        }
    }
    fn next(self: *Grid) Allocator.Error!void {
        var next_live_points = try self.live_points.clone();
        next_live_points.clearRetainingCapacity();
        var iterator = self.live_points.iterator();
        while (iterator.next()) |e| {
            const point = e.key_ptr;
            const is_live = e.value_ptr.*;
            var live_neighbors: u32 = 0;
            for (NEIGHBOR_UNITS) |neigh| {
                const calculated_x: i32 = @as(i32, @intCast(point.x)) + neigh.x;
                if (calculated_x < 0) {
                    continue;
                }
                const new_x = @as(u32, @intCast(calculated_x));

                const calculated_y: i32 = @as(i32, @intCast(point.y)) + neigh.y;
                if (calculated_y < 0) {
                    continue;
                }
                const new_y = @as(u32, @intCast(calculated_y));

                const live = self.live_points.get(Point{ .x = new_x, .y = new_y }) orelse false;
                if (live) {
                    live_neighbors += 1;
                }
            }
            if (is_live and ((live_neighbors == 2) or (live_neighbors == 3))) {
                try next_live_points.put(Point{ .x = point.x, .y = point.y }, true);
                for (NEIGHBOR_UNITS) |unit| {
                    const neigh_x: i32 = @as(i32, @intCast(point.x)) + unit.x;
                    const neigh_y: i32 = @as(i32, @intCast(point.y)) + unit.y;
                    const neigh_point = Point{ .x = @as(u32, @intCast(neigh_x)), .y = @as(u32, @intCast(neigh_y)) };
                    const exists = next_live_points.get(neigh_point) orelse false;
                    if (neigh_x < self.size and neigh_x > 0 and neigh_y < self.size and neigh_y > 0 and !exists) {
                        try next_live_points.put(neigh_point, false);
                    }
                }
            }
            if (!is_live and live_neighbors == 3) {
                try next_live_points.put(Point{ .x = point.x, .y = point.y }, true);
                for (NEIGHBOR_UNITS) |unit| {
                    const neigh_x: i32 = @as(i32, @intCast(point.x)) + unit.x;
                    const neigh_y: i32 = @as(i32, @intCast(point.y)) + unit.y;
                    const neigh_point = Point{ .x = @as(u32, @intCast(neigh_x)), .y = @as(u32, @intCast(neigh_y)) };
                    const exists = next_live_points.get(neigh_point) orelse false;
                    if (neigh_x < self.size and neigh_x > 0 and neigh_y < self.size and neigh_y > 0 and !exists) {
                        try next_live_points.put(neigh_point, false);
                    }
                }
            }
        }
        self.live_points = next_live_points;
    }
    fn print(self: *Grid, writer: *const std.io.AnyWriter, allocator: Allocator) !void {
        for (0..self.size) |y| {
            var lines = ArrayList(u8).init(allocator);
            for (0..self.size) |x| {
                const point = Point{ .x = @as(u32, @intCast(x)), .y = @as(u32, @intCast(y)) };

                const is_live = self.live_points.get(point) orelse false;
                const point_str: u8 = if (is_live) '#' else '.';
                try lines.append(point_str);
                try lines.append(' ');
            }
            try lines.append('\n');
            _ = try writer.write(lines.items);
        }
    }
    fn lives(self: *Grid) u32 {
        var total: u32 = 0;
        var iterator = self.live_points.iterator();
        while (iterator.next()) |lp| {
            if (lp.value_ptr.*) {
                total += 1;
            }
        }
        return total;
    }
};

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    var stdout = bw.writer().any();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const live_points = std.AutoHashMap(Point, bool).init(
        allocator,
    );
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed_val: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed_val));
        break :blk seed_val;
    });
    const rand = prng.random();

    const size: u32 = 30;
    var grid = Grid{ .live_points = live_points, .size = size };

    _ = try stdout.write("\x1B[2J\x1B[H");

    try grid.seed(&rand, 35, 4);
    try grid.print(&stdout, allocator);
    try bw.flush();

    var runs: u32 = 0;
    const max_size: u32 = size * size;
    var generation: u32 = 0;
    const generations_till_reset: u32 = 150;
    var dead_generations: u32 = 0;
    var prev_lives: u32 = 0;
    const max_dead_generations = 25;

    const ns_per_us: u64 = 1000;
    const ns_per_ms: u64 = 1000 * ns_per_us;
    // const ns_per_s: u64 = 1000 * ns_per_ms;

    while (true) {
        // bring cursor to "home" location, in just about any currently-used
        // terminal emulation mode
        _ = try stdout.write("\x1B[2J\x1B[H");

        generation += 1;

        try grid.next();
        try grid.print(&stdout, allocator);

        try stdout.print(
            "\nRuns: {}\nGeneration: {}\nTotal population: {}/{}",
            .{ runs, generation, grid.lives(), max_size },
        );

        try bw.flush();

        // Increment dead generations, reset if past threshold
        if (grid.lives() == 0 or prev_lives == grid.lives()) {
            if (dead_generations > max_dead_generations) {
                runs += 1;
                generation = 0;
                dead_generations = 0;
                try grid.seed(&rand, 35, 4);
            }
            dead_generations += 1;
        }

        if (generation == generations_till_reset) {
            runs += 1;
            generation = 0;
            dead_generations = 0;
            try grid.seed(&rand, 35, 4);
        }

        prev_lives = grid.lives();
        std.time.sleep(150 * ns_per_ms);
    }
}
