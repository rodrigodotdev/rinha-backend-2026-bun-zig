const payload_schema = @import("../schema/payload.zig");
const json = @import("../parser/json.zig");
const detector = @import("../runtime/detector.zig");
const features = @import("../vector/features.zig");
const vector_types = @import("../vector/types.zig");

pub fn init() i32 {
    return detector.initDefault();
}

pub fn ready() bool {
    return detector.ready();
}

pub fn countFraudJson(body: []const u8) u8 {
    if (!detector.ready()) return 0;

    var output: vector_types.Vector14 = undefined;
    parseAndVectorize(body, &output) catch return 0;
    return detector.countFraud(&output);
}

fn parseAndVectorize(body: []const u8, out: *vector_types.Vector14) payload_schema.ParseError!void {
    const payload = try json.parse(body);
    out.* = features.vectorize(&payload);
}
