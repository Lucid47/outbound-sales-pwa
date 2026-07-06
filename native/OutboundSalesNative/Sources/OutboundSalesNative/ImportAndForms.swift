import OutboundSalesCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct ImportView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var showingFileImporter = false
    @State private var showingCreateList = false
    @State private var showingAddCustomer = false
    @State private var importDraft: ImportDraft?
    @State private var pastedCSV = """
    이름,전화번호,주소,메모
    홍길동,010-1234-5678,서울 강남구 테헤란로 152,방문 상담
    """
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    #else
    @State private var showingImageImporter = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("파일에서 가져오기") {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("CSV 파일 선택", systemImage: "doc.badge.plus")
                    }

                    Label("파일을 읽은 뒤 컬럼 매핑 팝업을 표시합니다.", systemImage: "tablecells")
                        .foregroundStyle(.secondary)
                }

                Section("직접 만들기") {
                    Button {
                        showingCreateList = true
                    } label: {
                        Label("빈 고객리스트 생성", systemImage: "folder.badge.plus")
                    }

                    Button {
                        showingAddCustomer = true
                    } label: {
                        Label("선택 리스트에 고객 수동 추가", systemImage: "person.badge.plus")
                    }
                    .disabled(state.selectedListId == nil)
                }

                Section("사진에서 가져오기") {
                    #if os(iOS)
                    HStack(spacing: 8) {
                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingCamera = true
                            } else {
                                state.ocrMessage = "이 기기에서는 카메라를 사용할 수 없습니다."
                            }
                        } label: {
                            ImportSourceButtonLabel(title: "카메라", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            ImportSourceButtonLabel(title: "사진앱", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.bordered)
                    }
                    #else
                    Button {
                        showingImageImporter = true
                    } label: {
                        Label("이미지 파일 선택", systemImage: "photo.on.rectangle")
                    }
                    #endif

                    Text(state.ocrMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("CSV 텍스트 붙여넣기") {
                    TextEditor(text: $pastedCSV)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)

                    Button {
                        presentMappingPopup(text: pastedCSV, sourceFileName: "붙여넣기.csv", sourceTitle: "텍스트 붙여넣기")
                    } label: {
                        Label("붙여넣은 CSV 매핑", systemImage: "tablecells")
                    }
                }

                if !state.importMessage.isEmpty {
                    Text(state.importMessage)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("가져오기")
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: ImportFileType.allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    loadCSVFile(url: url)
                case .failure:
                    state.importMessage = "파일 선택을 완료하지 못했습니다."
                }
            }
            .sheet(isPresented: $showingCreateList) {
                CreateListView()
                    .environmentObject(state)
            }
            .sheet(isPresented: $showingAddCustomer) {
                AddCustomerView()
                    .environmentObject(state)
            }
            .sheet(item: $importDraft) { draft in
                ImportMappingSheet(draft: draft)
                    .environmentObject(state)
            }
            #if os(iOS)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { await recognizePhotoItem(item) }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { url in
                    Task { await recognizeImage(at: url, sourceTitle: "카메라 촬영") }
                }
            }
            #else
            .fileImporter(
                isPresented: $showingImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else {
                    state.ocrMessage = "사진 선택을 완료하지 못했습니다."
                    return
                }
                Task { await recognizeImage(at: url, sourceTitle: "이미지 파일") }
            }
            #endif
        }
    }

    private func loadCSVFile(url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension != "xlsx" && fileExtension != "xls" else {
            state.importMessage = "엑셀 파일 가져오기는 다음 단계에서 연결합니다. 현재는 CSV 파일을 사용할 수 있습니다."
            return
        }

        do {
            let text = try decodeCSVText(data: Data(contentsOf: url))
            presentMappingPopup(text: text, sourceFileName: fileName, sourceTitle: "파일 가져오기")
        } catch {
            state.importMessage = "CSV 파일을 읽지 못했습니다. UTF-8, UTF-16, CP949, EUC-KR CSV를 지원합니다."
        }
    }

    private func presentMappingPopup(text: String, sourceFileName: String, sourceTitle: String) {
        guard !parseCSVRows(text).isEmpty else {
            state.importMessage = "읽을 데이터가 없습니다."
            return
        }
        importDraft = ImportDraft(
            sourceTitle: sourceTitle,
            sourceFileName: sourceFileName,
            rawText: text,
            defaultListName: defaultListName(from: sourceFileName)
        )
    }

    private func recognizeImage(at url: URL, sourceTitle: String) async {
        if let csv = await state.recognizeOCRCSV(url: url, headers: []) {
            presentMappingPopup(text: csv, sourceFileName: "ocr-image.csv", sourceTitle: sourceTitle)
        }
    }

    #if os(iOS)
    private func recognizePhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                state.ocrMessage = "사진을 읽지 못했습니다."
                return
            }
            let url = try writeTemporaryImage(data: data, extension: "image")
            await recognizeImage(at: url, sourceTitle: "사진앱")
        } catch {
            state.ocrMessage = "사진을 읽지 못했습니다."
        }
    }

    private func writeTemporaryImage(data: Data, extension pathExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try data.write(to: url, options: [.atomic])
        return url
    }
    #endif
}

