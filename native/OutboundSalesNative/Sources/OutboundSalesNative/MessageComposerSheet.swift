import OutboundSalesCore
import SwiftUI
#if os(iOS)
import MessageUI
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
    #if os(iOS)
    @State private var draft: MessageDraft?
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        startMessage(body: nil, type: .manualSms, templateId: nil)
                    } label: {
                        Label("일반 문자 보내기", systemImage: "message")
                    }
                    .disabled(!hasDialablePhone(customer.phoneNumber))
                } header: {
                    Text(customer.name.isEmpty ? customer.phoneNumber : "\(customer.name) · \(customer.phoneNumber)")
                } footer: {
                    Text("템플릿 문자는 수신번호와 본문이 입력된 문자 작성창을 엽니다.")
                }

                Section("문자 템플릿") {
                    if state.messageTemplates.isEmpty {
                        Text("설정 탭에서 문자 템플릿을 추가하세요.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.messageTemplates) { template in
                            Button {
                                let body = render(template.body)
                                startMessage(body: body, type: .templateSms, templateId: template.id)
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
        #if os(iOS)
        .sheet(item: $draft) { draft in
            MessageComposeController(
                recipients: [draft.recipient],
                body: draft.body
            ) {
                self.draft = nil
                dismiss()
            }
        }
        #endif
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

    private func startMessage(body: String?, type: ContactLogType, templateId: String?) {
        state.recordContact(
            customer: customer,
            type: type,
            result: .opened,
            messageBody: body,
            templateId: templateId
        )

        let recipient = cleanPhone(customer.phoneNumber)
        #if os(iOS)
        if MFMessageComposeViewController.canSendText() {
            draft = MessageDraft(recipient: recipient, body: body)
            return
        }
        #endif

        openMessagesFallback(recipient: recipient, body: body)
        dismiss()
    }

    private func openMessagesFallback(recipient: String, body: String?) {
        if let body, !body.isEmpty {
            copyToClipboard(body)
        }
        if let url = smsURL(recipient: recipient, body: body) {
            openURL(url)
        }
    }

    private func smsURL(recipient: String, body: String?) -> URL? {
        guard let body, !body.isEmpty else {
            return URL(string: "sms:\(recipient)")
        }
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "sms:\(recipient)&body=\(encoded)")
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

#if os(iOS)
private struct MessageDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let body: String?
}

private struct MessageComposeController: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String?
    let onFinish: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body ?? ""
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
        let onFinish: @MainActor () -> Void

        init(onFinish: @escaping @MainActor () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.onFinish()
            }
        }
    }
}
#endif
