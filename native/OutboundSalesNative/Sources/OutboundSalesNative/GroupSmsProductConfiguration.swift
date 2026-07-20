import OutboundSalesCore
import Foundation

enum SoheeGroupSmsProductConfiguration {
    static let shortcutInstallURL = URL(string: "https://www.icloud.com/shortcuts/b779b53ba1ed4c2b826355c2c583910b")!

    static let transport = GroupSmsTransportConfiguration(
        shortcutName: "SoheeGroupSMS",
        shortcutVersion: "0.1",
        callbackScheme: "com.lucid47.outboundsales"
    )
}
