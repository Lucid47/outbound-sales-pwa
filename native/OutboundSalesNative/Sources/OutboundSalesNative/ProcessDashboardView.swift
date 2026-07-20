import OutboundSalesCore
import SwiftUI

struct ProcessDashboardView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var currentPage = 0
    @State private var selectedCustomer: Customer?
    @State private var showingStatusSettings = false

    private let pageSize = 100
    private let gridDimension = 10
    private let gridSpacing: CGFloat = 2

    private var customers: [Customer] {
        state.visibleCustomers
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(customers.count) / Double(pageSize))))
    }

    private var pageCustomers: [Customer] {
        let safePage = min(currentPage, pageCount - 1)
        let start = safePage * pageSize
        guard start < customers.count else { return [] }
        return Array(customers[start..<min(start + pageSize, customers.count)])
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            Group {
                if isLandscape {
                    heatmapBoard
                        .padding(2)
                } else {
                    VStack(spacing: 8) {
                        summaryHeader
                        if state.dashboardSettings.showsLegend {
                            statusLegend
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        heatmapBoard
                        pageControls
                    }
                    .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 10)
                    .padding(.bottom, 8)
                }
            }
            .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(isLandscape)
        }
        .background(AppPalette.pageBackground)
        .navigationTitle("고객 프로세스")
        .modifier(InlineNavigationTitleModifier())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingStatusSettings = true
                } label: {
                    Label("상태 설정", systemImage: "slider.horizontal.3")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.snappy) {
                        state.setDashboardLegendVisible(!state.dashboardSettings.showsLegend)
                    }
                } label: {
                    Label("상태 범례", systemImage: "paintpalette")
                }
            }
        }
        .sheet(item: $selectedCustomer) { customer in
            DashboardCustomerSheet(customerId: customer.id)
                .environmentObject(state)
                .presentationDetents(horizontalSizeClass == .regular ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showingStatusSettings) {
            DashboardStatusSettingsView()
                .environmentObject(state)
        }
        .onChange(of: state.selectedListId) {
            currentPage = 0
        }
        .onChange(of: customers.count) {
            currentPage = min(currentPage, pageCount - 1)
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.selectedList?.name ?? "전체 고객")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(customers.count)명")
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("현재 페이지")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pageRangeText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(state.dashboardStatuses.enumerated()), id: \.element.id) { index, status in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(DashboardColor.color(hex: status.colorHex))
                            .frame(width: 9, height: 9)
                        Text("\(index + 1) \(status.name)")
                            .lineLimit(1)
                        Text("\(statusCount(status.id))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(AppPalette.cardBackground, in: Capsule())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var heatmapBoard: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let boardSide = max(0, min(proxy.size.width, proxy.size.height))
            let boardWidth = isLandscape ? proxy.size.width : boardSide
            let boardHeight = isLandscape ? proxy.size.height : boardSide
            let totalRowSpacing = gridSpacing * CGFloat(gridDimension - 1)
            let rowHeight = max(1, (boardHeight - totalRowSpacing) / CGFloat(gridDimension))
            let columns = Array(
                repeating: GridItem(.flexible(minimum: 1), spacing: gridSpacing),
                count: gridDimension
            )

            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(0..<pageSize, id: \.self) { index in
                    if index < pageCustomers.count {
                        let customer = pageCustomers[index]
                        ProcessHeatCell(
                            customer: customer,
                            status: state.dashboardStatus(for: customer),
                            statusNumber: statusNumber(for: customer),
                            elapsedDays: elapsedDays(for: customer),
                            isLandscape: isLandscape
                        )
                        .frame(height: rowHeight)
                        .onTapGesture { selectedCustomer = customer }
                    } else {
                        EmptyProcessHeatCell()
                            .frame(height: rowHeight)
                    }
                }
            }
            .frame(width: boardWidth, height: boardHeight, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .gesture(pageSwipeGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("고객 프로세스 히트맵, \(currentPage + 1)페이지")
        }
    }

    private var pageControls: some View {
        HStack(spacing: 14) {
            Button {
                changePage(to: currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == 0)

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { page in
                    Capsule()
                        .fill(page == currentPage ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: page == currentPage ? 18 : 7, height: 7)
                        .contentShape(Rectangle())
                        .onTapGesture { changePage(to: page) }
                }
            }
            .accessibilityLabel("\(pageCount)페이지 중 \(currentPage + 1)페이지")

            Button {
                changePage(to: currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(currentPage >= pageCount - 1)
        }
    }

    private var pageRangeText: String {
        guard !customers.isEmpty else { return "0 / 0" }
        let start = currentPage * pageSize + 1
        let end = min((currentPage + 1) * pageSize, customers.count)
        return "\(start)–\(end) / \(customers.count)"
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 55 else { return }
                changePage(to: currentPage + (value.translation.width < 0 ? 1 : -1))
            }
    }

    private func changePage(to page: Int) {
        guard (0..<pageCount).contains(page) else { return }
        withAnimation(.snappy) { currentPage = page }
    }

    private func statusCount(_ statusId: String) -> Int {
        pageCustomers.filter { state.dashboardStatus(for: $0)?.id == statusId }.count
    }

    private func statusNumber(for customer: Customer) -> Int? {
        guard let id = state.dashboardStatus(for: customer)?.id,
              let index = state.dashboardStatuses.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    private func elapsedDays(for customer: Customer) -> Int? {
        guard let latest = state.latestTouchDate(for: customer) else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: latest, to: Date()).day ?? 0)
    }
}

