import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GroupSmsTestView: View {
    @Environment(\.openURL) private var openURL
    @State private var phoneNumbersText = ""
    @State private var repeatsPerPhone = 3
    @State private var messageTemplate = "소희가 간다 단체문자 테스트 {순번}/{전체}"
    @State private var delayMode: GroupSmsDelayMode = .off
    @State private var fixedDelaySeconds = 1
    @State private var minDelaySeconds = 1
    @State private var maxDelaySeconds = 3
    @State private var batchRestEnabled = false
    @State private var batchSize = 50
    @State private var batchMinRestSeconds = 30
    @State private var batchMaxRestSeconds = 60
    @State private var lastRecipients: [GroupSmsRecipient] = []
    @State private var statusMessage = ""
    @State private var showingRunConfirmation = false
    @State private var pendingPayloadJSON = ""
    @State private var pendingShortcutURL: URL?

    private var normalizedPhones: [String] {
        GroupSmsBuilder.normalizedPhoneNumbers(phoneNumbersText)
    }

    private var totalCount: Int {
        normalizedPhones.count * max(0, repeatsPerPhone)
    }

    private var policySummary: GroupSmsPolicySummary {
        GroupSmsBuilder.policySummary(totalCount: totalCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("테스트 수신번호") {
                    TextField("01012345678, 01098765432", text: $phoneNumbersText, axis: .vertical)
                    Stepper("번호당 반복 \(repeatsPerPhone)회", value: $repeatsPerPhone, in: 1...100)
                    LabeledContent("총 발송 요청", value: "\(totalCount)건")
                    if normalizedPhones.isEmpty {
                        Text("테스트할 내 번호 1개 또는 2개를 입력하세요. 쉼표, 공백, 줄바꿈으로 구분할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(normalizedPhones.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("메시지") {
                    TextEditor(text: $messageTemplate)
                        .frame(minHeight: 90)
                    Text("사용 가능: {순번}, {전체}, {번호순번}, {반복}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("발송 간격") {
                    Picker("딜레이", selection: $delayMode) {
                        Text("꺼짐").tag(GroupSmsDelayMode.off)
                        Text("고정").tag(GroupSmsDelayMode.fixed)
                        Text("랜덤").tag(GroupSmsDelayMode.random)
                    }
                    .pickerStyle(.segmented)

                    if delayMode == .fixed {
                        Stepper("고정 \(fixedDelaySeconds)초", value: $fixedDelaySeconds, in: 0...30)
                    }

                    if delayMode == .random {
                        Stepper("최소 \(minDelaySeconds)초", value: $minDelaySeconds, in: 0...30)
                        Stepper("최대 \(maxDelaySeconds)초", value: $maxDelaySeconds, in: 0...30)
                    }

                    Toggle("묶음 휴식", isOn: $batchRestEnabled)
                    if batchRestEnabled {
                        Stepper("\(batchSize)건마다 휴식", value: $batchSize, in: 5...200, step: 5)
                        Stepper("휴식 최소 \(batchMinRestSeconds)초", value: $batchMinRestSeconds, in: 0...600, step: 10)
                        Stepper("휴식 최대 \(batchMaxRestSeconds)초", value: $batchMaxRestSeconds, in: 0...600, step: 10)
                    }

                    Text("딜레이를 꺼도 Shortcuts와 메시지앱 처리 과정에서 자연 지연이 생길 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("SKT 보호선") {
                    LabeledContent("권장 보호선", value: "\(policySummary.recommendedDailyLimit)건/일")
                    LabeledContent("일 최대 제한", value: "\(policySummary.dailyLimit)건/일")
                    if let warning = policySummary.warning {
                        Label(warning, systemImage: policySummary.isBlocked ? "xmark.octagon" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(policySummary.isBlocked ? .red : .orange)
                    } else {
                        Label("현재 테스트 건수는 200건 보호선 안에 있습니다.", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Section("미리보기") {
                    Button {
                        buildPreview()
                    } label: {
                        Label("테스트 발송 목록 만들기", systemImage: "list.bullet.rectangle")
                    }

                    if !lastRecipients.isEmpty {
                        ForEach(lastRecipients.prefix(8)) { recipient in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(recipient.orderIndex + 1). \(recipient.phoneNumber)")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(recipient.plannedDelaySeconds)초 후")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(recipient.messageBody)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if lastRecipients.count > 8 {
                            Text("외 \(lastRecipients.count - 8)건")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Shortcuts 실행") {
                    Button {
                        prepareShortcutRun()
                    } label: {
                        Label("클립보드에 payload 저장 후 단축어 실행", systemImage: "paperplane")
                    }
                    .disabled(totalCount == 0 || policySummary.isBlocked)

                    Button {
                        copyPayloadOnly()
                    } label: {
                        Label("payload만 클립보드에 복사", systemImage: "doc.on.doc")
                    }
                    .disabled(totalCount == 0)

                    Text("단축어 이름은 \(GroupSmsBuilder.shortcutName)입니다. 설치 전에는 실행 버튼을 눌러도 Shortcuts 앱에서 오류가 날 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !statusMessage.isEmpty {
                    Section("상태") {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("단체문자 검증")
            .confirmationDialog("테스트 문자 \(totalCount)건을 Shortcuts로 넘길까요?", isPresented: $showingRunConfirmation) {
                Button("단축어 실행") {
                    runPendingShortcut()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("입력한 테스트 번호로 실제 문자 발송 흐름이 시작될 수 있습니다.")
            }
        }
    }

    private func currentDelaySettings() -> GroupSmsDelaySettings {
        GroupSmsDelaySettings(
            mode: delayMode,
            fixedDelaySeconds: fixedDelaySeconds,
            minDelaySeconds: minDelaySeconds,
            maxDelaySeconds: maxDelaySeconds,
            batchRestEnabled: batchRestEnabled,
            batchSize: batchSize,
            batchMinRestSeconds: batchMinRestSeconds,
            batchMaxRestSeconds: batchMaxRestSeconds
        )
    }

    private func buildRecipients() throws -> [GroupSmsRecipient] {
        try GroupSmsBuilder.buildTestRecipients(
            input: GroupSmsTestInput(
                phoneNumbers: normalizedPhones,
                repeatsPerPhone: repeatsPerPhone,
                messageTemplate: messageTemplate,
                delaySettings: currentDelaySettings()
            )
        )
    }

    private func buildPreview() {
        do {
            lastRecipients = try buildRecipients()
            statusMessage = "\(lastRecipients.count)건의 테스트 발송 목록을 만들었습니다."
        } catch {
            lastRecipients = []
            statusMessage = errorMessage(error)
        }
    }

    private func prepareShortcutRun() {
        do {
            let recipients = try buildRecipients()
            let payload = GroupSmsBuilder.makePayload(campaignTitle: "반복 테스트", recipients: recipients)
            pendingPayloadJSON = try GroupSmsBuilder.encodePayload(payload)
            pendingShortcutURL = GroupSmsBuilder.shortcutsRunURL(campaignId: payload.campaignId)
            lastRecipients = recipients
            showingRunConfirmation = true
        } catch {
            statusMessage = errorMessage(error)
        }
    }

    private func copyPayloadOnly() {
        do {
            let recipients = try buildRecipients()
            let payload = GroupSmsBuilder.makePayload(campaignTitle: "반복 테스트", recipients: recipients)
            let json = try GroupSmsBuilder.encodePayload(payload)
            copyToClipboard(json)
            lastRecipients = recipients
            statusMessage = "payload를 클립보드에 복사했습니다."
        } catch {
            statusMessage = errorMessage(error)
        }
    }

    private func runPendingShortcut() {
        guard let pendingShortcutURL else {
            statusMessage = "단축어 실행 URL을 만들지 못했습니다."
            return
        }
        copyToClipboard(pendingPayloadJSON)
        openURL(pendingShortcutURL) { accepted in
            statusMessage = accepted ? "Shortcuts를 열었습니다. 단축어에서 발송 흐름을 확인하세요." : "Shortcuts를 열지 못했습니다."
        }
    }

    private func copyToClipboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }

    private func errorMessage(_ error: Error) -> String {
        if let builderError = error as? GroupSmsBuilderError {
            switch builderError {
            case .noPhoneNumbers:
                return "발송 가능한 테스트 번호가 없습니다."
            case .invalidRepeatCount:
                return "반복 횟수를 확인하세요."
            case .emptyMessage:
                return "메시지 본문을 입력하세요."
            }
        }
        return "테스트 payload를 만들지 못했습니다."
    }
}
