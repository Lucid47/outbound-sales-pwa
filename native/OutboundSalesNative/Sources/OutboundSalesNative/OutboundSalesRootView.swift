import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum OutboundSalesRootTab: String {
    case today
    case customers
    case importData
    case logs
    case settings
}

private struct ScheduledGroupSmsPresentation: Identifiable {
    let campaignId: String
    let action: GroupSmsScheduleAction
    var id: String { "\(campaignId)-\(action.rawValue)" }
}

public struct OutboundSalesRootView: View {
    @StateObject private var state = NativeAppState()
    @AppStorage("selectedRootTab") private var selectedTab = OutboundSalesRootTab.today.rawValue
    @State private var scheduledGroupSmsPresentation: ScheduledGroupSmsPresentation?

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .environmentObject(state)
                .tabItem { Label("오늘", systemImage: "calendar") }
                .tag(OutboundSalesRootTab.today.rawValue)

            CustomersView()
                .environmentObject(state)
                .tabItem { Label("고객", systemImage: "person.3") }
                .tag(OutboundSalesRootTab.customers.rawValue)

            ImportView()
                .environmentObject(state)
                .tabItem { Label("가져오기", systemImage: "square.and.arrow.down") }
                .tag(OutboundSalesRootTab.importData.rawValue)

            LogsView()
                .environmentObject(state)
                .tabItem { Label("기록", systemImage: "clock.arrow.circlepath") }
                .tag(OutboundSalesRootTab.logs.rawValue)

            SettingsView()
                .environmentObject(state)
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(OutboundSalesRootTab.settings.rawValue)
        }
        .onAppear {
            // iOS stores the previous six-tab selection even after the tab is removed.
            if selectedTab == "groupSms" {
                selectedTab = OutboundSalesRootTab.customers.rawValue
            }
        }
        .task {
            await state.performStartupMaintenance()
        }
        .onOpenURL { url in
            state.handleGroupSmsCallback(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .outboundSalesOpenURL)) { notification in
            guard let url = notification.object as? URL else { return }
            state.handleGroupSmsCallback(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .outboundSalesScheduledGroupSmsAction)) { notification in
            guard let event = notification.object as? GroupSmsScheduleNotificationEvent else { return }
            selectedTab = OutboundSalesRootTab.customers.rawValue
            scheduledGroupSmsPresentation = ScheduledGroupSmsPresentation(
                campaignId: event.campaignId,
                action: event.action
            )
        }
        .sheet(item: $scheduledGroupSmsPresentation) { presentation in
            ScheduledGroupSmsCampaignView(
                campaignId: presentation.campaignId,
                initialAction: presentation.action
            )
            .environmentObject(state)
        }
    }
}

public extension Notification.Name {
    static let outboundSalesOpenURL = Notification.Name("OutboundSalesOpenURL")
}

struct TodayView: View {
    @EnvironmentObject private var state: NativeAppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TodayClockHeader()
                }

                Section("요약") {
                    LabeledContent("선택 리스트", value: state.selectedList?.name ?? "없음")
                    LabeledContent("미완료", value: "\(state.openCustomerCount)")
                    LabeledContent("완료", value: "\(state.doneCustomerCount)")
                }

                Section("오늘 확인할 고객") {
                    if state.todayScheduledCustomers.isEmpty {
                        Text("고객 상세에서 오늘 스케줄에 추가할 수 있습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.todayScheduledCustomers) { customer in
                            NavigationLink {
                                CustomerDetailView(customerId: customer.id)
                                    .environmentObject(state)
                            } label: {
                                CustomerRow(customer: customer)
                            }
                        }
                    }
                }

                Section("지도") {
                    NavigationLink {
                        CustomerMapView()
                            .environmentObject(state)
                    } label: {
                        Label("오늘 고객 지도 보기", systemImage: "map")
                    }
                }

                Section("빠른 실행") {
                    NavigationLink {
                        GroupSmsCampaignView(initialTargetScope: .todaySchedule)
                            .environmentObject(state)
                    } label: {
                        Label("오늘 고객에게 단체문자", systemImage: "message.fill")
                    }
                    .disabled(state.todayScheduledCustomers.isEmpty)
                }
            }
            .navigationTitle("오늘")
        }
    }
}

private struct TodayClockHeader: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.dateFormatter.string(from: context.date))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(Self.timeFormatter.string(from: context.date))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

enum CustomerFilterMode: String, CaseIterable, Identifiable {
    case open = "미방문"
    case done = "완료"
    case all = "전체"

    var id: String { rawValue }
}

enum CustomerDisplayMode: String, CaseIterable, Identifiable {
    case cards = "카드"
    case list = "목록"

    var id: String { rawValue }
}