private struct ProcessHeatCell: View {
    let customer: Customer
    let status: DashboardStatusDefinition?
    let statusNumber: Int?
    let elapsedDays: Int?
    let isLandscape: Bool

    var body: some View {
        GeometryReader { proxy in
            let colorHex = status?.colorHex ?? "A8B1BE"
            let foregroundColor = DashboardColor.foregroundColor(hex: colorHex)
            let displayName = customer.name.isEmpty ? "이름없음" : customer.name
            let elapsedText = elapsedDays.map(String.init) ?? "–"
            let primaryFontSize = min(
                isLandscape ? 30 : 16,
                max(9, proxy.size.height * (isLandscape ? 0.62 : 0.4))
            )
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DashboardColor.color(hex: colorHex))

                Text("\(displayName) \(elapsedText)")
                    .font(.system(
                        size: primaryFontSize,
                        weight: isLandscape ? .black : .bold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .foregroundStyle(foregroundColor.opacity(0.9))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let statusNumber {
                    Text("\(statusNumber)")
                        .font(.system(size: 6, weight: .bold, design: .rounded))
                        .foregroundStyle(foregroundColor.opacity(0.68))
                        .padding(2)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(customer.name), \(status?.name ?? "상태 없음"), 마지막 터치 \(elapsedDays.map { "\($0)일 전" } ?? "기록 없음")")
        .accessibilityAddTraits(.isButton)
    }
}

private struct EmptyProcessHeatCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.secondary.opacity(0.055))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.14), style: StrokeStyle(lineWidth: 0.7, dash: [2, 2]))
            }
            .accessibilityHidden(true)
    }
}

