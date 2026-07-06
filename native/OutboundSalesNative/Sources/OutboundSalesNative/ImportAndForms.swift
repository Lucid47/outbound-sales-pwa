import OutboundSalesCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct ImportView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var companyName = ""
    @State private var listName = ""
    @State private var showingFileImporter = false
    @State private var showingCreateList = false
    @State private var showingAddCustomer = false
    @State private var csvText = """
    이름,전화번호,주소,메모
    홍길동,010-1234-5678,서울 강남구 테헤란로 152,방문 상담
    """

    var body: some View {
        NavigationStack {
            Form {
                Section("고객리스트 정보") {
                    TextField("고객사 이름", text: $companyName)
                    TextField("고객리스트 이름", text: $listName)
                }

                Section("파일에서 가져오기") {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("CSV 파일 선택", systemImage: "doc.badge.plus")
                    }

                    Label("엑셀 파일(.xlsx)은 다음 단계에서 연결합니다.", systemImage: "tablecells")
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
                    OCRImportView()
                        .environmentObject(state)
                }

                Section("CSV 텍스트 붙여넣기") {
                    TextEditor(text: $csvText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)

                    Button {
                        state.importCSV(text: csvText, companyName: companyName, listName: listName)
                    } label: {
                        Label("붙여넣은 CSV 가져오기", systemImage: "square.and.arrow.down")
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
                    state.importFile(url: url, companyName: companyName, listName: listName)
                case .failure:
                    state.importMessage = "파일 선택을 완료하지 못했습니다."
                }
            }
            .sheet(isPresented: $showingCreateList) {
                CreateListView(companyName: companyName, listName: listName)
                    .environmentObject(state)
            }
            .sheet(isPresented: $showingAddCustomer) {
                AddCustomerView()
                    .environmentObject(state)
            }
        }
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

struct OCRImportView: View {
    @EnvironmentObject private var state: NativeAppState
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    #else
    @State private var showingImageImporter = false
    #endif
    @State private var companyName = ""
    @State private var listName = ""
    @State private var headers = ""
    @State private var csvText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("고객사 이름", text: $companyName)
            TextField("고객리스트 이름", text: $listName)
            TextField("열 이름 예: 이름,전화번호,주소,메모", text: $headers)

            #if os(iOS)
            HStack(spacing: 8) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingCamera = true
                    } else {
                        state.ocrMessage = "이 기기에서는 카메라를 사용할 수 없습니다."
                    }
                } label: {
                    Label("카메라로 촬영", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("사진앱에서 선택", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            #else
            Button {
                showingImageImporter = true
            } label: {
                Label("이미지 파일 선택 후 OCR 실행", systemImage: "photo.on.rectangle")
            }
            #endif

            if !csvText.isEmpty {
                TextEditor(text: $csvText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 160)

                Button {
                    state.importCSV(text: csvText, companyName: companyName, listName: listName.isEmpty ? "OCR 고객리스트" : listName, sourceFileName: "ocr-image.csv")
                } label: {
                    Label("OCR CSV를 고객리스트로 저장", systemImage: "square.and.arrow.down")
                }
            }

            Text(state.ocrMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        #if os(iOS)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await recognizePhotoItem(item) }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView { url in
                Task { await recognizeImage(at: url) }
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
            Task {
                let parsedHeaders = headers
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if let csv = await state.recognizeOCRCSV(url: url, headers: parsedHeaders) {
                    csvText = csv
                }
            }
        }
        #endif
    }

    private var parsedHeaders: [String] {
        headers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func recognizeImage(at url: URL) async {
        if let csv = await state.recognizeOCRCSV(url: url, headers: parsedHeaders) {
            csvText = csv
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
            await recognizeImage(at: url)
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
    @State private var companyName: String
    @State private var listName: String

    init(companyName: String = "", listName: String = "") {
        self._companyName = State(initialValue: companyName)
        self._listName = State(initialValue: listName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("고객사 이름", text: $companyName)
                TextField("고객리스트 이름", text: $listName)
            }
            .navigationTitle("리스트 생성")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("생성") {
                        state.createEmptyList(companyName: companyName, listName: listName)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var selectedHistoryCustomer: Customer?

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

                Section("고객별 히스토리") {
                    if state.visibleCustomers.isEmpty {
                        Text("기록 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.visibleCustomers) { customer in
                            Button {
                                selectedHistoryCustomer = customer
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(customer.name.isEmpty ? "이름 없음" : customer.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("\(customer.region ?? extractRegion(customer.address)) · \(customer.phoneNumber.isEmpty ? "연락처 없음" : customer.phoneNumber)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        if let latest = state.latestHistorySummary(for: customer) {
                                            Text("\(latest.title) · \(latest.at, format: .dateTime.month().day().hour().minute())")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("아직 터치 이력 없음")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(state.progressLabel(for: customer))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(progressColor(for: customer).opacity(0.14))
                                        .foregroundStyle(progressColor(for: customer))
                                        .clipShape(Capsule())
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
