import OutboundSalesCore
import SwiftUI

struct GoogleDriveBackupSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @State private var scope: DriveListScope = .all
    @State private var selectedListIds = Set<String>()

    var body: some View {
        NavigationStack {
            Form {
                Section("백업 범위") {
                    Picker("범위", selection: $scope) {
                        ForEach(DriveListScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if scope == .selected {
                    Section("백업할 고객리스트") {
                        if state.customerLists.isEmpty {
                            Text("백업할 고객리스트가 없습니다.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(state.customerLists) { list in
                                Toggle(isOn: binding(for: list.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.name)
                                        Text("\(state.customers.filter { $0.customerListId == list.id }.count)명")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !state.driveSyncMessage.isEmpty {
                    Section("상태") {
                        Text(state.driveSyncMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Drive 백업")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("백업") {
                        Task {
                            await state.createVisibleGoogleDriveBackup(listIds: scope == .all ? nil : selectedListIds)
                        }
                    }
                    .disabled(state.driveSyncBusy || (scope == .selected && selectedListIds.isEmpty))
                }
            }
        }
    }

    private func binding(for listId: String) -> Binding<Bool> {
        Binding(
            get: { selectedListIds.contains(listId) },
            set: { isSelected in
                if isSelected {
                    selectedListIds.insert(listId)
                } else {
                    selectedListIds.remove(listId)
                }
            }
        )
    }
}

struct GoogleDriveRestoreSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @State private var scope: DriveListScope = .all
    @State private var selectedListIds = Set<String>()
    @State private var didRequestRemoteLists = false

    var body: some View {
        NavigationStack {
            Form {
                Section("복원 방식") {
                    Picker("방식", selection: $scope) {
                        ForEach(DriveListScope.allCases) { scope in
                            Text(scope.restoreTitle).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(scope == .all ? "Drive의 전체 데이터로 이 기기 데이터를 교체합니다." : "선택한 고객리스트만 이 기기에 복원하고, 나머지 로컬 데이터는 유지합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Drive 고객리스트") {
                    if state.driveSyncBusy && state.remoteDriveLists.isEmpty {
                        ProgressView("Drive 데이터 확인 중...")
                    } else if state.remoteDriveLists.isEmpty {
                        Text("Drive에서 고객리스트를 찾지 못했습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.remoteDriveLists) { list in
                            if scope == .selected {
                                Toggle(isOn: binding(for: list.id)) {
                                    listLabel(list)
                                }
                            } else {
                                listLabel(list)
                            }
                        }
                    }
                }

                if !state.driveSyncMessage.isEmpty {
                    Section("상태") {
                        Text(state.driveSyncMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Drive 복원")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("목록 새로고침") {
                        Task { await state.loadRemoteDriveBackup() }
                    }
                    .disabled(state.driveSyncBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("복원") {
                        Task {
                            await state.restoreFromGoogleDrive(listIds: scope == .all ? nil : selectedListIds)
                        }
                    }
                    .disabled(state.driveSyncBusy || state.remoteDriveLists.isEmpty || (scope == .selected && selectedListIds.isEmpty))
                }
            }
            .task {
                guard !didRequestRemoteLists else { return }
                didRequestRemoteLists = true
                await state.loadRemoteDriveBackup()
            }
        }
    }

    private func binding(for listId: String) -> Binding<Bool> {
        Binding(
            get: { selectedListIds.contains(listId) },
            set: { isSelected in
                if isSelected {
                    selectedListIds.insert(listId)
                } else {
                    selectedListIds.remove(listId)
                }
            }
        )
    }

    private func listLabel(_ list: CustomerList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(list.name)
            Text(list.sourceFileName.isEmpty ? "수동 생성" : list.sourceFileName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum DriveListScope: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "전체"
        case .selected: return "선택"
        }
    }

    var restoreTitle: String {
        switch self {
        case .all: return "전체"
        case .selected: return "선택"
        }
    }
}