private struct DashboardCustomerSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customerId: String

    private var customer: Customer? {
        state.customers.first { $0.id == customerId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let customer {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            customerHeader(customer)
                            statusPicker(customer)
                            recentHistory(customer)
                            NavigationLink {
                                CustomerDetailView(customerId: customer.id)
                                    .environmentObject(state)
                            } label: {
                                Label("전체 고객 상세 보기", systemImage: "person.text.rectangle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(20)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                    .background(AppPalette.pageBackground)
                } else {
                    ContentUnavailableView("고객을 찾을 수 없습니다.", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle("고객 상태")
            .modifier(InlineNavigationTitleModifier())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private func customerHeader(_ customer: Customer) -> some View {
        let status = state.dashboardStatus(for: customer)
        let colorHex = status?.colorHex ?? "A8B1BE"
        let latest = state.latestTouchDate(for: customer)
        let days = latest.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0) }
        return HStack(spacing: 14) {
            Circle()
                .fill(DashboardColor.color(hex: colorHex))
                .frame(width: 58, height: 58)
                .overlay {
                    Text(String((customer.name.isEmpty ? "?" : customer.name).prefix(1)))
                        .font(.title2.bold())
                        .foregroundStyle(DashboardColor.foregroundColor(hex: colorHex).opacity(0.86))
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                    .font(.title2.bold())
                Text(status?.name ?? "상태 없음")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("마지막 터치")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(days.map { "\($0)일 전" } ?? "기록 없음")
                    .font(.headline)
                    .monospacedDigit()
            }
        }
    }

    private func statusPicker(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("프로세스 상태")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(state.dashboardStatuses.enumerated()), id: \.element.id) { index, status in
                    Button {
                        withAnimation(.snappy) {
                            state.setDashboardStatus(customerId: customer.id, statusId: status.id)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(DashboardColor.color(hex: status.colorHex))
                                .frame(width: 13, height: 13)
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit().bold())
                            Text(status.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 1)
                            if state.dashboardStatus(for: customer)?.id == status.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 42)
                        .background(
                            state.dashboardStatus(for: customer)?.id == status.id
                                ? DashboardColor.color(hex: status.colorHex).opacity(0.2)
                                : AppPalette.cardBackground,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recentHistory(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 이력")
                .font(.headline)
            let entries = state.historyEntries(for: customer)
            if entries.isEmpty {
                Text("아직 터치 이력이 없습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries.prefix(3)) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(entry.at, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .background(AppPalette.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct DashboardStatusSettingsView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @State private var pendingReducedStatusCount: Int?
    @State private var showingStatusCountReductionConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("상태 개수") {
                    Stepper(
                        value: Binding(
                            get: { state.dashboardSettings.statusCount },
                            set: { newCount in
                                if newCount < state.dashboardStatuses.count {
                                    pendingReducedStatusCount = newCount
                                    showingStatusCountReductionConfirmation = true
                                } else {
                                    state.setDashboardStatusCount(newCount)
                                }
                            }
                        ),
                        in: 1...10
                    ) {
                        HStack {
                            Label("프로세스 단계", systemImage: "square.grid.3x3")
                            Spacer()
                            Text("\(state.dashboardSettings.statusCount)개")
                                .font(.body.monospacedDigit().bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("색상 계열") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(DashboardPaletteFamily.allCases, id: \.rawValue) { family in
                                Button {
                                    withAnimation(.snappy) {
                                        state.updateDashboardPaletteFamily(family)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack(spacing: 2) {
                                            ForEach(NativeAppState.dashboardColorPalette(for: family), id: \.self) { hex in
                                                Rectangle()
                                                    .fill(DashboardColor.color(hex: hex))
                                                    .frame(width: 8, height: 16)
                                            }
                                        }
                                        HStack(spacing: 5) {
                                            Text(family.displayName)
                                                .font(.caption.bold())
                                            if state.dashboardSettings.paletteFamily == family {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.tint)
                                            }
                                        }
                                    }
                                    .padding(9)
                                    .background(
                                        state.dashboardSettings.paletteFamily == family
                                            ? Color.accentColor.opacity(0.12)
                                            : AppPalette.cardBackground,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(
                                                state.dashboardSettings.paletteFamily == family
                                                    ? Color.accentColor.opacity(0.7)
                                                    : Color.secondary.opacity(0.16),
                                                lineWidth: 1
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    ForEach(Array(state.dashboardStatuses.enumerated()), id: \.element.id) { index, status in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit().bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Circle()
                                    .fill(DashboardColor.color(hex: status.colorHex))
                                    .frame(width: 18, height: 18)
                                TextField(
                                    "상태 이름",
                                    text: Binding(
                                        get: { status.name },
                                        set: { state.updateDashboardStatus(id: status.id, name: $0) }
                                    )
                                )
                                .font(.body.weight(.medium))
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(state.activeDashboardColorPalette, id: \.self) { hex in
                                        Button {
                                            state.updateDashboardStatus(id: status.id, colorHex: hex)
                                        } label: {
                                            Circle()
                                                .fill(DashboardColor.color(hex: hex))
                                                .frame(width: 28, height: 28)
                                                .overlay {
                                                    if status.colorHex == hex {
                                                        Image(systemName: "checkmark")
                                                            .font(.caption.bold())
                                                            .foregroundStyle(DashboardColor.foregroundColor(hex: hex).opacity(0.85))
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.leading, 30)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: state.removeDashboardStatuses)
                    .onMove(perform: state.moveDashboardStatuses)
                } header: {
                    Text("프로세스 단계 \(state.dashboardStatuses.count)/10")
                } footer: {
                    Text("순서, 이름과 색상 변경은 히트맵과 고객 팝업에 즉시 반영됩니다.")
                }

            }
            .navigationTitle("상태 설정")
            .modifier(InlineNavigationTitleModifier())
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .alert("상태 개수를 줄일까요?", isPresented: $showingStatusCountReductionConfirmation) {
                Button("취소", role: .cancel) {
                    pendingReducedStatusCount = nil
                }
                Button("줄이기", role: .destructive) {
                    if let pendingReducedStatusCount {
                        state.setDashboardStatusCount(pendingReducedStatusCount)
                    }
                    self.pendingReducedStatusCount = nil
                }
            } message: {
                Text("제거되는 단계의 고객은 새 마지막 단계로 이동합니다.")
            }
        }
    }
}

private extension DashboardPaletteFamily {
    var displayName: String {
        switch self {
        case .blue: "파랑"
        case .green: "초록"
        case .purple: "보라"
        case .orange: "주황"
        case .red: "빨강"
        case .gray: "회색"
        }
    }
}

private struct InlineNavigationTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}

private enum DashboardColor {
    static func color(hex: String) -> Color {
        let components = components(hex: hex)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func foregroundColor(hex: String) -> Color {
        let components = components(hex: hex)
        let brightness = (components.red * 0.299) + (components.green * 0.587) + (components.blue * 0.114)
        return brightness < 0.52 ? .white : .black
    }

    private static func components(hex: String) -> (red: Double, green: Double, blue: Double) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
