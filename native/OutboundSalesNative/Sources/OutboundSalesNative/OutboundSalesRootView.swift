import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct OutboundSalesRootView: View {
    @StateObject private var state = NativeAppState()

    public init() {}

    public var body: some View {
        TabView {
            TodayView()
                .environmentObject(state)
                .tabItem { Label("오늘", systemImage: "calendar") }

            CustomersView()
                .environmentObject(state)
                .tabItem { Label("고객", systemImage: "person.3") }

            ImportView()
                .environmentObject(state)
                .tabItem { Label("가져오기", systemImage: "square.and.arrow.down") }

            LogsView()
                .environmentObject(state)
                .tabItem { Label("기록", systemImage: "clock.arrow.circlepath") }

            GroupSmsTestView()
                .tabItem { Label("단체문자", systemImage: "message.badge") }

            SettingsView()
                .environmentObject(state)
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .task {
            await state.performStartupMaintenance()
        }
    }
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

    var body: some View {
        NavigationStack {
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
                    .padding(12)
                    .background(AppPalette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
            }
            .background(AppPalette.pageBackground)
            .searchable(text: $state.searchText, prompt: "이름, 전화번호, 주소 검색")
            .navigationTitle("고객")
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
