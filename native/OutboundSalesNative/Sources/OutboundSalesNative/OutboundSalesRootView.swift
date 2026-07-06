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

            CustomerMapView()
                .environmentObject(state)
                .tabItem { Label("지도", systemImage: "map") }

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
                    ForEach(state.visibleCustomers.prefix(8)) { customer in
                        CustomerRow(customer: customer)
                    }
                }
            }
            .navigationTitle("오늘")
        }
    }
}

struct CustomersView: View {
    @EnvironmentObject private var state: NativeAppState

    var body: some View {
        NavigationStack {
            List {
                Section("고객리스트") {
                    ForEach(state.customerLists) { list in
                        Button {
                            state.selectList(list)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(list.name)
                                    Text(list.companyName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if state.selectedListId == list.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section("고객") {
                    ForEach(state.visibleCustomers) { customer in
                        Button {
                            state.toggleDone(customer)
                        } label: {
                            CustomerRow(customer: customer)
                        }
                    }
                }
            }
            .searchable(text: $state.searchText, prompt: "이름, 전화번호, 주소 검색")
            .navigationTitle("고객")
        }
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
            }
        }
        .padding(.vertical, 4)
    }
}
