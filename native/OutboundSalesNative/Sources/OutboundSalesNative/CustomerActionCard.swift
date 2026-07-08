import MapKit
import OutboundSalesCore
import SwiftUI

struct CustomerActionCard: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.openURL) private var openURL
    let customer: Customer
    let compact: Bool
    @State private var showingEdit = false
    @State private var showingMessageSheet = false
    @State private var showingPhotoSheet = false
    @State private var showingVisitSheet = false

    private let primaryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let secondaryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .top, spacing: 10) {
                NavigationLink {
                    CustomerDetailView(customerId: customer.id)
                        .environmentObject(state)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                            .font(compact ? .title3.weight(.heavy) : .title2.weight(.heavy))
                            .foregroundStyle(AppPalette.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(regionLine)
                            .font(.caption)
                            .foregroundStyle(AppPalette.textSecondary)
                        if !customer.phoneNumber.isEmpty {
                            Text(customer.phoneNumber)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)
                        }
                        Text(customer.address.isEmpty ? "주소 없음" : customer.address)
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .lineLimit(compact ? 1 : 2)
                        if !compact, let latest = state.logs(for: customer).first {
                            Text("최근: \(latest.1)")
                                .font(.caption)
                                .foregroundStyle(AppPalette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(customer.status == .done ? "완료" : customer.status == .needsGeocode ? "위치확인" : "미완")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.14))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: primaryColumns, spacing: 8) {
                actionButton("전화", "phone.fill", color: Color(red: 0.122, green: 0.435, blue: 0.922)) {
                    callCustomer()
                }
                .disabled(!hasDialablePhone(customer.phoneNumber))

                actionButton("문자", "message.fill", color: Color(red: 0.02, green: 0.52, blue: 0.62)) {
                    showingMessageSheet = true
                }
                .disabled(!hasDialablePhone(customer.phoneNumber))

                actionButton("길찾기", "location.fill", color: Color(red: 0.31, green: 0.36, blue: 0.86)) {
                    navigateCustomer()
                }
                .disabled(customer.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && customer.latitude == nil)
            }

            LazyVGrid(columns: secondaryColumns, spacing: 8) {
                actionButton("수정", "pencil", color: Color(red: 0.40, green: 0.46, blue: 0.56)) {
                    showingEdit = true
                }

                actionButton("사진", "camera.fill", color: Color(red: 0.44, green: 0.35, blue: 0.82)) {
                    showingPhotoSheet = true
                }

                actionButton("스케줄", "calendar.badge.plus", color: Color(red: 0.84, green: 0.48, blue: 0.12)) {
                    state.addToTodaySchedule(customer)
                }

                actionButton("방문", "mappin.and.ellipse", color: Color(red: 0.12, green: 0.74, blue: 0.32)) {
                    showingVisitSheet = true
                }
            }
        }
        .padding(compact ? 10 : 12)
        .background(AppPalette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppPalette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingEdit) {
            EditCustomerView(customer: customer)
                .environmentObject(state)
        }
        .sheet(isPresented: $showingMessageSheet) {
            MessageComposerSheet(customer: customer)
                .environmentObject(state)
        }
        .sheet(isPresented: $showingPhotoSheet) {
            CustomerPhotoCaptureSheet(customer: customer, title: "사진 메모")
                .environmentObject(state)
        }
        .sheet(isPresented: $showingVisitSheet) {
            CustomerVisitPromptSheet(customer: customer)
                .environmentObject(state)
        }
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

    private func actionButton(_ title: String, _ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .actionButtonLabel()
        }
        .buttonStyle(ColoredActionButtonStyle(color: color))
    }

    private func callCustomer() {
        state.recordContact(customer: customer, type: .call)
        if let url = URL(string: "tel:\(cleanPhone(customer.phoneNumber))") {
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
        let routeLabel = normalizedDestination().isEmpty ? customer.name : normalizedDestination()
        let goalName = routeLabel
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let latitude = customer.latitude, let longitude = customer.longitude {
            return URL(string: "tmap://route?goalx=\(longitude)&goaly=\(latitude)&goalname=\(goalName)")!
        }
        let destination = (normalizedDestination().isEmpty ? customer.name : normalizedDestination())
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "tmap://?search=\(destination)")!
    }

    private func normalizedDestination() -> String {
        let normalized = normalizeAddressForMapSearch(customer.address)
        return normalized.isEmpty ? customer.address : normalized
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

private extension Label where Title == Text, Icon == Image {
    func actionButtonLabel() -> some View {
        self
            .font(.subheadline.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ColoredActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CustomerCompactRow: View {
    @EnvironmentObject private var state: NativeAppState
    let customer: Customer

    var body: some View {
        NavigationLink {
            CustomerDetailView(customerId: customer.id)
                .environmentObject(state)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                statusDot
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(AppPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    HStack(spacing: 6) {
                        if !customer.phoneNumber.isEmpty {
                            Text(customer.phoneNumber)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)
                                .lineLimit(1)
                        }
                        Text(state.progressLabel(for: customer))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }

                    Text(compactAddressLine)
                        .font(.caption)
                        .foregroundStyle(AppPalette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppPalette.hairline)
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
}
