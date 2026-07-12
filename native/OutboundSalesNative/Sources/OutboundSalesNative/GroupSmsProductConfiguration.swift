import OutboundSalesCore

enum SoheeGroupSmsProductConfiguration {
    static let transport = GroupSmsTransportConfiguration(
        shortcutName: "SoheeGroupSMS",
        shortcutVersion: "0.1",
        callbackScheme: "com.lucid47.outboundsales"
    )
}
