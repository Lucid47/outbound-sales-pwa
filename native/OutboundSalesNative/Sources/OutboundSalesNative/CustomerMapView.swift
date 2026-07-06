import MapKit
import OutboundSalesCore
import SwiftUI

struct CustomerMapView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private var mappedCustomers: [Customer] {
        state.visibleCustomers.filter { $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition) {
                    ForEach(mappedCustomers) { customer in
                        if let coordinate = customer.coordinate {
                            Marker(customer.name.isEmpty ? "고객" : customer.name, coordinate: coordinate)
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .ignoresSafeArea(edges: .top)

                MapSummaryBanner(
                    selectedListName: state.selectedList?.name ?? "전체 고객",
                    mappedCount: mappedCustomers.count,
                    totalCount: state.visibleCustomers.count
                )
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
