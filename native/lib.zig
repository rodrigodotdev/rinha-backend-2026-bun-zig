const fraud = @import("ffi/fraud.zig");

pub export fn fraud_init() i32 {
    return fraud.init();
}

pub export fn fraud_ready() bool {
    return fraud.ready();
}

pub export fn fraud_score_json(ptr: [*]const u8, len: usize) u8 {
    return fraud.countFraudJson(ptr[0..len]);
}
