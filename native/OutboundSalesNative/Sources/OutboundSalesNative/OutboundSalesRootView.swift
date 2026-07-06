import OutboundSalesCore
import SwiftUI

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
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        CustomerMapView()
                            .environmentObject(state)
                    } label: {
                        HStack {
                            Label("고객 위치 지도", systemImage: "map")
                            Spacer()
                            Text("표시 가능 \(state.visibleCustomers.filter { $0.latitude != nil && $0.longitude != nil }.count)/\(state.visibleCustomers.count)명")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.white)
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
                            Spacer()
                            Text("\(filteredCustomers.count)명")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if filteredCustomers.isEmpty {
                            ContentUnavailableView("고객 없음", systemImage: "person.3", description: Text("가져오기 탭에서 고객을 추가하세요."))
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
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
            }
            .background(Color(red: 0.961, green: 0.969, blue: 0.984))
            .searchable(text: $state.searchText, prompt: "이름, 전화번호, 주소 검색")
            .navigationTitle("고객")
        }
    }
}

struct ActiveListPanel: View {
    @EnvironmentObject private var state: NativeAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.selectedList?.name ?? "고객리스트 없음")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(state.selectedList?.companyName ?? "가져오기 탭에서 고객리스트를 생성하세요.")
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
            }
        }
        .padding(12)
        .background(Color(red: 0.086, green: 0.125, blue: 0.196))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