private struct ImportSourceButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.body.weight(.semibold))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .contentShape(Rectangle())
    }
}

struct ImportDraft: Identifiable {
    let id = UUID()
    let sourceTitle: String
    let sourceFileName: String
    let rawText: String
    let defaultListName: String
}

private enum ImportDestinationMode: String, CaseIterable {
    case existingList
    case newList
}

struct ImportMappingSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let draft: ImportDraft
    @State private var destinationMode: ImportDestinationMode = .newList
    @State private var selectedListId = ""
    @State private var listName: String
    @State private var firstRowIsHeader = true
    @State private var parsed: ParsedCSV?
    @State private var message = ""
    @State private var didPrepareDestination = false

    init(draft: ImportDraft) {
        self.draft = draft
        self._listName = State(initialValue: draft.defaultListName)
        self._parsed = State(initialValue: try? parseCSV(draft.rawText, firstRowIsHeader: true))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("고객리스트") {
                    Picker("저장 방식", selection: $destinationMode) {
                        Text("기존 리스트에 추가").tag(ImportDestinationMode.existingList)
                        Text("새 리스트").tag(ImportDestinationMode.newList)
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
                }

                Section {
                    Toggle("첫 행을 헤더로 사용", isOn: $firstRowIsHeader)

                    if let parsed {
                        ForEach(FieldKey.allCases, id: \.self) { field in
                            Picker(fieldLabel(field), selection: mappingSelection(field)) {
                                Text("사용 안 함").tag(-1)
                                ForEach(parsed.headers.indices, id: \.self) { index in
                                    Text("\(index + 1). \(parsed.headers[index])").tag(index)
                                }
                            }
                        }
                    } else {
                        Text("데이터를 분석하지 못했습니다.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("헤더 매핑")
                } footer: {
                    Text("헤더 이름이 인식되면 먼저 자동 매핑합니다. 필요하면 여기서 직접 바꾸세요.")
                }

                if let parsed, let firstRow = parsed.rows.first {
                    Section("첫 데이터 미리보기") {
                        ForEach(parsed.headers.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(index + 1). \(parsed.headers[index])")
                                    .font(.caption.weight(.semibold))
                                Text(index < firstRow.count ? firstRow[index] : "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if !message.isEmpty {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("가져오기 확인")
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
            .onChange(of: firstRowIsHeader) { _, _ in
                reloadParsed()
            }
            .onChange(of: state.customerLists) { _, _ in
                ensureSelectedListIsValid()
            }
        }
    }

    private var canSave: Bool {
        guard parsed != nil else { return false }
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

    private func reloadParsed() {
        do {
            parsed = try parseCSV(draft.rawText, firstRowIsHeader: firstRowIsHeader)
            message = ""
        } catch {
            parsed = nil
            message = "데이터를 읽지 못했습니다."
        }
    }

    private func mappingSelection(_ field: FieldKey) -> Binding<Int> {
        Binding(
            get: {
                parsed?.mapping[field] ?? -1
            },
            set: { value in
                guard var next = parsed else { return }
                next.mapping[field] = value < 0 ? nil : value
                parsed = next
            }
        )
    }

    private func save() {
        guard let parsed else {
            message = "먼저 데이터를 분석하세요."
            return
        }
        guard parsed.mapping[.name] != nil else {
            message = "고객명으로 사용할 열을 선택하세요."
            return
        }
        guard parsed.mapping[.phoneNumber] != nil || parsed.mapping[.address] != nil else {
            message = "연락처 또는 주소 열 중 하나는 필요합니다."
            return
        }
        switch destinationMode {
        case .existingList:
            guard state.customerLists.contains(where: { $0.id == selectedListId }) else {
                message = "추가할 기존 고객리스트를 선택하세요."
                return
            }
            state.appendParsedCSV(parsed, to: selectedListId, sourceFileName: draft.sourceFileName)
        case .newList:
            let trimmedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedListName.isEmpty else {
                message = "고객리스트 이름을 입력하세요."
                return
            }
            state.importParsedCSV(parsed, listName: trimmedListName, sourceFileName: draft.sourceFileName)
        }
        dismiss()
    }
}

enum ImportFileType {
    static let excelWorkbook = UTType(filenameExtension: "xlsx") ?? .data
    static let legacyExcelWorkbook = UTType(filenameExtension: "xls") ?? .data
    static let allowedTypes: [UTType] = [
        .commaSeparatedText,
        .plainText,
        excelWorkbook,
        legacyExcelWorkbook
    ]
}

private func fieldLabel(_ field: FieldKey) -> String {
    switch field {
    case .name:
        return "고객명"
    case .phoneNumber:
        return "연락처"
    case .address:
        return "주소"
    case .birthDate:
        return "생년월일"
    case .notes:
        return "메모"
    case .latitude:
        return "위도"
    case .longitude:
        return "경도"
    }
}

private func defaultListName(from sourceFileName: String) -> String {
    let url = URL(fileURLWithPath: sourceFileName)
    let baseName = url.deletingPathExtension().lastPathComponent
    return baseName.isEmpty ? "새 고객리스트" : baseName
}

#if os(iOS)
struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (URL) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (URL) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            defer { dismiss() }
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.92) else {
                return
            }
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("camera-ocr-\(UUID().uuidString)")
                    .appendingPathExtension("jpg")
                try data.write(to: url, options: [.atomic])
                onCapture(url)
            } catch {
                return
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
#endif

struct AddCustomerView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @State private var targetListId: String
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var address = ""
    @State private var notes = ""

    init(initialListId: String? = nil) {
        self._targetListId = State(initialValue: initialListId ?? "")
    }

    private var selectedList: String {
        if !targetListId.isEmpty {
            return targetListId
        }
        return state.selectedListId ?? state.customerLists.first?.id ?? ""
    }

    private var selectedListName: String {
        state.customerLists.first { $0.id == selectedList }?.name ?? "선택된 리스트 없음"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("추가할 고객리스트") {
                    if state.customerLists.isEmpty {
                        Text("먼저 고객리스트를 생성하세요.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("고객리스트", selection: $targetListId) {
                            ForEach(state.customerLists) { list in
                                Text(list.name).tag(list.id)
                            }
                        }
                        LabeledContent("대상", value: selectedListName)
                    }
                }

                TextField("이름", text: $name)
                TextField("연락처", text: $phoneNumber)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
                TextField("주소", text: $address, axis: .vertical)
                TextField("메모", text: $notes, axis: .vertical)
            }
            .navigationTitle("고객 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        state.addCustomer(to: selectedList, name: name, phoneNumber: phoneNumber, address: address, notes: notes)
                        dismiss()
                    }
                    .disabled(selectedList.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if targetListId.isEmpty {
                    targetListId = state.selectedListId ?? state.customerLists.first?.id ?? ""
                }
            }
        }
    }
}

struct CreateListView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @State private var listName: String

    init(listName: String = "") {
        self._listName = State(initialValue: listName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("고객리스트 이름", text: $listName)
            }
            .navigationTitle("리스트 생성")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("생성") {
                        state.createEmptyList(listName: listName)
                        dismiss()
                    }
                    .disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var selectedHistoryCustomer: Customer?
    @State private var startDate = Calendar.current.date(
        byAdding: .day,
        value: -30,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    @State private var endDate = Date()

    private var historyPreviews: [CustomerHistoryPreview] {
        guard let dateRange else { return [] }
        return state.visibleCustomers.compactMap { customer in
            let logs = state.logs(for: customer).filter { dateRange.contains($0.0) }
            guard let latest = logs.first else { return nil }
            return CustomerHistoryPreview(customer: customer, latest: latest, count: logs.count)
        }
    }

    private var dateRange: ClosedRange<Date>? {
        let start = Calendar.current.startOfDay(for: startDate)
        guard let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate),
              start <= end else {
            return nil
        }
        return start...end
    }

    private var periodLogCount: Int {
        historyPreviews.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("누적 상태") {
                    LabeledContent("전체 고객", value: "\(state.visibleCustomers.count)")
                    LabeledContent("터치 기록", value: "\(state.contactLogs.count)")
                    LabeledContent("방문 기록", value: "\(state.visitLogs.count)")
                    LabeledContent("완료 고객", value: "\(state.doneCustomerCount)")
                    LabeledContent("미완료 고객", value: "\(state.openCustomerCount)")
                }

                Section("조회 기간") {
                    DatePicker("시작날짜", selection: $startDate, displayedComponents: .date)
                    DatePicker("종료날짜", selection: $endDate, displayedComponents: .date)
                    if dateRange == nil {
                        Text("시작날짜가 종료날짜보다 늦습니다.")
                            .foregroundStyle(.red)
                    } else {
                        LabeledContent("기간 내 고객", value: "\(historyPreviews.count)명")
                        LabeledContent("기간 내 이력", value: "\(periodLogCount)건")
                    }
                }

                Section("기간 내 고객별 히스토리") {
                    if state.visibleCustomers.isEmpty {
                        Text("기록 없음")
                            .foregroundStyle(.secondary)
                    } else if dateRange == nil {
                        Text("조회 기간을 다시 선택하세요.")
                            .foregroundStyle(.secondary)
                    } else if historyPreviews.isEmpty {
                        Text("선택한 기간에 터치 이력이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(historyPreviews) { preview in
                            Button {
                                selectedHistoryCustomer = preview.customer
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preview.customer.name.isEmpty ? "이름 없음" : preview.customer.name)
                                            .font(.title3.weight(.heavy))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.82)
                                        Text("\(preview.customer.region ?? extractRegion(preview.customer.address)) · \(preview.customer.phoneNumber.isEmpty ? "연락처 없음" : preview.customer.phoneNumber)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text("\(preview.latest.1) · \(preview.latest.0, format: .dateTime.month().day().hour().minute())")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(state.progressLabel(for: preview.customer))
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(progressColor(for: preview.customer).opacity(0.14))
                                            .foregroundStyle(progressColor(for: preview.customer))
                                            .clipShape(Capsule())
                                        Text("\(preview.count)건")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("기록")
            .sheet(item: $selectedHistoryCustomer) { customer in
                CustomerHistorySheet(customer: customer)
                    .environmentObject(state)
            }
        }
    }

    private func progressColor(for customer: Customer) -> Color {
        if customer.status == .done { return .green }
        return state.logs(for: customer).isEmpty ? .secondary : .orange
    }
}

private struct CustomerHistoryPreview: Identifiable {
    let customer: Customer
    let latest: (Date, String, String)
    let count: Int

    var id: String { customer.id }
}

struct SettingsView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var showingResetConfirmation = false
    @State private var showingBackupImporter = false
    @State private var showingBackupExporter = false
    @State private var backupFile: BackupDocument?

    var body: some View {
        NavigationStack {
            List {
                Section("로컬 저장") {
                    LabeledContent("상태", value: state.storageMessage.isEmpty ? "대기 중" : state.storageMessage)
                    Button {
                        do {
                            backupFile = BackupDocument(data: try state.exportSnapshotData())
                            showingBackupExporter = true
                        } catch {
                            backupFile = nil
                        }
                    } label: {
                        Label("JSON 백업 내보내기", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingBackupImporter = true
                    } label: {
                        Label("JSON 백업 가져오기", systemImage: "square.and.arrow.down")
                    }

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("로컬 데이터 초기화", systemImage: "trash")
                    }
                }

                Section("네이티브 앱") {
                    Label("고객리스트와 고객 정보는 기기 안에 저장합니다.", systemImage: "externaldrive")
                    Label("Google Drive 동기화는 계정 연동 단계에서 별도 연결합니다.", systemImage: "icloud")
                }

                Section("문자 템플릿") {
                    ForEach(state.messageTemplates) { template in
                        NavigationLink {
                            TemplateEditorView(template: template)
                                .environmentObject(state)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.title)
                                Text(template.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    NavigationLink {
                        TemplateEditorView(template: nil)
                            .environmentObject(state)
                    } label: {
                        Label("새 템플릿 추가", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("설정")
            .confirmationDialog("로컬 데이터를 초기화할까요?", isPresented: $showingResetConfirmation) {
                Button("초기화", role: .destructive) {
                    state.resetLocalData()
                }
                Button("취소", role: .cancel) {}
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    state.importSnapshot(url: url)
                }
            }
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupFile ?? BackupDocument(),
                contentType: .json,
                defaultFilename: "outbound-sales-backup.json"
            ) { _ in }
        }
    }
}

struct TemplateEditorView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let template: MessageTemplate?
    @State private var title: String
    @State private var templateBody: String
    @State private var isDefault: Bool

    init(template: MessageTemplate?) {
        self.template = template
        self._title = State(initialValue: template?.title ?? "")
        self._templateBody = State(initialValue: template?.body ?? "")
        self._isDefault = State(initialValue: template?.isDefault ?? false)
    }

    var body: some View {
        Form {
            Section("템플릿") {
                TextField("제목", text: $title)
                TextEditor(text: $templateBody)
                    .frame(minHeight: 140)
                Toggle("기본 템플릿", isOn: $isDefault)
            }

            if let template {
                Section {
                    Button("삭제", role: .destructive) {
                        state.deleteMessageTemplate(template)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(template == nil ? "템플릿 추가" : "템플릿 수정")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    if let template {
                        state.updateMessageTemplate(template, title: title, body: templateBody, isDefault: isDefault)
                    } else {
                        state.createMessageTemplate(title: title, body: templateBody)
                    }
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || templateBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
