import MapKit
import OutboundSalesCore
import SwiftUI

struct CustomerMapView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var selectedCustomerId: String?
    @State private var noteCustomer: Customer?
    @State private var historyCustomer: Customer?

    private var mappedCustomers: [Customer] {
        state.visibleCustomers.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var selectedCustomer: Customer? {
        guard let selectedCustomerId else { return nil }
        return state.customers.first { $0.id == selectedCustomerId }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition) {
                    ForEach(mappedCustomers) { customer in
                        if let coordinate = customer.coordinate {
                            Annotation("", coordinate: coordinate, anchor: .bottom) {
                                MapCustomerLabel(
                                    customer: customer,
                                    selected: selectedCustomerId == customer.id
                                )
                                .onTapGesture {
                                    selectedCustomerId = customer.id
                                }
                            }
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 10) {
                    MapSummaryBanner(
                        selectedListName: state.selectedList?.name ?? "전체 고객",
                        mappedCount: mappedCustomers.count,
                        totalCount: state.visibleCustomers.count
                    )

                    if let selectedCustomer {
                        MapCustomerPanel(
                            customer: selectedCustomer,
                            onClose: { selectedCustomerId = nil },
                            onNote: { noteCustomer = selectedCustomer },
                            onHistory: { historyCustomer = selectedCustomer }
                        )
                        .environmentObject(state)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationTitle("지도")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button {
                            fitMappedCustomers()
                        } label: {
                            Image(systemName: "scope")
                        }
                        .disabled(mappedCustomers.isEmpty)

                        Button {
                            Task {
                                await state.geocodeVisibleCustomers()
                                fitMappedCustomers()
                            }
                        } label: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }
                }
            }
            .task {
                if mappedCustomers.isEmpty {
                    await state.geocodeVisibleCustomers()
                }
                fitMappedCustomers()
            }
            .sheet(item: $noteCustomer) { customer in
                CustomerNoteSheet(customer: customer)
                    .environmentObject(state)
            }
            .sheet(item: $historyCustomer) { customer in
                CustomerHistorySheet(customer: customer)
                    .environmentObject(state)
            }
        }
    }

    private func fitMappedCustomers() {
        let coordinates = mappedCustomers.compactMap(\.coordinate)
        guard let region = MKCoordinateRegion.bounding(coordinates: coordinates) else {
            cameraPosition = .region(Self.defaultRegion)
            return
        }
        cameraPosition = .region(region)
    }

    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
}

private struct MapCustomerLabel: View {
    let customer: Customer
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(customer.name.isEmpty ? "고객" : customer.name)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Text(customer.status == .done ? "완료" : "미완")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white.opacity(0.24))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(statusColor)
        .overlay(
            Capsule().stroke(.white, lineWidth: selected ? 3 : 1.5)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    private var statusColor: Color {
        switch customer.status {
        case .done:
            return .green
        case .needsGeocode, .hold:
            return .orange
        case .open:
            return .orange
        }
    }
}

private struct MapCustomerPanel: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.openURL) private var openURL
    let customer: Customer
    let onClose: () -> Void
    let onNote: () -> Void
    let onHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(customer.name.isEmpty ? "고객" : customer.name)
                        .font(.headline)
                    Text(customer.address.isEmpty ? "주소 없음" : customer.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(scheduleText) · \(state.progressLabel(for: customer))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                panelButton("전화", "phone") { callCustomer() }
                    .disabled(!hasDialablePhone(customer.phoneNumber))
                panelButton("문자", "message") { smsCustomer() }
                    .disabled(!hasDialablePhone(customer.phoneNumber))
                panelButton("길찾기", "location") { navigateCustomer() }
                    .disabled(customer.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && customer.latitude == nil)
                panelButton("메모", "square.and.pencil") { onNote() }
                panelButton("이력", "calendar.badge.clock") { onHistory() }
                panelButton(customer.status == .done ? "완료취소" : "완료", "checkmark") {
                    if customer.status == .done {
                        state.toggleDone(customer)
                    } else {
                        state.completeVisit(customer: customer)
                    }
                }
            }

            Button {
                state.addToTodaySchedule(customer)
            } label: {
                Label("스케줄 추가", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.086, green: 0.125, blue: 0.196))
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var scheduleText: String {
        guard let schedule = state.todaySchedule else { return "스케줄 미포함" }
        let included = state.visitScheduleItems.contains { $0.scheduleId == schedule.id && $0.customerId == customer.id }
        return included ? "오늘 스케줄" : "스케줄 미포함"
    }

    private func panelButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
    }

    private func callCustomer() {
        state.recordContact(customer: customer, type: .call)
        if let url = URL(string: "tel:\(cleanPhone(customer.phoneNumber))") {
            openURL(url)
        }
    }

    private func smsCustomer() {
        state.recordContact(customer: customer, type: .manualSms)
        if let url = URL(string: "sms:\(cleanPhone(customer.phoneNumber))") {
            openURL(url)
        }
    }

    private func navigateCustomer() {
        let goalName = (customer.name.isEmpty ? customer.address : customer.name)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url: URL
        if let latitude = customer.latitude, let longitude = customer.longitude {
            url = URL(string: "tmap://route?goalx=\(longitude)&goaly=\(latitude)&goalname=\(goalName)")!
        } else {
            let destination = (normalizeAddressForMapSearch(customer.address).isEmpty ? customer.address : normalizeAddressForMapSearch(customer.address))
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            url = URL(string: "tmap://?search=\(destination)")!
        }
        openURL(url) { accepted in
            if !accepted {
                openAppleMaps()
            }
        }
    }

    private func openAppleMaps() {
        if let latitude = customer.latitude, let longitude = customer.longitude {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
            item.name = customer.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            return
        }
        let destination = normalizeAddressForMapSearch(customer.address).isEmpty ? customer.address : normalizeAddressForMapSearch(customer.address)
        if let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)") {
            openURL(url)
        }
    }
}

struct CustomerNoteSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var memo = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name.isEmpty ? "고객 메모" : customer.name) {
                    TextField("메모", text: $memo, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("메모")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        state.addNote(customer: customer, memo: memo)
                        dismiss()
                    }
                    .disabled(memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct CustomerHistorySheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer

    var body: some View {
        NavigationStack {
            List {
                Section("고객") {
                    LabeledContent("이름", value: customer.name.isEmpty ? "이름 없음" : customer.name)
                    LabeledContent("연락처", value: customer.phoneNumber.isEmpty ? "연락처 없음" : customer.phoneNumber)
                    LabeledContent("진행상태", value: state.progressLabel(for: customer))
                }
                Section("히스토리") {
                    let logs = state.logs(for: customer)
                    if logs.isEmpty {
                        Text("아직 터치 이력 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.1)
                                    .font(.headline)
                                Text(log.2)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(log.0, format: .dateTime.month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("이력")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

private struct MapSummaryBanner: View {
    @EnvironmentObject private var state: NativeAppState
    let selectedListName: String
    let mappedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedListName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(mappedCount)/\(totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if totalCount == 0 {
                Text("고객리스트를 가져오거나 고객을 추가하면 지도에서 확인할 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if mappedCount == 0 {
                Text(state.geocodeMessage.isEmpty ? "좌표가 있는 고객이 없습니다. 우측 상단 핀 버튼으로 주소를 변환하세요." : state.geocodeMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(state.geocodeMessage.isEmpty ? "좌표가 있는 고객을 지도에 표시하고 있습니다." : state.geocodeMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Customer {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension MKCoordinateRegion {
    static func bounding(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.4, 0.02)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.4, 0.02)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
