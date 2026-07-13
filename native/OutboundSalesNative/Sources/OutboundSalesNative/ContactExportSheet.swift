import OutboundSalesCore
import SwiftUI

struct ContactExportSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss

    let list: CustomerList
    let customers: [Customer]

    @State private var groupName: String
    @State private var usePrefix = true
    @State private var prefix = "#"
    @State private var suffix = ""
    @State private var duplicateHandling: ContactDuplicateHandling = .skip
    @State private var preview: ContactExportPreview?
    @State private var summary: ContactExportSummary?
    @State private var isLoadingPreview = false
    @State private var isExporting = false
    @State private var message: String?
    @State private var showingCleanup = false

    private let service = ContactExportService()

    init(list: CustomerList, customers: [Customer]) {
        self.list = list
        self.customers = customers
        self._groupName = State(initialValue: list.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("등록 대상") {
                    LabeledContent("고객리스트", value: list.name)
                    LabeledContent("전체 고객", value: "\(customers.count)명")
                    if let preview {
                        LabeledContent("전화번호 있음", value: "\(preview.phoneCount)명")
                        LabeledContent("전화번호 없음", value: "\(preview.noPhoneCount)명")
                        LabeledContent("중복 후보", value: "\(preview.duplicateCandidateCount)명")
                    } else if isLoadingPreview {
                        ProgressView("연락처 중복 확인 중...")
                    } else {
                        Button("중복 미리보기") {
                            Task { await loadPreview() }
                        }
                    }
                }

                Section("그룹") {
                    TextField("연락처 그룹 이름", text: $groupName)
                    Text("같은 이름의 연락처 그룹이 있으면 그 그룹에 추가합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("이름 변경") {
                    Toggle("이름 앞에 접두어 붙이기", isOn: $usePrefix)
                    if usePrefix {
                        TextField("접두어", text: $prefix)
                        Text("예: 홍길동 → \(prefix)홍길동")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("접미어", text: $suffix)
                    if !usePrefix {
                        Text("접두어를 끄면 고객명이 원래 이름 그대로 연락처에 저장됩니다.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("중복 전화번호 처리") {
                    Picker("처리 방식", selection: $duplicateHandling) {
                        ForEach(ContactDuplicateHandling.allCases) { handling in
                            Text(handling.title).tag(handling)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                if let summary {
                    Section("등록 결과") {
                        LabeledContent("신규 등록", value: "\(summary.createdCount)명")
                        LabeledContent("업데이트", value: "\(summary.updatedCount)명")
                        LabeledContent("중복 건너뜀", value: "\(summary.skippedDuplicateCount)명")
                        LabeledContent("전화번호 없음", value: "\(summary.skippedNoPhoneCount)명")
                        LabeledContent("실패", value: "\(summary.failedCount)명")
                    }

                    if !summary.failures.isEmpty {
                        Section("실패 항목") {
                            ForEach(summary.failures) { failure in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(failure.customerName.isEmpty ? "이름 없음" : failure.customerName)
                                        .font(.headline)
                                    Text(failure.phoneNumber.isEmpty ? "전화번호 없음" : failure.phoneNumber)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(failure.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("등록 연락처 관리") {
                    Text("앱이 새로 만든 연락처만 확인해 그룹과 함께 정리합니다. 기존 연락처와 다른 그룹에 속한 연락처는 자동으로 보호합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        showingCleanup = true
                    } label: {
                        Label("등록 연락처 정리", systemImage: "person.crop.circle.badge.minus")
                            .frame(maxWidth: .infinity)
                    }
                }

                Section {
                    Button {
                        Task { await exportContacts() }
                    } label: {
                        if isExporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("연락처에 등록", systemImage: "person.crop.circle.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isExporting || customers.isEmpty || groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("연락처 관리")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadPreview()
            }
            .sheet(isPresented: $showingCleanup) {
                ContactCleanupSheet(
                    list: list,
                    customers: customers,
                    groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? list.name : groupName
                )
                .environmentObject(state)
            }
        }
    }

    private var exportOptions: ContactExportOptions {
        ContactExportOptions(
            groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? list.name : groupName,
            usePrefix: usePrefix,
            prefix: prefix,
            suffix: suffix,
            duplicateHandling: duplicateHandling
        )
    }

    private func loadPreview() async {
        guard !isLoadingPreview else { return }
        isLoadingPreview = true
        message = nil
        defer { isLoadingPreview = false }

        do {
            preview = try await service.preview(customers: customers)
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportContacts() async {
        guard !isExporting else { return }
        isExporting = true
        message = "연락처에 등록하는 중..."
        defer { isExporting = false }

        do {
            let result = try await service.export(customers: customers, customerListId: list.id, options: exportOptions)
            state.recordContactExport(result)
            summary = result
            message = "연락처 등록이 완료되었습니다."
            preview = try? await service.preview(customers: customers)
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ContactCleanupSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss

    let list: CustomerList
    let customers: [Customer]
    let groupName: String

    @State private var mode: ContactCleanupMode = .appCreatedContactsAndGroup
    @State private var preview: ContactCleanupPreview?
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var message: String?
    @State private var showingConfirmation = false

    private let service = ContactCleanupService()

    var body: some View {
        NavigationStack {
            Form {
                Section("삭제 방식") {
                    Picker("삭제 방식", selection: $mode) {
                        ForEach(ContactCleanupMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if isLoading {
                    Section {
                        ProgressView("연락처 소유권 확인 중...")
                    }
                } else if let preview {
                    Section("삭제 미리보기") {
                        LabeledContent("삭제할 앱 생성 연락처", value: "\(mode == .appCreatedContactsAndGroup ? preview.eligibleContacts.count : 0)명")
                        LabeledContent("삭제할 앱 생성 그룹", value: "\(preview.groupCount)개")
                        if preview.legacyCandidateCount > 0 {
                            LabeledContent("과거 등록분 확인", value: "\(preview.legacyCandidateCount)명")
                        }
                    }

                    Section("자동 보호") {
                        LabeledContent("기존 연락처", value: "\(preview.protectedExistingCount)명")
                        LabeledContent("다른 그룹에도 소속", value: "\(preview.otherGroupCount)명")
                        LabeledContent("등록 후 변경됨", value: "\(preview.modifiedCount)명")
                        LabeledContent("이미 없거나 확인 불가", value: "\(preview.missingCount)명")
                        if preview.unownedGroupMemberCount > 0 {
                            LabeledContent("그룹 안의 비소유 연락처", value: "\(preview.unownedGroupMemberCount)명")
                        }
                    }

                    if preview.groupCount == 0 {
                        Section {
                            Text("앱이 만든 그룹이 이미 삭제되었거나 확인되지 않습니다. 앱이 만든 것으로 검증된 연락처만 정리할 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Text("연락처 삭제는 기본 iCloud 또는 Google 연락처 계정과 다른 기기에도 동기화될 수 있습니다. 앱이 만든 것으로 확인된 연락처만 삭제하며 이 작업은 앱에서 되돌릴 수 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingConfirmation = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(deleteButtonTitle, systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isDeleting || !hasAnythingToDelete)
                }
            }
            .navigationTitle("등록 연락처 정리")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task { await loadPreview() }
            .confirmationDialog(
                "연락처를 영구 삭제하시겠습니까?",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button(deleteButtonTitle, role: .destructive) {
                    Task { await cleanup() }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    private var hasAnythingToDelete: Bool {
        guard let preview else { return false }
        return preview.groupCount > 0 || (mode == .appCreatedContactsAndGroup && !preview.eligibleContacts.isEmpty)
    }

    private var deleteButtonTitle: String {
        guard let preview else { return "삭제" }
        if mode == .groupOnly {
            return "그룹 \(preview.groupCount)개 삭제"
        }
        return "연락처 \(preview.eligibleContacts.count)명과 그룹 \(preview.groupCount)개 삭제"
    }

    private var confirmationMessage: String {
        guard let preview else { return "" }
        if mode == .groupOnly {
            return "연락처 원본은 유지하고 앱이 만든 그룹 \(preview.groupCount)개만 삭제합니다."
        }
        return "앱이 만든 것으로 확인된 연락처 \(preview.eligibleContacts.count)명과 그룹 \(preview.groupCount)개를 삭제합니다. 다른 그룹 소속 및 기존 연락처는 제외됩니다."
    }

    private func loadPreview() async {
        guard !isLoading else { return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            preview = try await service.preview(
                customerListId: list.id,
                groupName: groupName,
                customers: currentListCustomers,
                batches: state.contactExportBatches
            )
        } catch {
            message = error.localizedDescription
        }
    }

    private func cleanup() async {
        guard !isDeleting else { return }
        isDeleting = true
        message = "연락처를 안전하게 다시 확인하는 중..."
        defer { isDeleting = false }
        do {
            let result = try await service.cleanup(
                mode: mode,
                customerListId: list.id,
                groupName: groupName,
                customers: currentListCustomers,
                batches: state.contactExportBatches
            )
            state.applyContactCleanup(result)
            await loadPreview()
            message = "연락처 \(result.deletedContactIdentifiers.count)명과 그룹 \(result.deletedGroupIdentifiers.count)개를 삭제했습니다."
        } catch {
            message = error.localizedDescription
        }
    }

    private var currentListCustomers: [Customer] {
        state.customers.filter { $0.customerListId == list.id }
    }
}
