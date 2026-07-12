import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum GroupSmsCampaignStep: Int, CaseIterable {
    case targets
    case message
    case review

    var title: String {
        switch self {
        case .targets: return "대상"
        case .message: return "메시지"
        case .review: return "확인"
        }
    }

    var icon: String {
        switch self {
        case .targets: return "person.2.fill"
        case .message: return "message.fill"
        case .review: return "checkmark.shield.fill"
        }
    }
}

enum GroupSmsCampaignTargetScope: String, CaseIterable, Identifiable {
    case selectedList = "현재 리스트"
    case todaySchedule = "오늘"
    case visible = "검색 결과"

    var id: String { rawValue }
}

struct GroupSmsCampaignView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.openURL) private var openURL
    @AppStorage("groupSmsShortcutVerified") private var legacyShortcutVerified = false
    @AppStorage("groupSmsShortcutVerifiedAt") private var shortcutVerifiedAt = ""
    @AppStorage("groupSmsShortcutVerifiedVersion") private var shortcutVerifiedVersion = ""
    @AppStorage("groupSmsAutomationReadiness") private var automationReadinessRaw = GroupSmsAutomationReadiness.notInstalled.rawValue

    @State private var step: GroupSmsCampaignStep = .targets
    @State private var targetScope: GroupSmsCampaignTargetScope = .selectedList
    @State private var excludedCustomerIds = Set<String>()
    @State private var removesDuplicatePhones = true
    @State private var campaignTitle = "단체문자"
    @State private var selectedTemplateId = ""
    @State private var messageTemplate = ""
    @State private var delayMode: GroupSmsDelayMode = .off
    @State private var fixedDelaySeconds = 1
    @State private var minDelaySeconds = 2
    @State private var maxDelaySeconds = 6
    @State private var showingDelaySettings = false
    @State private var showingDiagnostics = false
    @State private var showingLaunchConfirmation = false
    @State private var currentCampaignId = ""
    @State private var statusMessage = ""

    init(initialTargetScope: GroupSmsCampaignTargetScope = .selectedList) {
        _targetScope = State(initialValue: initialTargetScope)
    }

    private static let transportConfiguration = SoheeGroupSmsProductConfiguration.transport

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

    private var messageTargets: [GroupMessageTarget] {
        targetCandidates.map { customer in
            GroupMessageTarget(
                sourceRecordId: customer.id,
                displayName: customer.name,
                phoneNumber: customer.phoneNumber,
                mergeFields: [
                    "고객명": customer.name,
                    "이름": customer.name,
                    "연락처": customer.phoneNumber,
                    "주소": customer.address,
                    "메모": customer.notes
                ],
                sourceMetadata: ["customerListId": customer.customerListId]
            )
        }
    }

    private var selection: GroupSmsTargetSelectionResult {
        GroupSmsTargetSelector.select(
            targets: messageTargets,
            userExcludedSourceRecordIds: excludedCustomerIds,
            removesDuplicatePhones: removesDuplicatePhones
        )
    }

    private var delaySettings: GroupSmsDelaySettings {
        GroupSmsDelaySettings(
            mode: delayMode,
            fixedDelaySeconds: fixedDelaySeconds,
            minDelaySeconds: minDelaySeconds,
            maxDelaySeconds: maxDelaySeconds
        )
    }

    private var recipients: [GroupSmsRecipient] {
        (try? GroupSmsBuilder.buildRecipients(
            targets: selection.includedTargets,
            messageTemplate: messageTemplate,
            delaySettings: delaySettings,
            removesDuplicatePhones: false
        )) ?? []
    }

    private var automationReadiness: GroupSmsAutomationReadiness {
        let stored = GroupSmsAutomationReadiness(rawValue: automationReadinessRaw) ?? .notInstalled
        if stored == .ready,
           shortcutVerifiedVersion != Self.transportConfiguration.shortcutVersion {
            return .updateRequired
        }
        return stored
    }

    private var preflight: GroupSmsPreflightSummary {
        GroupSmsPreflightEvaluator.evaluate(
            selection: selection,
            recipients: recipients,
            messageTemplate: messageTemplate,
            attachments: [],
            automationReadiness: automationReadiness,
            sentTodayCount: sentTodayCount
        )
    }

    private var sentTodayCount: Int {
        state.groupSmsCampaigns.reduce(0) { count, campaign in
            guard let requestedAt = campaign.requestedAt,
                  Calendar.current.isDateInToday(requestedAt) else { return count }
            return count + campaign.recipients.count
        }
    }

    private var currentCampaign: GroupSmsCampaign? {
        state.groupSmsCampaigns.first { $0.id == currentCampaignId }
    }

    private var isRunning: Bool {
        currentCampaign?.status == .shortcutOpened
    }

    private var hasResult: Bool {
        guard let status = currentCampaign?.status else { return false }
        return status == .requested || status == .cancelled || status == .shortcutFailed || status == .unknown
    }

    var body: some View {
        ZStack {
            AppPalette.pageBackground.ignoresSafeArea()

            if isRunning {
                runningView
            } else if hasResult {
                resultView
            } else {
                campaignBuilder
            }
        }
        .navigationTitle("단체문자")
        .groupSmsCompactNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingDiagnostics = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .help("자동화 설정 및 진단")
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            GroupSmsTestView()
                .environmentObject(state)
        }
        .confirmationDialog("\(recipients.count)명에게 발송 요청을 시작할까요?", isPresented: $showingLaunchConfirmation) {
            Button("발송 시작") {
                launchCampaign()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 수신자는 한 명씩 개별 메시지로 처리됩니다.")
        }
        .onAppear {
            migrateReadinessIfNeeded()
            applyDefaultTemplateIfNeeded()
        }
    }

    private var campaignBuilder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                readinessBanner
                stepIndicator

                switch step {
                case .targets:
                    targetStep
                case .message:
                    messageStep
                case .review:
                    reviewStep
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 104)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            bottomCommandBar
        }
    }

    private var readinessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: readinessIcon)
                .font(.title2)
                .foregroundStyle(readinessColor)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(readinessTitle)
                    .font(.headline)
                    .foregroundStyle(AppPalette.textPrimary)
                Text(readinessSubtitle)
                    .font(.caption)
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if automationReadiness != .ready {
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("준비", systemImage: "wrench.and.screwdriver")
                        .frame(minWidth: 78, minHeight: 46)
                }
                .buttonStyle(GroupSmsPrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(AppPalette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(readinessColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(GroupSmsCampaignStep.allCases, id: \.rawValue) { item in
                Button {
                    if item.rawValue <= step.rawValue {
                        step = item
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                        Text(item.title)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(item == step ? .white : item.rawValue < step.rawValue ? Color.accentColor : AppPalette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(item == step ? Color.accentColor : AppPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(item.rawValue < step.rawValue ? Color.accentColor.opacity(0.45) : AppPalette.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(item.rawValue > step.rawValue)
            }
        }
    }

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("누구에게 보낼까요?", detail: state.selectedList?.name ?? "고객리스트를 먼저 선택하세요")

            Picker("대상 범위", selection: $targetScope) {
                ForEach(GroupSmsCampaignTargetScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                metricCard("후보", value: selection.totalCandidateCount, color: .blue)
                metricCard("발송", value: selection.includedTargets.count, color: .green)
                metricCard("제외", value: selection.excludedTargets.count, color: .orange)
            }

            Toggle("중복 전화번호 한 번만 보내기", isOn: $removesDuplicatePhones)
                .font(.headline)
                .padding(.vertical, 4)

            if targetCandidates.isEmpty {
                emptyState("선택한 범위에 고객이 없습니다.", icon: "person.crop.circle.badge.xmark")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 8)], spacing: 8) {
                    ForEach(targetCandidates) { customer in
                        customerSelectionRow(customer)
                    }
                }
            }
        }
    }

    private var messageStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("메시지를 작성하세요", detail: "\(selection.includedTargets.count)명에게 각각 전송")

            VStack(alignment: .leading, spacing: 12) {
                TextField("캠페인 이름", text: $campaignTitle)
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)

                Picker("문자 템플릿", selection: $selectedTemplateId) {
                    Text("직접 작성").tag("")
                    ForEach(state.messageTemplates) { template in
                        Text(template.title).tag(template.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTemplateId) { _, id in
                    guard let template = state.messageTemplates.first(where: { $0.id == id }) else { return }
                    messageTemplate = template.body
                    if campaignTitle == "단체문자" || campaignTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        campaignTitle = template.title
                    }
                }

                TextEditor(text: $messageTemplate)
                    .font(.body)
                    .frame(minHeight: 180)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(AppPalette.pageBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppPalette.hairline, lineWidth: 1)
                    )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["{고객명}", "{연락처}", "{주소}", "{순번}", "{전체}"], id: \.self) { token in
                            Button(token) {
                                appendMergeToken(token)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(14)
            .background(AppPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            DisclosureGroup("발송 간격", isExpanded: $showingDelaySettings) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("간격", selection: $delayMode) {
                        Text("꺼짐").tag(GroupSmsDelayMode.off)
                        Text("고정").tag(GroupSmsDelayMode.fixed)
                        Text("랜덤").tag(GroupSmsDelayMode.random)
                    }
                    .pickerStyle(.segmented)

                    if delayMode == .fixed {
                        Stepper("메시지 사이 \(fixedDelaySeconds)초", value: $fixedDelaySeconds, in: 0...30)
                    } else if delayMode == .random {
                        Stepper("최소 \(minDelaySeconds)초", value: $minDelaySeconds, in: 0...30)
                        Stepper("최대 \(maxDelaySeconds)초", value: $maxDelaySeconds, in: 0...30)
                    }
                }
                .padding(.top, 12)
            }
            .font(.headline)
            .padding(14)
            .background(AppPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("마지막으로 확인하세요", detail: campaignTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "단체문자" : campaignTitle)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                metricCard("발송", value: recipients.count, color: .green)
                metricTextCard("형식", value: messageKindText, color: .indigo)
                metricTextCard("예상", value: durationText, color: .orange)
            }

            if preflight.blockingReasons.isEmpty == false || selection.excludedTargets.isEmpty == false {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(preflight.blockingReasons, id: \.rawValue) { reason in
                        Label(blockingReasonText(reason), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    if selection.excludedTargets.isEmpty == false {
                        Label("제외 고객 \(selection.excludedTargets.count)명", systemImage: "person.crop.circle.badge.minus")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("메시지 미리보기")
                    .font(.headline)
                ForEach(recipients.prefix(3)) { recipient in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipient.displayName)
                            .font(.headline)
                        Text(recipient.messageBody)
                            .font(.body)
                            .foregroundStyle(AppPalette.textSecondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 6)
                    if recipient.id != recipients.prefix(3).last?.id {
                        Divider()
                    }
                }
                if recipients.count > 3 {
                    Text("외 \(recipients.count - 3)명")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var bottomCommandBar: some View {
        HStack(spacing: 10) {
            if step != .targets {
                Button {
                    step = GroupSmsCampaignStep(rawValue: step.rawValue - 1) ?? .targets
                } label: {
                    Label("이전", systemImage: "chevron.left")
                        .frame(minWidth: 74, minHeight: 54)
                }
                .buttonStyle(GroupSmsSecondaryButtonStyle())
            }

            Button {
                advance()
            } label: {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(GroupSmsPrimaryButtonStyle())
            .disabled(primaryButtonDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var runningView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("발송 요청 진행 중")
                .font(.title2.weight(.bold))
            Text("\(currentCampaign?.recipients.count ?? recipients.count)명을 Shortcuts에서 처리하고 있습니다.")
                .font(.headline)
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
            Text("앱에는 확인 가능한 요청 상태만 기록됩니다.")
                .font(.caption)
                .foregroundStyle(AppPalette.textSecondary)
            Button("자동화 진단") {
                showingDiagnostics = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Spacer()
        }
        .padding(24)
    }

    private var resultView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: resultIcon)
                .font(.system(size: 52))
                .foregroundStyle(resultColor)
            Text(resultTitle)
                .font(.title2.weight(.bold))
            Text("\(currentCampaign?.recipients.count ?? 0)명 · \(currentCampaign?.title ?? "단체문자")")
                .font(.headline)
                .foregroundStyle(AppPalette.textSecondary)
            Text("이 화면은 통신사 최종 전달 여부가 아니라 Shortcuts 요청 결과입니다.")
                .font(.caption)
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                resetCampaign()
            } label: {
                Label("새 캠페인", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: 320, minHeight: 54)
            }
            .buttonStyle(GroupSmsPrimaryButtonStyle())
            Spacer()
        }
        .padding(24)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(AppPalette.textPrimary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .lineLimit(2)
        }
    }

    private func metricCard(_ title: String, value: Int, color: Color) -> some View {
        metricTextCard(title, value: "\(value)", color: color)
    }

    private func metricTextCard(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 12)
        .background(AppPalette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppPalette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(AppPalette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func customerSelectionRow(_ customer: Customer) -> some View {
        let exclusion = selection.excludedTargets.first { $0.target.sourceRecordId == customer.id }
        let isManualExclusion = exclusion?.reason == .userExcluded
        let isUnavailable = exclusion != nil && !isManualExclusion
        let isSelected = exclusion == nil

        return Button {
            guard !isUnavailable else { return }
            if excludedCustomerIds.contains(customer.id) {
                excludedCustomerIds.remove(customer.id)
            } else {
                excludedCustomerIds.insert(customer.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : isUnavailable ? "xmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : isUnavailable ? .orange : AppPalette.textSecondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(1)
                    Text(customer.phoneNumber.isEmpty ? "연락처 없음" : customer.phoneNumber)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                }

                Spacer(minLength: 8)

                if let exclusion {
                    Text(exclusionText(exclusion.reason))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(AppPalette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : AppPalette.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
    }

    private func advance() {
        switch step {
        case .targets:
            step = .message
        case .message:
            step = .review
        case .review:
            statusMessage = ""
            showingLaunchConfirmation = true
        }
    }

    private func launchCampaign() {
        guard preflight.canLaunch else {
            statusMessage = preflight.blockingReasons.map(blockingReasonText).joined(separator: " · ")
            return
        }

        let campaignId = UUID().uuidString
        let title = campaignTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "단체문자" : campaignTitle
        let payload = GroupSmsBuilder.makePayload(
            configuration: Self.transportConfiguration,
            campaignId: campaignId,
            campaignTitle: title,
            recipients: recipients
        )

        do {
            let json = try GroupSmsBuilder.encodePayload(payload)
            guard let url = GroupSmsBuilder.shortcutsRunURL(
                configuration: Self.transportConfiguration,
                campaignId: campaignId
            ) else {
                statusMessage = "단축어 실행 URL을 만들지 못했습니다."
                return
            }

            state.saveGroupSmsCampaign(
                id: campaignId,
                title: title,
                customerListId: state.selectedListId,
                targetDescription: "\(targetScope.rawValue) · \(recipients.count)명",
                messageTemplate: messageTemplate,
                recipients: recipients,
                status: .ready
            )
            currentCampaignId = campaignId
            copyToClipboard(json)
            state.markGroupSmsCampaign(campaignId, status: .shortcutOpened)
            openURL(url) { accepted in
                if !accepted {
                    state.markGroupSmsCampaign(campaignId, status: .shortcutFailed)
                    statusMessage = "Shortcuts를 열지 못했습니다."
                }
            }
        } catch {
            statusMessage = "발송 payload를 만들지 못했습니다."
        }
    }

    private func appendMergeToken(_ token: String) {
        if messageTemplate.isEmpty || messageTemplate.hasSuffix(" ") || messageTemplate.hasSuffix("\n") {
            messageTemplate.append(token)
        } else {
            messageTemplate.append(" \(token)")
        }
    }

    private func applyDefaultTemplateIfNeeded() {
        guard messageTemplate.isEmpty else { return }
        if let template = state.messageTemplates.first(where: { $0.isDefault }) ?? state.messageTemplates.first {
            selectedTemplateId = template.id
            messageTemplate = template.body
            campaignTitle = template.title
        }
    }

    private func migrateReadinessIfNeeded() {
        guard legacyShortcutVerified,
              automationReadinessRaw == GroupSmsAutomationReadiness.notInstalled.rawValue else { return }
        shortcutVerifiedVersion = shortcutVerifiedVersion.isEmpty
            ? Self.transportConfiguration.shortcutVersion
            : shortcutVerifiedVersion
        automationReadinessRaw = GroupSmsAutomationReadiness.ready.rawValue
    }

    private func resetCampaign() {
        currentCampaignId = ""
        excludedCustomerIds = []
        step = .targets
        statusMessage = ""
    }

    private func copyToClipboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }

    private var primaryButtonTitle: String {
        switch step {
        case .targets: return "메시지 작성"
        case .message: return "발송 전 확인"
        case .review: return "발송 시작"
        }
    }

    private var primaryButtonIcon: String {
        switch step {
        case .targets: return "chevron.right"
        case .message: return "checklist"
        case .review: return "paperplane.fill"
        }
    }

    private var primaryButtonDisabled: Bool {
        switch step {
        case .targets: return selection.includedTargets.isEmpty
        case .message: return messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .review: return !preflight.canLaunch
        }
    }

    private var readinessTitle: String {
        switch automationReadiness {
        case .notInstalled: return "자동 발송 준비가 필요합니다"
        case .installedNeedsTest: return "본인 번호 시험이 필요합니다"
        case .messagePermissionRequired: return "문자 권한이 필요합니다"
        case .attachmentPermissionRequired: return "첨부 권한이 필요합니다"
        case .ready: return "자동 발송 사용 가능"
        case .updateRequired: return "단축어 업데이트가 필요합니다"
        case .unavailable: return "이 기기에서 자동 발송을 사용할 수 없습니다"
        }
    }

    private var readinessSubtitle: String {
        if automationReadiness == .ready {
            return shortcutVerifiedAt.isEmpty ? "단축어 v\(Self.transportConfiguration.shortcutVersion)" : "마지막 시험 \(shortcutVerifiedAt)"
        }
        return "대상과 메시지는 먼저 작성할 수 있습니다."
    }

    private var readinessIcon: String {
        switch automationReadiness {
        case .ready: return "checkmark.seal.fill"
        case .notInstalled, .unavailable: return "xmark.octagon.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var readinessColor: Color {
        switch automationReadiness {
        case .ready: return .green
        case .notInstalled, .unavailable: return .red
        default: return .orange
        }
    }

    private var messageKindText: String {
        switch preflight.estimatedMessageKind {
        case .sms: return "SMS"
        case .lms: return "LMS"
        case .mms: return "MMS"
        }
    }

    private var durationText: String {
        let seconds = preflight.estimatedDurationSeconds
        if seconds < 60 { return "\(seconds)초" }
        return "약 \((seconds + 59) / 60)분"
    }

    private func exclusionText(_ reason: GroupSmsTargetExclusionReason) -> String {
        switch reason {
        case .userExcluded: return "제외"
        case .missingOrInvalidPhone: return "번호 오류"
        case .duplicatePhone: return "중복"
        case .recentlyMessaged: return "최근 발송"
        }
    }

    private func blockingReasonText(_ reason: GroupSmsPreflightBlockingReason) -> String {
        switch reason {
        case .noRecipients: return "발송 가능한 고객이 없습니다"
        case .emptyContent: return "메시지를 입력하세요"
        case .automationNotReady: return "자동 발송 준비를 완료하세요"
        case .policyLimitExceeded: return "오늘 발송 보호선을 초과합니다"
        case .invalidAttachments: return "첨부파일을 확인하세요"
        }
    }

    private var resultTitle: String {
        switch currentCampaign?.status {
        case .requested: return "발송 요청 완료"
        case .cancelled: return "발송 요청 취소"
        case .shortcutFailed: return "발송 요청 오류"
        default: return "상태 확인 필요"
        }
    }

    private var resultIcon: String {
        currentCampaign?.status == .requested ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var resultColor: Color {
        currentCampaign?.status == .requested ? .green : .orange
    }
}

private struct GroupSmsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.32))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct GroupSmsSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .foregroundStyle(isEnabled ? Color.accentColor : AppPalette.textSecondary)
            .background(AppPalette.cardBackground.opacity(configuration.isPressed ? 0.72 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppPalette.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    @ViewBuilder
    func groupSmsCompactNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
