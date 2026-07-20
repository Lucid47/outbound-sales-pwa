import OutboundSalesCore
import SwiftUI

struct CustomerListManagementView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var renameTarget: CustomerList?
    @State private var moveTarget: CustomerList?
    @State private var archiveTarget: CustomerList?
    @State private var deleteTarget: CustomerList?

    var body: some View {
        List {
            Section {
                if state.customerLists.isEmpty {
                    ContentUnavailableView("사용 중인 리스트 없음", systemImage: "folder")
                } else {
                    ForEach(state.customerLists) { list in
                        listRow(list, isArchived: false)
                    }
                }
            } header: {
                Text("사용 중")
            }

            Section {
                if state.archivedCustomerLists.isEmpty {
                    Text("보관한 고객리스트가 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.archivedCustomerLists) { list in
                        listRow(list, isArchived: true)
                    }
                }
            } header: {
                Text("보관함")
            } footer: {
                Text("보관은 고객과 모든 기록을 유지합니다. 영구삭제는 앱 저장소의 고객, 기록, 사진·음성 파일을 제거하지만 iPhone 연락처는 삭제하지 않습니다.")
            }
        }
        .navigationTitle("리스트 관리")
        .sheet(item: $renameTarget) { list in
            CustomerListRenameSheet(list: list)
                .environmentObject(state)
        }
        .sheet(item: $moveTarget) { list in
            CustomerListMoveSheet(sourceList: list)
                .environmentObject(state)
        }
        .confirmationDialog(
            "고객리스트를 보관할까요?",
            isPresented: Binding(
                get: { archiveTarget != nil },
                set: { if !$0 { archiveTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("보관", role: .destructive) {
                if let archiveTarget { state.archiveCustomerList(id: archiveTarget.id) }
                archiveTarget = nil
            }
            Button("취소", role: .cancel) { archiveTarget = nil }
        } message: {
            Text("고객과 기록은 삭제되지 않으며 보관함에서 복원할 수 있습니다.")
        }
        .alert(
            "영구삭제",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { list in
            Button("영구삭제", role: .destructive) {
                state.permanentlyDeleteCustomerList(id: list.id)
                deleteTarget = nil
            }
            Button("취소", role: .cancel) { deleteTarget = nil }
        } message: { list in
            let impact = state.deletionImpact(for: list.id)
            Text("\(list.name)의 고객 \(impact.customerCount)명, 방문 \(impact.visitLogCount)건, 터치 \(impact.contactLogCount)건, 사진 \(impact.photoLogCount)건을 앱에서 삭제합니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    @ViewBuilder
    private func listRow(_ list: CustomerList, isArchived: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isArchived ? "archivebox.fill" : "folder.fill")
                .font(.title3)
                .foregroundStyle(isArchived ? Color.secondary : Color.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(state.customerCount(in: list.id))명")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !list.sourceFileName.isEmpty {
                    Text(list.sourceFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Menu {
                if isArchived {
                    Button {
                        state.restoreCustomerList(id: list.id)
                    } label: {
                        Label("복원", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        state.selectList(list)
                    } label: {
                        Label("이 리스트 사용", systemImage: "checkmark.circle")
                    }
                    Button {
                        renameTarget = list
                    } label: {
                        Label("이름 변경", systemImage: "pencil")
                    }
                    if state.customerLists.count > 1 && state.customerCount(in: list.id) > 0 {
                        Button {
                            moveTarget = list
                        } label: {
                            Label("고객 전부 이동", systemImage: "arrow.right.arrow.left")
                        }
                    }
                    Button {
                        archiveTarget = list
                    } label: {
                        Label("보관", systemImage: "archivebox")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    deleteTarget = list
                } label: {
                    Label("영구삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("\(list.name) 관리")
        }
        .padding(.vertical, 4)
    }
}

private struct CustomerListRenameSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let list: CustomerList
    @State private var name: String

    init(list: CustomerList) {
        self.list = list
        _name = State(initialValue: list.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("고객리스트 이름", text: $name)
            }
            .navigationTitle("이름 변경")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        state.renameCustomerList(id: list.id, name: name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct CustomerListMoveSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let sourceList: CustomerList
    @State private var targetListId: String?

    private var targets: [CustomerList] {
        state.customerLists.filter { $0.id != sourceList.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(targets) { list in
                        Button {
                            targetListId = list.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(list.name)
                                        .foregroundStyle(.primary)
                                    Text("\(state.customerCount(in: list.id))명")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if targetListId == list.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("이동할 리스트")
                } footer: {
                    Text("\(sourceList.name)의 고객과 연결된 방문·메모·사진·스케줄 기록을 함께 이동합니다.")
                }
            }
            .navigationTitle("고객 전부 이동")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이동") {
                        if let targetListId {
                            state.moveAllCustomers(from: sourceList.id, to: targetListId)
                        }
                        dismiss()
                    }
                    .disabled(targetListId == nil)
                }
            }
        }
    }
}

struct ManagementPeriodsView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var editingPeriod: ManagementPeriod?
    @State private var showingCreate = false
    @State private var closingPeriod: ManagementPeriod?

    var body: some View {
        List {
            periodSection(title: "진행 중", stateFilter: .active)
            periodSection(title: "마감", stateFilter: .closed)
            periodSection(title: "보관", stateFilter: .archived)
        }
        .navigationTitle("관리 기간")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("관리 기간 추가")
                .disabled(state.customerLists.isEmpty)
            }
        }
        .sheet(isPresented: $showingCreate) {
            ManagementPeriodEditor(period: nil)
                .environmentObject(state)
        }
        .sheet(item: $editingPeriod) { period in
            ManagementPeriodEditor(period: period)
                .environmentObject(state)
        }
        .sheet(item: $closingPeriod) { period in
            ManagementPeriodCloseSheet(period: period)
                .environmentObject(state)
        }
    }

    @ViewBuilder
    private func periodSection(title: String, stateFilter: ManagementPeriodState) -> some View {
        let periods = state.managementPeriods
            .filter { $0.state == stateFilter }
            .sorted { $0.startDate > $1.startDate }
        Section(title) {
            if periods.isEmpty {
                Text("없음")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(periods) { period in
                    NavigationLink {
                        ActivityReportView(managementPeriodId: period.id)
                            .environmentObject(state)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(period.name)
                                .font(.headline)
                            Text("\(period.startDate.formatted(date: .numeric, time: .omitted)) - \(period.endDate.formatted(date: .numeric, time: .omitted))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("고객리스트 \(period.customerListIds.count)개")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if period.state == .active {
                            Button("마감") { closingPeriod = period }
                                .tint(.green)
                            Button("수정") { editingPeriod = period }
                                .tint(.blue)
                        } else if period.state == .closed {
                            Button("보관") { state.archiveManagementPeriod(id: period.id) }
                                .tint(.gray)
                        }
                    }
                }
            }
        }
    }
}

private struct ManagementPeriodEditor: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let period: ManagementPeriod?
    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedListIds: Set<String>
    @State private var summaryNote: String

    init(period: ManagementPeriod?) {
        self.period = period
        let today = Calendar.current.startOfDay(for: Date())
        _name = State(initialValue: period?.name ?? "")
        _startDate = State(initialValue: period?.startDate ?? today)
        _endDate = State(initialValue: period?.endDate ?? Calendar.current.date(byAdding: .month, value: 3, to: today) ?? today)
        _selectedListIds = State(initialValue: Set(period?.customerListIds ?? []))
        _summaryNote = State(initialValue: period?.summaryNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    TextField("예: 2026년 하반기", text: $name)
                    DatePicker("시작일", selection: $startDate, displayedComponents: .date)
                    DatePicker("종료일", selection: $endDate, displayedComponents: .date)
                }
                Section("포함할 고객리스트") {
                    ForEach(state.customerLists) { list in
                        Toggle(isOn: Binding(
                            get: { selectedListIds.contains(list.id) },
                            set: { isSelected in
                                if isSelected { selectedListIds.insert(list.id) }
                                else { selectedListIds.remove(list.id) }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(list.name)
                                Text("\(state.customerCount(in: list.id))명")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if period != nil {
                    Section("정리 메모") {
                        TextEditor(text: $summaryNote)
                            .frame(minHeight: 100)
                    }
                }
            }
            .navigationTitle(period == nil ? "관리 기간 추가" : "관리 기간 수정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedListIds.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let period {
            state.updateManagementPeriod(
                id: period.id,
                name: name,
                startDate: startDate,
                endDate: endDate,
                customerListIds: Array(selectedListIds),
                customerIds: period.customerIds,
                colorHex: period.colorHex,
                summaryNote: summaryNote
            )
        } else {
            state.createManagementPeriod(
                name: name,
                startDate: startDate,
                endDate: endDate,
                customerListIds: Array(selectedListIds)
            )
        }
    }
}

private struct ManagementPeriodCloseSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let period: ManagementPeriod
    @State private var summaryNote: String

    init(period: ManagementPeriod) {
        self.period = period
        _summaryNote = State(initialValue: period.summaryNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $summaryNote)
                        .frame(minHeight: 140)
                } header: {
                    Text("마감 메모")
                } footer: {
                    Text("기간의 활동 기록은 그대로 유지되며 나중에 보고서에서 다시 볼 수 있습니다.")
                }
            }
            .navigationTitle("\(period.name) 마감")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("마감") {
                        state.closeManagementPeriod(id: period.id, summaryNote: summaryNote)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ActivityReportView: View {
    @EnvironmentObject private var state: NativeAppState
    let managementPeriodId: String?
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedListId: String?

    init(managementPeriodId: String? = nil) {
        self.managementPeriodId = managementPeriodId
    }

    private var period: ManagementPeriod? {
        managementPeriodId.flatMap { id in state.managementPeriods.first { $0.id == id } }
    }

    private var events: [CustomerActivityEvent] {
        state.activityReport(
            from: managementPeriodId == nil ? startDate : nil,
            to: managementPeriodId == nil ? endDate : nil,
            listIds: selectedListId.map { [$0] },
            managementPeriodId: managementPeriodId
        )
    }

    private var summary: CustomerActivitySummary {
        state.activitySummary(for: events)
    }

    var body: some View {
        List {
            if managementPeriodId == nil {
                Section("조회 조건") {
                    DatePicker("시작일", selection: $startDate, displayedComponents: .date)
                    DatePicker("종료일", selection: $endDate, displayedComponents: .date)
                    Picker("고객리스트", selection: $selectedListId) {
                        Text("전체").tag(String?.none)
                        ForEach(state.customerLists) { list in
                            Text(list.name).tag(Optional(list.id))
                        }
                        ForEach(state.archivedCustomerLists) { list in
                            Text("\(list.name) (보관)").tag(Optional(list.id))
                        }
                    }
                }
            } else if let period {
                Section("관리 기간") {
                    LabeledContent("기간", value: "\(period.startDate.formatted(date: .numeric, time: .omitted)) - \(period.endDate.formatted(date: .numeric, time: .omitted))")
                    LabeledContent("고객리스트", value: "\(period.customerListIds.count)개")
                    if !period.summaryNote.isEmpty {
                        Text(period.summaryNote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("활동 요약") {
                LabeledContent("전체 활동", value: "\(summary.totalCount)건")
                LabeledContent("관리 고객", value: "\(summary.customerCount)명")
                LabeledContent("전화", value: "\(summary.callCount)건")
                LabeledContent("문자", value: "\(summary.messageCount)건")
                LabeledContent("방문", value: "\(summary.visitCount)건")
                LabeledContent("메모", value: "\(summary.memoCount)건")
            }

            Section("활동 내역") {
                if events.isEmpty {
                    Text("선택한 조건의 활동이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: activityIcon(event.kind))
                                .foregroundStyle(activityColor(event.kind))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.headline)
                                if let customerId = event.customerId,
                                   let customer = state.customers.first(where: { $0.id == customerId }) {
                                    Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                                        .font(.subheadline.weight(.semibold))
                                }
                                if !event.detail.isEmpty {
                                    Text(event.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle(period?.name ?? "내 활동")
    }

    private func activityIcon(_ kind: CustomerActivityKind) -> String {
        switch kind {
        case .call: return "phone.fill"
        case .message: return "message.fill"
        case .visit: return "mappin.circle.fill"
        case .photoMemo: return "photo.fill"
        case .voiceMemo: return "waveform"
        case .textMemo: return "note.text"
        case .dashboardStageChanged: return "arrow.triangle.2.circlepath"
        case .scheduleAdded, .scheduleRemoved: return "calendar"
        case .listArchived, .managementPeriodArchived: return "archivebox"
        case .listDeleted: return "trash"
        default: return "clock.arrow.circlepath"
        }
    }

    private func activityColor(_ kind: CustomerActivityKind) -> Color {
        switch kind {
        case .call: return .blue
        case .message: return .teal
        case .visit: return .green
        case .photoMemo, .voiceMemo, .textMemo: return .purple
        case .listDeleted: return .red
        default: return .orange
        }
    }
}
