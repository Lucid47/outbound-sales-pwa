import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
enum PhoneCallLauncher {
    static func call(customer: Customer, state: NativeAppState, openURL: OpenURLAction, onFallback: @escaping (String) -> Void) {
        let phone = cleanPhone(customer.phoneNumber)
        guard hasDialablePhone(phone) else {
            onFallback("전화 가능한 연락처가 없습니다.")
            return
        }

        state.recordContact(customer: customer, type: .call)

        guard let telURL = URL(string: "tel:\(phone)") else {
            copyPhone(phone)
            onFallback("전화번호를 열지 못해 번호를 복사했습니다.")
            return
        }

        openURL(telURL) { accepted in
            guard !accepted else { return }
            openFaceTimeAudio(phone: phone, openURL: openURL, onFallback: onFallback)
        }
    }

    private static func openFaceTimeAudio(phone: String, openURL: OpenURLAction, onFallback: @escaping (String) -> Void) {
        guard let faceTimeURL = URL(string: "facetime-audio://\(phone)") else {
            copyPhone(phone)
            onFallback(fallbackMessage)
            return
        }

        openURL(faceTimeURL) { accepted in
            guard !accepted else { return }
            copyPhone(phone)
            onFallback(fallbackMessage)
        }
    }

    private static var fallbackMessage: String {
        "전화앱을 열 수 없어 번호를 복사했습니다. iPad의 Phone 앱 설치, iPhone 통화 연동, FaceTime 통화 설정을 확인하세요."
    }

    private static func copyPhone(_ phone: String) {
        #if os(iOS)
        UIPasteboard.general.string = phone
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phone, forType: .string)
        #endif
    }
}
