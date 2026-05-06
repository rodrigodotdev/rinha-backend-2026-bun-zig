pub const MAX_KNOWN_MERCHANTS: usize = 64;

pub const ParseError = error{
    ExpectedValue,
    InvalidString,
    InvalidNumber,
    InvalidTimestamp,
    TooManyKnownMerchants,
};

pub const Payload = struct {
    amount: f32,
    customer_avg_amount: f32,
    merchant_avg_amount: f32,
    km_from_home: f32,
    km_from_current: f32,
    tx_count_24h: u32,
    mcc: u32,
    minutes_since_last: u32,
    installments: u8,
    hour: u8,
    day_of_week: u8,
    is_online: bool,
    card_present: bool,
    is_unknown_merchant: bool,
    has_last_tx: bool,
};
