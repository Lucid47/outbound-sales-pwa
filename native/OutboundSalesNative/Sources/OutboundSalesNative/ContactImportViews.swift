import OutboundSalesCore
import SwiftUI

#if os(iOS)
import Contacts
import ContactsUI
#endif

private enum ContactImportDestinationMode: String, CaseIterable {
    case existingList
    case newList
}

struct ContactImportDraft: Identifiable {
    let id = UUID()
    var sourceTitle: String
    var defaultListName: String
    var contacts: [ContactImportCustomer]
}

struct ContactImportSaveSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let draft: ContactImportDraft
    @State private var destinationMode: ContactImportDestinationMode = .newList
    @State private var selectedListId = ""
    @State private var listName: String
    @State private var skipDuplicatePhones = true
    @State private var didPrepareDestination = false

    init(draft: ContactImportDraft) {
        self.draft = draft
        self._listName = State(initialValue: draft.defaultListName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("고객리스트") {
                    Picker("저장 방식", selection: $destinationMode) {
                        Text("기존 리스트에 추가").tag(ContactImportDestinationMode.existingList)
                        Text("새 리스트").tag(ContactImportDestinationMode.newList)
                    }
                    .pickerStyle(.segmented)
                    .disabled(state.customerLists.isEmpty)

                    if destinationMode == .existingList {
                        if state.customerLists.isEmpty {
                            Text("아직 기존 고객리스트가 없습니다. 새 리스트로 저장하세요.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("추가할 리스트", selection: $selectedListId) {
                                ForEach(state.customerLists) { list in
                                    Text("\(list.name) · \(state.customers.filter { $0.customerListId == list.id }.count)명")
                                        .tag(list.id)
                                }
                            }
                        }
                    } else {
                        TextField("고객리스트 이름", text: $listName)
                    }

                    LabeledContent("가져오기 방식", value: draft.sourceTitle)
                    LabeledContent("선택된 연락처", value: "\(draft.contacts.count)명")
                }

                Section("중복 처리") {
                    Toggle("전화번호가 이미 있는 고객은 건너뛰기", isOn: $skipDuplicatePhones)
                    Text("앱 안의 기존 고객 전화번호와 비교합니다. 같은 연락처를 여러 그룹에서 선택한 경우도 한 번만 가져옵니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("미리보기") {
                    ForEach(draft.contacts.prefix(8)) { contact in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contact.name.isEmpty ? "이름 없음" : contact.name)
                                .font(.headline)
                            Text(contact.phoneNumber.isEmpty ? "연락처 없음" : contact.phoneNumber)
                                .foregroundStyle(.secondary)
                            if !contact.address.isEmpty {
                                Text(contact.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    if draft.contacts.count > 8 {
                        Text("외 \(draft.contacts.count - 8)명")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("연락처 가져오기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                prepareDefaultDestination()
            }
            .onChange(of: state.customerLists) { _, _ in
                ensureSelectedListIsValid()
            }
        }
    }

    private var canSave: Bool {
        guard !draft.contacts.isEmpty else { return false }
        switch destinationMode {
        case .existingList:
            return state.customerLists.contains { $0.id == selectedListId }
        case .newList:
            return !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func prepareDefaultDestination() {
        guard !didPrepareDestination else { return }
        didPrepareDestination = true
        if let preferredListId = state.selectedListId ?? state.customerLists.first?.id {
            selectedListId = preferredListId
            destinationMode = .existingList
        }
    }

    private func ensureSelectedListIsValid() {
        if state.customerLists.contains(where: { $0.id == selectedListId }) {
            return
        }
        selectedListId = state.selectedListId ?? state.customerLists.first?.id ?? ""
        if state.customerLists.isEmpty {
            destinationMode = .newList
        }
    }

    private func save() {
        switch destinationMode {
        case .existingList:
            state.appendContactCustomers(draft.contacts, to: selectedListId, sourceFileName: "contacts", skipDuplicatePhones: skipDuplicatePhones)
        case .newList:
            state.importContactCustomers(draft.contacts, listName: listName, sourceFileName: "contacts", skipDuplicatePhones: skipDuplicatePhones)
        }
        dismiss()
    }
}

#if os(iOS)
struct ContactPickerSheet: UIViewControllerRepresentable {
    let onSelect: ([ContactImportCustomer]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactPhoneNumbersKey,
            CNContactPostalAddressesKey
        ]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: ([ContactImportCustomer]) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping ([ContactImportCustomer]) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onSelect(ContactImportService.importCustomers(from: contacts))
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(ContactImportService.importCustomers(from: [contact]))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
#endif

struct ContactGroupImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [ContactImportGroup] = []
    @State private var selectedGroupIds = Set<String>()
    @State private var message = ""
    @State private var isLoading = false
    let onImport: (ContactImportDraft) -> Void
    private let service = ContactImportService()

    var body: some View {
        NavigationStack {
            Form {
                Section("연락처 그룹") {
                    if isLoading {
                        ProgressView("연락처 그룹을 불러오는 중...")
                    } else if groups.isEmpty {
                        Text(message.isEmpty ? "가져올 연락처 그룹이 없습니다." : message)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groups) { group in
                            Toggle(isOn: binding(for: group.id)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.name)
                                    Text("\(group.count)명")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !message.isEmpty && !groups.isEmpty {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("그룹 선택")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("새로고침") {
                        Task { await loadGroups() }
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("가져오기") {
                        Task { await importSelectedGroups() }
                    }
                    .disabled(isLoading || selectedGroupIds.isEmpty)
                }
            }
            .task {
                await loadGroups()
            }
        }
    }

    private func binding(for groupId: String) -> Binding<Bool> {
        Binding(
            get: { selectedGroupIds.contains(groupId) },
            set: { isSelected in
                if isSelected {
                    selectedGroupIds.insert(groupId)
                } else {
                    selectedGroupIds.remove(groupId)
                }
            }
        )
    }

    private func loadGroups() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await service.groups()
            message = groups.isEmpty ? "연락처 그룹이 없습니다." : ""
        } catch {
            groups = []
            message = error.localizedDescription
        }
    }

    private func importSelectedGroups() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let contacts = try await service.customers(in: selectedGroupIds)
            let selectedGroups = groups.filter { selectedGroupIds.contains($0.id) }
            let defaultName = selectedGroups.count == 1 ? selectedGroups[0].name : "연락처 그룹 \(selectedGroups.count)개"
            onImport(ContactImportDraft(sourceTitle: "연락처 그룹", defaultListName: defaultName, contacts: contacts))
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
