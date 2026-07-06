import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct MessageComposerSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let customer: Customer

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        state.recordContact(customer: customer, type: .manualSms)
                        openMessages()
                    } label: {
                        Label("일반 문자 보내기", systemImage: "message")
                    }
                    .disabled(!hasDialablePhone(customer.phoneNumber))
                } header: {
                    Text(customer.name.isEmpty ? customer.phoneNumber : "\(customer.name) · \(customer.phoneNumber)")
                } footer: {
                    Text("템플릿 문자는 본문을 클립보드에 복사한 뒤 문자앱을 엽니다.")
                }

                Section("문자 템플릿") {
                    if state.messageTemplates.isEmpty {
                        Text("설정 탭에서 문자 템플릿을 추가하세요.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.messageTemplates) { template in
                            Button {
                                let body = render(template.body)
                                copyToClipboard(body)
                                state.recordContact(
                                    customer: customer,
                                    type: .templateSms,
                                    result: .opened,
                                    messageBody: body,
                                    templateId: template.id
                                )
                                openMessages()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Label(template.title, systemImage: template.isDefault ? "star.fill" : "text.bubble")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(render(template.body))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .disabled(!hasDialablePhone(customer.phoneNumber))
                        }
                    }
                }
            }
            .navigationTitle("문자 보내기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func render(_ body: String) -> String {
        body
            .replacingOccurrences(of: "{고객명}", with: customer.name)
            .replacingOccurrences(of: "{{고객명}}", with: customer.name)
            .replacingOccurrences(of: "{이름}", with: customer.name)
            .replacingOccurrences(of: "{{이름}}", with: customer.name)
            .replacingOccurrences(of: "{주소}", with: customer.address)
            .replacingOccurrences(of: "{{주소}}", with: customer.address)
    }

    private func openMessages() {
        if let url = URL(string: "sms:\(cleanPhone(customer.phoneNumber))") {
            openURL(url)
        }
        dismiss()
    }

    private func copyToClipboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
