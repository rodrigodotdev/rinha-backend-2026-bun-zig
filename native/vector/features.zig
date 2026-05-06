const payload_schema = @import("../schema/payload.zig");
const vector_types = @import("types.zig");

const MAX_AMOUNT: f32 = 10000.0;
const MAX_INSTALLMENTS: f32 = 12.0;
const AMOUNT_VS_AVG_RATIO: f32 = 10.0;
const MAX_MINUTES: f32 = 1440.0;
const MAX_KM: f32 = 1000.0;
const MAX_TX_COUNT_24H: f32 = 20.0;
const MAX_MERCHANT_AVG_AMOUNT: f32 = 10000.0;

pub fn vectorize(payload: *const payload_schema.Payload) vector_types.Vector14 {
    var values = [_]f32{0.0} ** 14;

    values[0] = clamp01(payload.amount / MAX_AMOUNT);
    values[1] = clamp01(@as(f32, @floatFromInt(payload.installments)) / MAX_INSTALLMENTS);

    const ratio = if (payload.customer_avg_amount > 0.0)
        (payload.amount / payload.customer_avg_amount) / AMOUNT_VS_AVG_RATIO
    else
        1.0;
    values[2] = clamp01(ratio);

    values[3] = round4(@as(f32, @floatFromInt(payload.hour)) / 23.0);
    values[4] = round4(@as(f32, @floatFromInt(payload.day_of_week)) / 6.0);

    if (payload.has_last_tx) {
        values[5] = clamp01(@as(f32, @floatFromInt(payload.minutes_since_last)) / MAX_MINUTES);
        values[6] = clamp01(payload.km_from_current / MAX_KM);
    } else {
        values[5] = -1.0;
        values[6] = -1.0;
    }

    values[7] = clamp01(payload.km_from_home / MAX_KM);
    values[8] = clamp01(@as(f32, @floatFromInt(payload.tx_count_24h)) / MAX_TX_COUNT_24H);
    values[9] = if (payload.is_online) 1.0 else 0.0;
    values[10] = if (payload.card_present) 1.0 else 0.0;
    values[11] = if (payload.is_unknown_merchant) 1.0 else 0.0;
    values[12] = mccRisk(payload.mcc);
    values[13] = clamp01(payload.merchant_avg_amount / MAX_MERCHANT_AVG_AMOUNT);

    return values;
}

fn round4(value: f32) f32 {
    return @round(value * 10000.0) * 0.0001;
}

fn clamp01(value: f32) f32 {
    if (value <= 0.0) return 0.0;
    if (value >= 1.0) return 1.0;
    return round4(value);
}

fn mccRisk(mcc: u32) f32 {
    return switch (mcc) {
        5411 => 0.15,
        5812 => 0.30,
        5912 => 0.20,
        5944 => 0.45,
        7801 => 0.80,
        7802 => 0.75,
        7995 => 0.85,
        4511 => 0.35,
        5311 => 0.25,
        5999 => 0.50,
        else => 0.50,
    };
}
