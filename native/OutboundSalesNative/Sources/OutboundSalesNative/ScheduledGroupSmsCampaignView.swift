import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ScheduledGroupSmsCampaignView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let campaignId: String
    let initialAction: GroupSmsScheduleAction

    @State private var didProcessInitialAction = false
    @State private var message = ""
    @State private var isWorking = false

    private static let transportConfiguration = SoheeGroupSmsProductConfiguration.transport

    private var campaign: GroupSmsCampaign? {
        state.groupSmsCampaign(id: campaignId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let campaign {
                        header(campaign)
                        summary(campaign)

                        if !message.isEmpty {
                            Label(message, systemImage: messageIcon)
                                .font(.headline)
                                .foregroundStyle(messageColor)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if campaign.status == .scheduled || campaign.status == .due {
                            actionButtons(campaign)
                        } else {
                            Button("닫기") { dismiss() }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .buttonStyle(ScheduledGroupSmsPrimaryButtonStyle())
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        ContentUnavailableView(
                            "예약을 찾지 못했습니다",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("다른 기기에서 삭제되었거나 이미 정리된 예약일 수 있습니다.")
                        )
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .background(AppPalette.pageBackground)
            .navigationTitle("예약 단체문자")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task {
                await processInitialActionIfNeeded()
            }
        }
    }

    private func header(_ campaign: GroupSmsCampaign) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 38))
                .foregroundStyle(Color.accentColor)
            Text(campaign.title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(AppPalette.textPrimary)
            Text("예약한 단체문자를 확인한 뒤 발송을 시작합니다.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
        }
    }

    private func summary(_ campaign: GroupSmsCampaign) -> some View {
        VStack(spacing: 0) {
            summaryRow("대상", value: "\(campaign.recipients.count)명", icon: "person.2.fill")
            Divider()
            summaryRow("예약", value: scheduledDateText(campaign.scheduledAt), icon: "clock.fill")
            Divider()
            summaryRow("범위", value: campaign.targetDescription, icon: "list.bullet")
        }
        .padding(.horizontal, 14)
        .background(AppPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func summaryRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 54)
    }

    private func actionButtons(_ campaign: GroupSmsCampaign) -> some View {
        VStack(spacing: 10) {
            Button {
                launch(campaign)
            } label: {
                Label("발송 시작", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(ScheduledGroupSmsPrimaryButtonStyle())
            .disabled(isWorking)

            HStack(spacing: 10) {
                Button {
                    Task { await snooze(campaign) }
                } label: {
                    Label("10분 뒤", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(ScheduledGroupSmsSecondaryButtonStyle())
                .disabled(isWorking)

                Button(role: .destructive) {
                    cancel(campaign)
                } label: {
                    Label("예약 취소", systemImage: "xmark")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(ScheduledGroupSmsSecondaryButtonStyle())
                .disabled(isWorking)
            }
        }
    }

    private func processInitialActionIfNeeded() async {
        guard !didProcessInitialAction, let campaign else { return }
        didProcessInitialAction = true
        switch initialAction {
        case .snoozeTenMinutes:
            await snooze(campaign)
        case .cancel:
            cancel(campaign)
        case .open, .sendNow:
            if initialAction == .sendNow || (campaign.scheduledAt ?? .distantFuture) <= Date() {
                state.markGroupSmsCampaign(campaign.id, status: .due)
            }
        }
    }

    private func launch(_ campaign: GroupSmsCampaign) {
        isWorking = true
        let payload = GroupSmsBuilder.makePayload(
            configuration: Self.transportConfiguration,
            campaignId: campaign.id,
            campaignTitle: campaign.title,
            recipients: campaign.recipients,
            attachments: campaign.attachments ?? []
        )

        do {
            let json = try GroupSmsBuilder.encodePayload(payload)
            guard let url = GroupSmsBuilder.shortcutsRunURL(
                configuration: Self.transportConfiguration,
                campaignId: campaign.id
            ) else {
                message = "단축어 실행 URL을 만들지 못했습니다."
                isWorking = false
                return
            }
            copyToClipboard(json)
            GroupSmsScheduleNotificationService.cancel(
                notificationIdentifier: campaign.scheduleNotificationIdentifier
            )
            state.markGroupSmsCampaign(campaign.id, status: .shortcutOpened)
            openURL(url) { accepted in
                if !accepted {
                    state.markGroupSmsCampaign(campaign.id, status: .shortcutFailed)
                    message = "Shortcuts를 열지 못했습니다."
                }
                isWorking = false
            }
        } catch {
            message = "예약된 발송 데이터를 준비하지 못했습니다."
            isWorking = false
        }
    }

    private func snooze(_ campaign: GroupSmsCampaign) async {
        isWorking = true
        defer { isWorking = false }
        let nextDate = Date().addingTimeInterval(10 * 60)
        do {
            let identifier = try await GroupSmsScheduleNotificationService.schedule(
                campaignId: campaign.id,
                title: campaign.title,
                recipientCount: campaign.recipients.count,
                at: nextDate
            )
            state.rescheduleGroupSmsCampaign(
                campaign.id,
                scheduledAt: nextDate,
                notificationIdentifier: identifier
            )
            message = "10분 뒤 다시 알려드립니다."
        } catch {
            message = error.localizedDescription
        }
    }

    private func cancel(_ campaign: GroupSmsCampaign) {
        GroupSmsScheduleNotificationService.cancel(
            notificationIdentifier: campaign.scheduleNotificationIdentifier
        )
        state.markGroupSmsCampaign(campaign.id, status: .cancelled)
        message = "예약을 취소했습니다."
    }

    private func scheduledDateText(_ date: Date?) -> String {
        guard let date else { return "시간 정보 없음" }
        return Self.dateFormatter.string(from: date)
    }

    private func copyToClipboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }

    private var messageIcon: String {
        message.contains("취소") ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var messageColor: Color {
        message.contains("못") || message.contains("필요") ? .red : .green
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 E a h:mm"
        return formatter
    }()
}

private struct ScheduledGroupSmsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.32))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ScheduledGroupSmsSecondaryButtonStyle: ButtonStyle {
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

private struct ScheduledGroupSmsListSelection: Identifiable {
    let id: String
}

struct ScheduledGroupSmsListView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var selection: ScheduledGroupSmsListSelection?

    private var campaigns: [GroupSmsCampaign] {
        state.groupSmsCampaigns
            .filter {
                ($0.status == .scheduled || $0.status == .due)
                    && $0.scheduleDeviceIdentifier == GroupSmsScheduleNotificationService.currentDeviceIdentifier
            }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    var body: some View {
        List {
            if campaigns.isEmpty {
                ContentUnavailableView(
                    "예약 문자 없음",
                    systemImage: "calendar.badge.clock",
                    description: Text("단체문자 확인 단계에서 예약할 수 있습니다.")
                )
            } else {
                ForEach(campaigns) { campaign in
                    Button {
                        selection = ScheduledGroupSmsListSelection(id: campaign.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: campaign.status == .due ? "bell.badge.fill" : "calendar.badge.clock")
                                .font(.title3)
                                .foregroundStyle(campaign.status == .due ? .red : .orange)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(campaign.title)
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.textPrimary)
                                Text(Self.dateFormatter.string(from: campaign.scheduledAt ?? campaign.createdAt))
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                            }

                            Spacer()

                            Text("\(campaign.recipients.count)명")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("예약 문자")
        .sheet(item: $selection) { item in
            ScheduledGroupSmsCampaignView(campaignId: item.id, initialAction: .open)
                .environmentObject(state)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 E a h:mm"
        return formatter
    }()
}
