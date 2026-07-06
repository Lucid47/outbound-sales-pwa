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
            .navigationTitle("연락처 등록")
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
            let result = try await service.export(customers: customers, options: exportOptions)
            state.markContactExportResults(result.customerResults)
            summary = result
            message = "연락처 등록이 완료되었습니다."
            preview = try? await service.preview(customers: customers)
        } catch {
            message = error.localizedDescription
        }
    }
}