struct CustomersView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var filterMode: CustomerFilterMode = .open
    @State private var displayMode: CustomerDisplayMode = .cards

    private var filteredCustomers: [Customer] {
        switch filterMode {
        case .open:
            return state.visibleCustomers.filter { $0.status != .done }
        case .done:
            return state.visibleCustomers.filter { $0.status == .done }
        case .all:
            return state.visibleCustomers
        }
    }

    private var scheduledGroupSmsCount: Int {
        state.groupSmsCampaigns.filter {
            ($0.status == .scheduled || $0.status == .due)
                && $0.scheduleDeviceIdentifier == GroupSmsScheduleNotificationService.currentDeviceIdentifier
        }.count
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ActiveListPanel()
                            .environmentObject(state)

                        if !state.geocodeMessage.isEmpty {
                            Label(state.geocodeMessage, systemImage: "mappin.and.ellipse")
                                .font(.footnote)
                                .foregroundStyle(AppPalette.textSecondary)
                        }

                        NavigationLink {
                            CustomerMapView()
                                .environmentObject(state)
                        } label: {
                            HStack {
                                Label("고객 위치 지도", systemImage: "map")
                                    .foregroundStyle(AppPalette.textPrimary)
                                Spacer()
                                Text("표시 가능 \(state.visibleCustomers.filter { $0.latitude != nil && $0.longitude != nil }.count)/\(state.visibleCustomers.count)명")
                                    .font(.caption)
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                            .padding(12)
                            .background(AppPalette.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            GroupSmsCampaignView(initialTargetScope: .selectedList)
                                .environmentObject(state)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "message.fill")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("단체문자")
                                        .font(.headline)
                                    Text("고객리스트 또는 연락처에서 대상 선택")
                                        .font(.caption)
                                        .opacity(0.85)
                                }
                                Spacer()
                                Text("\(state.visibleCustomers.count)명")
                                    .font(.headline)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .padding(.horizontal, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        if scheduledGroupSmsCount > 0 {
                            NavigationLink {
                                ScheduledGroupSmsListView()
                                    .environmentObject(state)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(.orange)
                                    Text("예약 문자")
                                        .font(.headline)
                                        .foregroundStyle(AppPalette.textPrimary)
                                    Spacer()
                                    Text("\(scheduledGroupSmsCount)건")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.orange)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppPalette.textSecondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .padding(.horizontal, 14)
                                .background(AppPalette.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppPalette.hairline, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }

                        Picker("필터", selection: $filterMode) {
                            ForEach(CustomerFilterMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("표시 방식", selection: $displayMode) {
                            ForEach(CustomerDisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        customerListSection(width: proxy.size.width)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(responsivePagePadding(for: proxy.size.width))
                }
                .background(AppPalette.pageBackground)
            }
            .searchable(text: $state.searchText, prompt: "이름, 전화번호, 주소 검색")
            .navigationTitle("고객")
        }
    }

    private func customerListSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("고객 목록")
                    .font(.headline)
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer()
                Text("\(filteredCustomers.count)명")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
            }

            if filteredCustomers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.largeTitle)
                        .foregroundStyle(AppPalette.textSecondary)
                    Text("고객 없음")
                        .font(.headline)
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("가져오기 탭에서 고객을 추가하세요.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                LazyVGrid(columns: customerGridColumns(width: width), spacing: displayMode == .cards ? 12 : 6) {
                    ForEach(filteredCustomers) { customer in
                        if displayMode == .cards {
                            CustomerActionCard(customer: customer, compact: false)
                                .environmentObject(state)
                        } else {
                            CustomerCompactRow(customer: customer)
                                .environmentObject(state)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(AppPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func customerGridColumns(width: CGFloat) -> [GridItem] {
        let horizontalPadding = responsivePagePadding(for: width) * 2 + 24
        let availableWidth = max(320, width - horizontalPadding)
        let minimum: CGFloat = displayMode == .cards ? 340 : 420
        let columnCount = max(1, min(displayMode == .cards ? 4 : 3, Int(availableWidth / minimum)))
        return Array(repeating: GridItem(.flexible(), spacing: displayMode == .cards ? 12 : 10, alignment: .top), count: columnCount)
    }

    private func responsivePagePadding(for width: CGFloat) -> CGFloat {
        switch width {
        case 0..<700:
            return 12
        case 700..<1100:
            return 18
        default:
            return 24
        }
    }
}

enum AppPalette {
    static var textPrimary: Color { .primary }
    static var textSecondary: Color { .secondary }

    static var hairline: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #elseif os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color.gray.opacity(0.28)
        #endif
    }

    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondary)
        #endif
    }

    static var pageBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.primary)
        #endif
    }
}

struct ActiveListPanel: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var showingContactExport = false

    private var selectedListCustomers: [Customer] {
        guard let list = state.selectedList else { return [] }
        return state.customers.filter { $0.customerListId == list.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.selectedList?.name ?? "고객리스트 없음")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(activeListSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                Text("\(state.visibleCustomers.count)명")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            if !state.customerLists.isEmpty {
                Menu {
                    ForEach(state.customerLists) { list in
                        Button(list.name) {
                            state.selectList(list)
                        }
                    }
                } label: {
                    Label("리스트 변경", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(red: 0.086, green: 0.125, blue: 0.196))

                Button {
                    showingContactExport = true
                } label: {
                    Label("연락처 등록", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.102, green: 0.737, blue: 0.306))
                .disabled(state.selectedList == nil || selectedListCustomers.isEmpty)
            }
        }
        .padding(12)
        .background(Color(red: 0.086, green: 0.125, blue: 0.196))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingContactExport) {
            if let selectedList = state.selectedList {
                ContactExportSheet(list: selectedList, customers: selectedListCustomers)
                    .environmentObject(state)
            }
        }
    }

    private var activeListSubtitle: String {
        guard let selectedList = state.selectedList else {
            return "가져오기 탭에서 고객리스트를 생성하세요."
        }
        return selectedList.sourceFileName.isEmpty ? "직접 생성한 고객리스트" : selectedList.sourceFileName
    }
}

struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: customer.status == .done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(customer.status == .done ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                    .font(.headline)
                Text(customer.phoneNumber.isEmpty ? "연락처 없음" : customer.phoneNumber)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(customer.address.isEmpty ? "주소 없음" : customer.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let birthDate = customer.birthDate, !birthDate.isEmpty {
                    Text(birthDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
