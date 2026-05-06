const index_format = @import("../index/format.zig");

const K_NEIGHBORS: usize = 5;
const WORST_DISTANCE: f32 = 1.0e30;

const Neighbor = struct {
    distance: f32,
    label: u8,
};

pub const Top5 = struct {
    items: [K_NEIGHBORS]Neighbor = [_]Neighbor{.{ .distance = WORST_DISTANCE, .label = index_format.LABEL_LEGIT }} ** K_NEIGHBORS,
    worst_index: usize = 0,

    pub fn init() Top5 {
        return .{};
    }

    pub fn worstDistance(self: *const Top5) f32 {
        return self.items[self.worst_index].distance;
    }

    pub fn insert(self: *Top5, distance: f32, label: u8) void {
        if (distance >= self.worstDistance()) return;
        self.items[self.worst_index] = .{ .distance = distance, .label = label };
        self.worst_index = self.findWorst();
    }

    pub fn fraudCount(self: *const Top5) u8 {
        var count: u8 = 0;
        for (self.items) |neighbor| {
            if (neighbor.label == index_format.LABEL_FRAUD) count += 1;
        }
        return count;
    }

    fn findWorst(self: *const Top5) usize {
        var worst: usize = 0;
        var distance = self.items[0].distance;
        for (1..K_NEIGHBORS) |i| {
            if (self.items[i].distance > distance) {
                distance = self.items[i].distance;
                worst = i;
            }
        }
        return worst;
    }
};
