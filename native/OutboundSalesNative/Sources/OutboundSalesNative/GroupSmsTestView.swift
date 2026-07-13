import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum GroupSmsComposeMode: String, CaseIterable, Identifiable {
    case customers = "고객"
    case test = "테스트"

    var id: String { rawValue }
}

private enum GroupSmsTargetScope: String, CaseIterable, Identifiable {
    case selectedList = "현재 리스트"
    case todaySchedule = "오늘 스케줄"
    case visible = "현재 검색 결과"

    var id: String { rawValue }
}

struct GroupSmsTestView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.openURL) private var openURL
    @AppStorage("groupSmsShortcutInstallURL") private var shortcutInstallURLText = ""
    @AppStorage("groupSmsShortcutVerified") private var shortcutVerified = false
    @AppStorage("groupSmsShortcutVerifiedAt") private var shortcutVerifiedAt = ""
    @AppStorage("groupSmsShortcutVerifiedVersion") private var shortcutVerifiedVersion = ""
    @AppStorage("groupSmsAutomationReadiness") private var automationReadinessRaw = GroupSmsAutomationReadiness.notInstalled.rawValue
    @State private var composeMode: GroupSmsComposeMode = .customers
    @State private var targetScope: GroupSmsTargetScope = .selectedList
    @State private var excludedCustomerIds = Set<String>()
    @State private var removesDuplicatePhones = true
    @State private var campaignTitle = "단체문자"
    @State private var selectedTemplateId = ""
    @State private var phoneNumbersText = ""
    @State private var repeatsPerPhone = 3
    @State private var messageTemplate = "소희야 가자 단체문자 테스트 {순번}/{전체}"
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
    @State private var pendingCampaignId = ""
    @State private var showingShortcutTestConfirmation = false

    private var normalizedPhones: [String] {
        GroupSmsBuilder.normalizedPhoneNumbers(phoneNumbersText)
    }

    private var targetCandidates: [Customer] {
        switch targetScope {
        case .selectedList:
            guard let selectedListId = state.selectedListId else { return [] }
            return state.customers.filter { $0.customerListId == selectedListId }
        case .todaySchedule:
            return state.todayScheduledCustomers
        case .visible:
            return state.visibleCustomers
        }
    }

    private var selectedCustomers: [Customer] {
        targetCandidates.filter { !excludedCustomerIds.contains($0.id) && hasDialablePhone($0.phoneNumber) }
    }

    private var currentCustomerIds: Set<String> {
        Set(targetCandidates.map(\.id))
    }

    private var customerTargetSelection: GroupSmsTargetSelectionResult {
        GroupSmsTargetSelector.select(
            targets: targetCandidates.map { customer in
                GroupMessageTarget(
                    sourceRecordId: customer.id,
                    displayName: customer.name,
                    phoneNumber: customer.phoneNumber
                )
            },
            userExcludedSourceRecordIds: excludedCustomerIds,
            removesDuplicatePhones: removesDuplicatePhones
        )
    }

    private var automationReadiness: GroupSmsAutomationReadiness {
        let stored = GroupSmsAutomationReadiness(rawValue: automationReadinessRaw) ?? .notInstalled
        if stored == .ready,
           shortcutVerifiedVersion != Self.transportConfiguration.shortcutVersion {
            return .updateRequired
        }
        return stored
    }

    private var totalCount: Int {
        switch composeMode {
        case .customers:
            return customerTargetSelection.includedTargets.count
        case .test:
            return normalizedPhones.count * max(0, repeatsPerPhone)
        }
    }

    private var policySummary: GroupSmsPolicySummary {
        GroupSmsBuilder.policySummary(totalCount: totalCount)
    }

    private var shortcutInstallURL: URL? {
        let trimmed = shortcutInstallURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("모드", selection: $composeMode) {
                        ForEach(GroupSmsComposeMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(composeMode == .customers ? "고객 데이터를 대상으로 1명씩 개별 문자 요청 payload를 만듭니다." : "내 번호 1개 또는 2개로 단축어 동작을 반복 검증합니다.")
                }

                Section("단축어 설치") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: readinessIcon)
                            .foregroundStyle(readinessColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(readinessTitle)
                                .font(.headline)
                            Text("필수 단축어: \(Self.transportConfiguration.shortcutName) · v\(Self.transportConfiguration.shortcutVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !shortcutVerifiedAt.isEmpty {
                                Text("마지막 확인: \(shortcutVerifiedAt)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    TextField("iCloud 단축어 공유 링크", text: $shortcutInstallURLText, axis: .vertical)

                    Button {
                        openShortcutInstallLink()
                    } label: {
                        Label("단축어 설치하기", systemImage: "square.and.arrow.down")
                    }
                    .disabled(shortcutInstallURL == nil)

                    Button {
                        openShortcutForVerification()
                    } label: {
                        Label("단축어 열기 확인", systemImage: "checkmark.circle")
                    }

                    Button {
                        showingShortcutTestConfirmation = true
                    } label: {
                        Label("본인 번호 텍스트 시험 통과 기록", systemImage: "checkmark.shield")
                    }

                    Button {
                        copyShortcutRecipe()
                    } label: {
                        Label("단축어 구성 안내 복사", systemImage: "doc.on.doc")
                    }

                    Text("앱이 단축어를 자동 설치할 수는 없습니다. 설치 버튼은 Shortcuts 앱의 추가 화면을 열고, 사용자가 직접 단축어 추가를 눌러야 합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if composeMode == .customers {
                    customerTargetSection
                } else {
                    testTargetSection
                }

                Section("메시지") {
                    if composeMode == .customers {
                        Picker("템플릿", selection: $selectedTemplateId) {
                            Text("직접 작성").tag("")
                            ForEach(state.messageTemplates) { template in
                                Text(template.title).tag(template.id)
                            }
                        }
                        .onChange(of: selectedTemplateId) { _, id in
                            guard let template = state.messageTemplates.first(where: { $0.id == id }) else { return }
                            messageTemplate = template.body
                            if campaignTitle == "단체문자" || campaignTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                campaignTitle = template.title
                            }
                        }
                        TextField("캠페인 이름", text: $campaignTitle)
                    }
                    TextEditor(text: $messageTemplate)
                        .frame(minHeight: 90)
                    Text(composeMode == .customers ? "사용 가능: {고객명}, {이름}, {연락처}, {주소}, {메모}, {순번}, {전체}" : "사용 가능: {순번}, {전체}, {번호순번}, {반복}")
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
                        openShortcutForVerification()
                    } label: {
                        Label("단축어만 열기", systemImage: "arrow.up.forward.app")
                    }

                    Button {
                        copyPayloadOnly()
                    } label: {
                        Label("payload만 클립보드에 복사", systemImage: "doc.on.doc")
                    }
                    .disabled(totalCount == 0)

                    Text("단축어 이름은 \(Self.transportConfiguration.shortcutName)입니다. 실제 SMS 최종 도달 여부는 앱이 알 수 없고, 앱에는 발송 요청/콜백 상태만 기록됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !state.groupSmsCampaigns.isEmpty {
                    Section("최근 캠페인") {
                        ForEach(state.groupSmsCampaigns.prefix(5)) { campaign in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(campaign.title)
                                        .font(.headline)
                                    Spacer()
                                    Text(statusText(campaign.status))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(statusColor(campaign.status))
                                }
                                Text("\(campaign.recipients.count)명 · \(campaign.targetDescription)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(campaign.updatedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Section("상태") {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("단체문자")
            .onAppear {
                migrateAutomationReadinessIfNeeded()
                applyDefaultTemplateIfNeeded()
            }
            .alert("텍스트 시험을 통과했습니까?", isPresented: $showingShortcutTestConfirmation) {
                Button("통과로 기록") {
                    markShortcutTextTestPassed()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("본인 번호로 실제 문자를 보내 수신까지 확인한 경우에만 통과로 기록하세요.")
            }
            .confirmationDialog("\(totalCount)건을 Shortcuts로 넘길까요?", isPresented: $showingRunConfirmation) {
                Button("단축어 실행") {
                    runPendingShortcut()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(composeMode == .customers ? "선택한 고객에게 실제 문자 발송 흐름이 시작될 수 있습니다." : "입력한 테스트 번호로 실제 문자 발송 흐름이 시작될 수 있습니다.")
            }
        }
    }

    @ViewBuilder
    private var customerTargetSection: some View {
        Section("발송 대상") {
            Picker("대상 범위", selection: $targetScope) {
                ForEach(GroupSmsTargetScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            Toggle("중복 전화번호 제거", isOn: $removesDuplicatePhones)
            LabeledContent("후보 고객", value: "\(targetCandidates.count)명")
            LabeledContent("발송 가능", value: "\(customerTargetSelection.includedTargets.count)명")
            HStack(spacing: 10) {
                Button {
                    excludedCustomerIds.subtract(currentCustomerIds)
                } label: {
                    Label("전체 선택", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(currentCustomerIds.isDisjoint(with: excludedCustomerIds))

                Button {
                    excludedCustomerIds.formUnion(currentCustomerIds)
                } label: {
                    Label("전체 해제", systemImage: "circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(currentCustomerIds.isEmpty || currentCustomerIds.isSubset(of: excludedCustomerIds))
            }
            if customerTargetSelection.excludedTargets.isEmpty == false {
                LabeledContent("사용자 제외", value: "\(customerTargetSelection.excludedCount(for: .userExcluded))명")
                LabeledContent("번호 없음/오류", value: "\(customerTargetSelection.excludedCount(for: .missingOrInvalidPhone))명")
                LabeledContent("중복 번호", value: "\(customerTargetSelection.excludedCount(for: .duplicatePhone))명")
            }
            if targetCandidates.isEmpty {
                Text("선택한 범위에 고객이 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(targetCandidates.prefix(80)) { customer in
                    Toggle(isOn: customerSelectionBinding(customer)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                                .font(.headline)
                            Text([customer.phoneNumber, customer.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .disabled(!hasDialablePhone(customer.phoneNumber))
                }
                if targetCandidates.count > 80 {
                    Text("화면 성능을 위해 앞 80명만 개별 제외를 표시합니다. 전체 대상은 범위 기준으로 포함됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var testTargetSection: some View {
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

    private func customerSelectionBinding(_ customer: Customer) -> Binding<Bool> {
        Binding(
            get: { !excludedCustomerIds.contains(customer.id) },
            set: { isSelected in
                if isSelected {
                    excludedCustomerIds.remove(customer.id)
                } else {
                    excludedCustomerIds.insert(customer.id)
                }
            }
        )
    }

    private func buildRecipients() throws -> [GroupSmsRecipient] {
        switch composeMode {
        case .customers:
            return try GroupSmsBuilder.buildCustomerRecipients(
                customers: selectedCustomers,
                messageTemplate: messageTemplate,
                delaySettings: currentDelaySettings(),
                removesDuplicatePhones: removesDuplicatePhones
            )
        case .test:
            return try GroupSmsBuilder.buildTestRecipients(
                input: GroupSmsTestInput(
                    phoneNumbers: normalizedPhones,
                    repeatsPerPhone: repeatsPerPhone,
                    messageTemplate: messageTemplate,
                    delaySettings: currentDelaySettings()
                )
            )
        }
    }

    private func buildPreview() {
        do {
            lastRecipients = try buildRecipients()
            statusMessage = "\(lastRecipients.count)건의 발송 목록을 만들었습니다."
        } catch {
            lastRecipients = []
            statusMessage = errorMessage(error)
        }
    }

    private func prepareShortcutRun() {
        guard automationReadiness == .ready else {
            statusMessage = "단축어 텍스트 시험을 먼저 완료하세요. 현재 상태: \(readinessTitle)"
            return
        }
        do {
            let recipients = try buildRecipients()
            let campaignId = UUID().uuidString
            let title = resolvedCampaignTitle()
            let payload = GroupSmsBuilder.makePayload(configuration: Self.transportConfiguration, campaignId: campaignId, campaignTitle: title, recipients: recipients)
            pendingPayloadJSON = try GroupSmsBuilder.encodePayload(payload)
            pendingShortcutURL = GroupSmsBuilder.shortcutsRunURL(configuration: Self.transportConfiguration, campaignId: payload.campaignId)
            pendingCampaignId = campaignId
            lastRecipients = recipients
            state.saveGroupSmsCampaign(
                id: campaignId,
                title: title,
                customerListId: composeMode == .customers ? state.selectedListId : nil,
                targetDescription: targetDescription(),
                messageTemplate: messageTemplate,
                recipients: recipients,
                status: .ready
            )
            showingRunConfirmation = true
        } catch {
            statusMessage = errorMessage(error)
        }
    }

    private func copyPayloadOnly() {
        do {
            let recipients = try buildRecipients()
            let payload = GroupSmsBuilder.makePayload(configuration: Self.transportConfiguration, campaignTitle: resolvedCampaignTitle(), recipients: recipients)
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
        if !pendingCampaignId.isEmpty {
            state.markGroupSmsCampaign(pendingCampaignId, status: .shortcutOpened)
        }
        openURL(pendingShortcutURL) { accepted in
            if accepted {
                statusMessage = "Shortcuts를 열었습니다. 단축어에서 발송 흐름을 확인하세요."
            } else {
                if !pendingCampaignId.isEmpty {
                    state.markGroupSmsCampaign(pendingCampaignId, status: .shortcutFailed)
                }
                statusMessage = "Shortcuts를 열지 못했습니다."
            }
        }
    }

    private func openShortcutInstallLink() {
        guard let shortcutInstallURL else {
            statusMessage = "단축어 설치 링크를 입력하세요."
            return
        }
        openURL(shortcutInstallURL) { accepted in
            statusMessage = accepted ? "Shortcuts 설치 화면을 열었습니다. 단축어 추가를 누른 뒤 앱으로 돌아와 설치 확인 테스트를 실행하세요." : "설치 링크를 열지 못했습니다."
        }
    }

    private func openShortcutForVerification() {
        guard let url = GroupSmsBuilder.shortcutsOpenURL(configuration: Self.transportConfiguration) else {
            statusMessage = "단축어 확인 URL을 만들지 못했습니다."
            return
        }
        openURL(url) { accepted in
            if accepted {
                shortcutVerified = false
                automationReadinessRaw = GroupSmsAutomationReadiness.installedNeedsTest.rawValue
                statusMessage = "\(Self.transportConfiguration.shortcutName) 단축어 열기를 요청했습니다. 열기 성공은 설치 확인일 뿐 실제 문자 권한 시험 완료를 뜻하지 않습니다."
            } else {
                shortcutVerified = false
                automationReadinessRaw = GroupSmsAutomationReadiness.notInstalled.rawValue
                statusMessage = "Shortcuts에서 \(Self.transportConfiguration.shortcutName) 단축어를 열지 못했습니다. 설치 링크로 먼저 추가하세요."
            }
        }
    }

    private func markShortcutTextTestPassed() {
        shortcutVerified = true
        shortcutVerifiedAt = Self.statusDateFormatter.string(from: Date())
        shortcutVerifiedVersion = Self.transportConfiguration.shortcutVersion
        automationReadinessRaw = GroupSmsAutomationReadiness.ready.rawValue
        statusMessage = "본인 번호 텍스트 시험 통과를 기록했습니다."
    }

    private func migrateAutomationReadinessIfNeeded() {
        guard shortcutVerified,
              automationReadinessRaw == GroupSmsAutomationReadiness.notInstalled.rawValue else { return }
        shortcutVerifiedVersion = shortcutVerifiedVersion.isEmpty
            ? Self.transportConfiguration.shortcutVersion
            : shortcutVerifiedVersion
        automationReadinessRaw = GroupSmsAutomationReadiness.ready.rawValue
    }

    private func copyShortcutRecipe() {
        copyToClipboard(Self.shortcutRecipe)
        statusMessage = "단축어 구성 안내를 클립보드에 복사했습니다."
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
            case .noRecipients:
                return "발송 가능한 고객이 없습니다."
            }
        }
        return "테스트 payload를 만들지 못했습니다."
    }

    private func applyDefaultTemplateIfNeeded() {
        guard selectedTemplateId.isEmpty, messageTemplate.hasPrefix("소희야 가자 단체문자 테스트") else { return }
        if let template = state.messageTemplates.first(where: { $0.isDefault }) ?? state.messageTemplates.first {
            selectedTemplateId = template.id
            messageTemplate = template.body
            campaignTitle = template.title
        }
    }

    private func resolvedCampaignTitle() -> String {
        let trimmed = campaignTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return composeMode == .customers ? "고객 단체문자" : "반복 테스트"
    }

    private func targetDescription() -> String {
        switch composeMode {
        case .customers:
            return "\(targetScope.rawValue) · \(customerTargetSelection.includedTargets.count)명"
        case .test:
            return "반복 테스트 · \(normalizedPhones.count)개 번호"
        }
    }

    private func statusText(_ status: GroupSmsCampaignStatus) -> String {
        switch status {
        case .draft: return "임시"
        case .ready: return "준비"
        case .scheduled: return "예약"
        case .due: return "발송대기"
        case .shortcutOpened: return "실행"
        case .requested: return "요청완료"
        case .cancelled: return "취소"
        case .shortcutFailed: return "오류"
        case .unknown: return "미확인"
        }
    }

    private func statusColor(_ status: GroupSmsCampaignStatus) -> Color {
        switch status {
        case .requested:
            return .green
        case .cancelled, .shortcutFailed:
            return .red
        case .shortcutOpened, .ready, .scheduled, .due:
            return .orange
        case .draft, .unknown:
            return .secondary
        }
    }

    private var readinessTitle: String {
        switch automationReadiness {
        case .notInstalled: return "단축어 미설치"
        case .installedNeedsTest: return "설치됨 · 텍스트 시험 필요"
        case .messagePermissionRequired: return "문자 권한 필요"
        case .attachmentPermissionRequired: return "첨부 권한 필요"
        case .ready: return "텍스트 자동화 사용 가능"
        case .updateRequired: return "단축어 업데이트 필요"
        case .unavailable: return "이 기기에서 사용 불가"
        }
    }

    private var readinessIcon: String {
        switch automationReadiness {
        case .ready: return "checkmark.seal.fill"
        case .notInstalled, .unavailable: return "xmark.octagon.fill"
        case .installedNeedsTest, .messagePermissionRequired, .attachmentPermissionRequired, .updateRequired:
            return "exclamationmark.triangle.fill"
        }
    }

    private var readinessColor: Color {
        switch automationReadiness {
        case .ready: return .green
        case .notInstalled, .unavailable: return .red
        case .installedNeedsTest, .messagePermissionRequired, .attachmentPermissionRequired, .updateRequired:
            return .orange
        }
    }

    private static let statusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let transportConfiguration = SoheeGroupSmsProductConfiguration.transport

    private static let shortcutRecipe = """
    SoheeGroupSMS 단축어 v\(transportConfiguration.shortcutVersion)

    목적:
    - 소희야 가자 앱이 클립보드에 저장한 JSON payload를 읽는다.
    - recipients 배열을 순회하며 각 항목을 1명씩 개별 문자로 발송한다.
    - 각 항목의 plannedDelaySeconds 만큼 대기한다.
    - 완료/취소/오류 시 앱 callback URL을 연다.

    단축어 이름:
    \(transportConfiguration.shortcutName)

    한글 iPhone 기준 액션 이름:
    - Dictionary는 한글 단축어에서 "사전"으로 표시된다.
    - "딕셔너리 값 가져오기"가 아니라 "사전 값 가져오기" 또는 "사전에서 값 가져오기"를 찾는다.

    권장 액션 순서:
    1. "클립보드 가져오기"
       - 결과를 PayloadText라고 생각하면 된다.

    2. "입력에서 사전 가져오기" 또는 "JSON에서 사전 가져오기"
       - 입력은 1번의 클립보드 값이다.
       - 결과를 Payload라고 생각하면 된다.

    3. Payload에서 값 꺼내기
       "사전 값 가져오기" 액션을 5개 추가한다.
       각 액션에서 사전은 Payload를 선택하고, 키에는 아래 값을 직접 입력한다.
       - 키 campaignId -> 결과 CampaignId
       - 키 callbackScheme -> 결과 CallbackScheme
       - 키 successPath -> 결과 SuccessPath
       - 키 errorPath -> 결과 ErrorPath
       - 키 recipients -> 결과 Recipients

    4. "각 항목 반복"
       - 반복 대상은 Recipients

    5. 반복 안에서 현재 반복 항목 값 꺼내기
       "사전 값 가져오기" 액션을 반복 안에 3개 추가한다.
       각 액션에서 사전은 Payload가 아니라 "반복 항목"을 선택한다.
       - 키 phoneNumber -> 결과 PhoneNumber
       - 키 messageBody -> 결과 MessageBody
       - 키 plannedDelaySeconds -> 결과 DelaySeconds

    6. 반복 안에서 "메시지 보내기"
       - 메시지: MessageBody
       - 수신자: PhoneNumber
       - 수신자는 반드시 1명만 지정
       - 한글판에서 "받는 사람"을 길게 누르고 "변수 선택"으로 PhoneNumber를 지정
       - "실행 시 보기" 또는 작성 화면 표시 옵션은 끔
       - 검증 완료 후 반복 안의 "텍스트"와 "알림 보기"는 제거

    7. 반복 안에서 DelaySeconds가 0보다 크면 "대기"
       - 대기 시간: DelaySeconds초

    8. 반복이 모두 끝난 뒤 URL 열기
       - URL 텍스트: com.lucid47.outboundsales:/group-sms/complete?campaignId=CampaignId
       - 액션: URL 열기
    """
}
