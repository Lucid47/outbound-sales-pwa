import MapKit
import OutboundSalesCore
import SwiftUI

struct CustomerActionCard: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.openURL) private var openURL
    let customer: Customer
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                        .font(.headline)
                    Text(regionLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !customer.phoneNumber.isEmpty {
                        Text(customer.phoneNumber)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(customer.address.isEmpty ? "주소 없음" : customer.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)
                    if !compact, let latest = state.logs(for: customer).first {
                        Text("최근: \(latest.1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(customer.status == .done ? "완료" : customer.status == .needsGeocode ? "위치확인" : "미완")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.14))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                quickButton("전화", "phone.fill") {
                    callCustomer()
                }
                .disabled(!hasDialablePhone(customer.phoneNumber))

                quickButton("문자", "message.fill") {
                    smsCustomer()
                }
                .disabled(!hasDialablePhone(customer.phoneNumber))

                quickButton("길찾기", "location.fill") {
                    navigateCustomer()
                }
                .disabled(customer.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && customer.latitude == nil)
            }

            HStack(spacing: 8) {
                NavigationLink {
                    CustomerDetailView(customerId: customer.id)
                        .environmentObject(state)
                } label: {
                    Label("상세", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    state.addToTodaySchedule(customer)
                } label: {
                    Label("스케줄", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    if customer.status == .done {
                        state.toggleDone(customer)
                    } else {
                        state.completeVisit(customer: customer)
                    }
                } label: {
                    Label(customer.status == .done ? "완료취소" : "완료", systemImage: customer.status == .done ? "arrow.uturn.backward" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(customer.status == .done ? .gray : .green)
            }
        }
        .padding(compact ? 10 : 12)
        .background(Color(red: 0.973, green: 0.98, blue: 0.988))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.847, green: 0.871, blue: 0.91), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var regionLine: String {
        var parts = [customer.region ?? extractRegion(customer.address)]
        if customer.latitude != nil, customer.longitude != nil {
            parts.append("지도 표시 가능")
        } else {
            parts.append("위치 변환 필요")
        }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch customer.status {
        case .done:
            return .green
        case .needsGeocode:
            return .orange
        case .hold:
            return .orange
        case .open:
            return .blue
        }
    }

    private func quickButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.122, green: 0.435, blue: 0.922))
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
        let tmapURL = tmapURLForCustomer()
        openURL(tmapURL) { accepted in
            if !accepted {
                openAppleMaps()
            }
        }
    }

    private func tmapURLForCustomer() -> URL {
        let goalName = (customer.name.isEmpty ? customer.address : customer.name)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let latitude = customer.latitude, let longitude = customer.longitude {
            return URL(string: "tmap://route?goalx=\(longitude)&goaly=\(latitude)&goalname=\(goalName)")!
        }
        let destination = (normalizeAddressForMapSearch(customer.address).isEmpty ? customer.address : normalizeAddressForMapSearch(customer.address))
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "tmap://?search=\(destination)")!
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

struct CustomerCompactRow: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.openURL) private var openURL
    let customer: Customer

    var body: some View {
        HStack(spacing: 8) {
            statusDot

            NavigationLink {
                CustomerDetailView(customerId: customer.id)
                    .environmentObject(state)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if !customer.phoneNumber.isEmpty {
                            Text(customer.phoneNumber)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(compactAddressLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                iconButton("전화", "phone.fill", disabled: !hasDialablePhone(customer.phoneNumber)) {
                    callCustomer()
                }
                iconButton("문자", "message.fill", disabled: !hasDialablePhone(customer.phoneNumber)) {
                    smsCustomer()
                }
                iconButton("길찾기", "location.fill", disabled: customer.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && customer.latitude == nil) {
                    navigateCustomer()
                }
                iconButton(customer.status == .done ? "완료취소" : "완료", customer.status == .done ? "arrow.uturn.backward" : "checkmark", disabled: false) {
                    if customer.status == .done {
                        state.toggleDone(customer)
                    } else {
                        state.completeVisit(customer: customer)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.894, green: 0.91, blue: 0.937))
                .frame(height: 1)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var compactAddressLine: String {
        let address = customer.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = customer.region ?? extractRegion(customer.address)
        if address.isEmpty {
            return region.isEmpty ? "주소 없음" : region
        }
        return region.isEmpty || region == "주소 없음" ? address : "\(region) · \(address)"
    }

    private var statusColor: Color {
        switch customer.status {
        case .done:
            return .green
        case .needsGeocode, .hold:
            return .orange
        case .open:
            return .blue
        }
    }

    private func iconButton(_ title: String, _ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .secondary.opacity(0.45) : Color(red: 0.122, green: 0.435, blue: 0.922))
        .disabled(disabled)
        .accessibilityLabel(title)
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
        let tmapURL = tmapURLForCustomer()
        openURL(tmapURL) { accepted in
            if !accepted {
                openAppleMaps()
            }
        }
    }

    private func tmapURLForCustomer() -> URL {
        let goalName = (customer.name.isEmpty ? customer.address : customer.name)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let latitude = customer.latitude, let longitude = customer.longitude {
            return URL(string: "tmap://route?goalx=\(longitude)&goaly=\(latitude)&goalname=\(goalName)")!
        }
        let destination = (normalizeAddressForMapSearch(customer.address).isEmpty ? customer.address : normalizeAddressForMapSearch(customer.address))
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "tmap://?search=\(destination)")!
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
