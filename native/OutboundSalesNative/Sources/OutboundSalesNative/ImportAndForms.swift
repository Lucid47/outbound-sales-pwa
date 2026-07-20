import OutboundSalesCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import Contacts
import ContactsUI
import PhotosUI
import UIKit
#endif

struct ImportView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var showingFileImporter = false
    @State private var showingCreateList = false
    @State private var showingAddCustomer = false
    @State private var importDraft: ImportDraft?
    @State private var contactImportDraft: ContactImportDraft?
    @State private var pastedCSV = """
    이름,전화번호,주소,메모
    홍길동,010-1234-5678,서울 강남구 테헤란로 152,방문 상담
    """
    #if os(iOS)
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingOCRPhotos: [OCRPhotoSelection] = []
    @State private var showingPhotoImportConfirmation = false
    @State private var isPreparingPhotos = false
    @State private var isRecognizingPhotos = false
    @State private var showingCamera = false
    @State private var showingContactPicker = false
    @State private var showingContactGroupPicker = false
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

                #if os(iOS)
                Section("연락처에서 가져오기") {
                    Button {
                        showingContactPicker = true
                    } label: {
                        Label("개별 연락처 선택", systemImage: "person.crop.circle.badge.plus")
                    }

                    Button {
                        showingContactGroupPicker = true
                    } label: {
                        Label("연락처 그룹 선택", systemImage: "person.3.sequence")
                    }

                    Text("선택한 연락처를 새 고객리스트로 저장하거나 기존 리스트에 추가합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                #endif

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
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 20,
                            selectionBehavior: .ordered,
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

                    if isPreparingPhotos || isRecognizingPhotos {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(isPreparingPhotos ? "선택한 사진을 준비하는 중..." : state.ocrMessage)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(state.ocrMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
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
            .sheet(item: $contactImportDraft) { draft in
                ContactImportSaveSheet(draft: draft)
                    .environmentObject(state)
            }
            #if os(iOS)
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await preparePhotoItems(items) }
            }
            .sheet(isPresented: $showingPhotoImportConfirmation) {
                OCRPhotoImportConfirmationSheet(photos: pendingOCRPhotos) {
                    showingPhotoImportConfirmation = false
                    let photos = pendingOCRPhotos
                    Task { await recognizePhotos(photos, sourceTitle: "사진앱") }
                } onCancel: {
                    clearPendingPhotos()
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPickerSheet { contacts in
                    showingContactPicker = false
                    presentContactImport(contacts, sourceTitle: "연락처 선택", defaultListName: "연락처 가져오기")
                } onCancel: {
                    showingContactPicker = false
                }
            }
            .sheet(isPresented: $showingContactGroupPicker) {
                ContactGroupImportSheet { draft in
                    contactImportDraft = draft
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { url in
                    prepareCameraPhoto(url)
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

    private func presentContactImport(_ contacts: [ContactImportCustomer], sourceTitle: String, defaultListName: String) {
        guard !contacts.isEmpty else {
            state.importMessage = "선택한 연락처에서 가져올 이름 또는 전화번호를 찾지 못했습니다."
            return
        }
        contactImportDraft = ContactImportDraft(
            sourceTitle: sourceTitle,
            defaultListName: defaultListName,
            contacts: contacts
        )
    }

    private func recognizeImage(at url: URL, sourceTitle: String) async {
        if let csv = await state.recognizeOCRCSV(url: url, headers: []) {
            presentMappingPopup(text: csv, sourceFileName: "ocr-image.csv", sourceTitle: sourceTitle)
        }
    }

    #if os(iOS)
    private func preparePhotoItems(_ items: [PhotosPickerItem]) async {
        isPreparingPhotos = true
        defer {
            isPreparingPhotos = false
            selectedPhotoItems = []
        }
        var prepared: [OCRPhotoSelection] = []
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let url = try writeTemporaryImage(data: data, extension: "image")
                prepared.append(OCRPhotoSelection(order: index, url: url, previewData: data))
            } catch {
                continue
            }
        }
        guard !prepared.isEmpty else {
            state.ocrMessage = "선택한 사진을 읽지 못했습니다."
            return
        }
        pendingOCRPhotos = prepared
        showingPhotoImportConfirmation = true
    }

    private func prepareCameraPhoto(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            pendingOCRPhotos = [OCRPhotoSelection(order: 0, url: url, previewData: data)]
            showingPhotoImportConfirmation = true
        } catch {
            state.ocrMessage = "촬영한 사진을 읽지 못했습니다."
        }
    }

    private func recognizePhotos(_ photos: [OCRPhotoSelection], sourceTitle: String) async {
        guard !photos.isEmpty else { return }
        isRecognizingPhotos = true
        var csvDocuments: [String] = []
        for (index, photo) in photos.sorted(by: { $0.order < $1.order }).enumerated() {
            state.ocrMessage = "사진 OCR 처리 중: \(index + 1)/\(photos.count)"
            if let csv = await state.recognizeOCRCSV(url: photo.url, headers: []) {
                csvDocuments.append(csv)
            }
        }
        isRecognizingPhotos = false
        defer { clearPendingPhotos() }
        guard let mergedCSV = mergeOCRCSVDocuments(csvDocuments) else {
            state.ocrMessage = "선택한 사진에서 표 데이터를 만들지 못했습니다."
            return
        }
        state.ocrMessage = "OCR 완료: \(csvDocuments.count)/\(photos.count)장 인식"
        presentMappingPopup(text: mergedCSV, sourceFileName: "ocr-images.csv", sourceTitle: sourceTitle)
    }

    private func clearPendingPhotos() {
        for photo in pendingOCRPhotos {
            try? FileManager.default.removeItem(at: photo.url)
        }
        pendingOCRPhotos = []
        selectedPhotoItems = []
        showingPhotoImportConfirmation = false
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
private struct OCRPhotoSelection: Identifiable {
    let id = UUID()
    let order: Int
    let url: URL
    let previewData: Data
}

private struct OCRPhotoImportConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [OCRPhotoSelection]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("선택한 \(photos.count)장의 사진을 순서대로 읽어 하나의 고객리스트로 합칩니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(photos.sorted(by: { $0.order < $1.order })) { photo in
                            VStack(spacing: 6) {
                                if let image = UIImage(data: photo.previewData) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 112, height: 144)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "photo")
                                        .frame(width: 112, height: 144)
                                        .background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text("\(photo.order + 1)번째")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("사진 가져오기 확인")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OCR 시작") {
                        onConfirm()
                        dismiss()
                    }
                }
            }
        }
    }
}
#endif

private func mergeOCRCSVDocuments(_ documents: [String]) -> String? {
    let parsedDocuments = documents.compactMap { try? parseCSV($0, firstRowIsHeader: true) }
    guard let reference = parsedDocuments.max(by: { $0.headers.count < $1.headers.count }) else { return nil }
    let headers = reference.headers
    let normalizedHeaders = headers.map(normalizeHeader)
    var rows: [[String]] = []

    for parsed in parsedDocuments {
        var pageRows: [[String]] = []
        for sourceRow in parsed.rows {
            let row = (0..<headers.count).map { index in index < sourceRow.count ? sourceRow[index] : "" }
            let normalized = row.map(normalizeHeader)
            let isRepeatedHeader = zip(normalized, normalizedHeaders)
                .filter { !$0.0.isEmpty && $0.0 == $0.1 }
                .count >= max(2, headers.count / 2)
            guard !isRepeatedHeader, normalized.contains(where: { !$0.isEmpty }) else { continue }
            pageRows.append(row)
        }

        let maximumOverlap = min(12, rows.count, pageRows.count)
        var overlapCount = 0
        if maximumOverlap > 0 {
            for candidate in stride(from: maximumOverlap, through: 1, by: -1) {
                let previous = rows.suffix(candidate).map(ocrRowFingerprint)
                let current = pageRows.prefix(candidate).map(ocrRowFingerprint)
                if previous == current {
                    overlapCount = candidate
                    break
                }
            }
        }
        rows.append(contentsOf: pageRows.dropFirst(overlapCount))
    }
    return makeCSV(rows: [headers] + rows)
}

private func ocrRowFingerprint(_ row: [String]) -> String {
    row.map(normalizeHeader).joined(separator: "|")
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
    @State private var selectedRowIndices: Set<Int>
    @State private var message = ""
    @State private var didPrepareDestination = false

    init(draft: ImportDraft) {
        self.draft = draft
        let initialParsed = try? parseCSV(draft.rawText, firstRowIsHeader: true)
        self._listName = State(initialValue: draft.defaultListName)
        self._parsed = State(initialValue: initialParsed)
        self._selectedRowIndices = State(initialValue: Set(initialParsed?.rows.indices ?? 0..<0))
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

                if let parsed {
                    Section {
                        HStack {
                            Button("정상 신규만") { selectRecommendedRows() }
                            Spacer()
                            Button("전체 선택") { selectedRowIndices = Set(parsed.rows.indices) }
                            Button("전체 해제") { selectedRowIndices = [] }
                        }
                        .font(.subheadline.weight(.semibold))

                        LabeledContent("선택", value: "\(selectedRowIndices.count)/\(parsed.rows.count)명")

                        ForEach(parsed.rows.indices, id: \.self) { index in
                            Button {
                                if selectedRowIndices.contains(index) {
                                    selectedRowIndices.remove(index)
                                } else {
                                    selectedRowIndices.insert(index)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selectedRowIndices.contains(index) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedRowIndices.contains(index) ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(rowTitle(parsed.rows[index], parsed: parsed, index: index))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(rowSubtitle(parsed.rows[index], parsed: parsed))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if !rowIsValid(parsed.rows[index], parsed: parsed) {
                                        Text("확인 필요")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.orange)
                                    } else if rowIsDuplicate(parsed.rows[index], parsed: parsed, index: index) {
                                        Text("중복")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("가져올 고객 선택")
                    } footer: {
                        Text("정상 신규 고객만 기본 선택합니다. 중복 또는 확인이 필요한 행도 직접 선택하면 가져올 수 있습니다.")
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
                selectRecommendedRows()
            }
            .onChange(of: firstRowIsHeader) { _, _ in
                reloadParsed()
            }
            .onChange(of: state.customerLists) { _, _ in
                ensureSelectedListIsValid()
            }
            .onChange(of: destinationMode) { _, _ in
                selectRecommendedRows()
            }
            .onChange(of: selectedListId) { _, _ in
                selectRecommendedRows()
            }
        }
    }

    private var canSave: Bool {
        guard parsed != nil, !selectedRowIndices.isEmpty else { return false }
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
            selectedRowIndices = Set(parsed?.rows.indices ?? 0..<0)
            selectRecommendedRows()
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
                selectRecommendedRows()
            }
        )
    }

    private func save() {
        guard var parsed else {
            message = "먼저 데이터를 분석하세요."
            return
        }
        guard parsed.mapping[.name] != nil else {
            message = "고객명으로 사용할 열을 선택하세요."
            return
        }
        guard parsed.mapping[.phoneNumber] != nil || parsed.mapping[.address] != nil || parsed.mapping[.ownedAddress] != nil || parsed.mapping[.parcelAddress] != nil else {
            message = "연락처 또는 주소 관련 열 중 하나는 필요합니다."
            return
        }
        parsed.rows = parsed.rows.indices
            .filter(selectedRowIndices.contains)
            .map { parsed.rows[$0] }
        guard !parsed.rows.isEmpty else {
            message = "가져올 고객을 한 명 이상 선택하세요."
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

    private func selectRecommendedRows() {
        guard let parsed else { return }
        selectedRowIndices = Set(parsed.rows.indices.filter { index in
            rowIsValid(parsed.rows[index], parsed: parsed) && !rowIsDuplicate(parsed.rows[index], parsed: parsed, index: index)
        })
    }

    private func mappedValue(_ field: FieldKey, row: [String], parsed: ParsedCSV) -> String {
        guard let index = parsed.mapping[field], index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rowIsValid(_ row: [String], parsed: ParsedCSV) -> Bool {
        let name = mappedValue(.name, row: row, parsed: parsed)
        let contactValues = [
            mappedValue(.phoneNumber, row: row, parsed: parsed),
            mappedValue(.address, row: row, parsed: parsed),
            mappedValue(.ownedAddress, row: row, parsed: parsed),
            mappedValue(.parcelAddress, row: row, parsed: parsed)
        ]
        return !name.isEmpty && contactValues.contains { !$0.isEmpty }
    }

    private func rowIsDuplicate(_ row: [String], parsed: ParsedCSV, index: Int) -> Bool {
        let phone = normalizedPhone(mappedValue(.phoneNumber, row: row, parsed: parsed))
        let name = normalizeHeader(mappedValue(.name, row: row, parsed: parsed))
        let address = normalizeHeader(mappedValue(.address, row: row, parsed: parsed))
        if !phone.isEmpty {
            if destinationCustomers.contains(where: { normalizedPhone($0.phoneNumber) == phone }) { return true }
            return parsed.rows.indices.contains { previousIndex in
                previousIndex < index && normalizedPhone(mappedValue(.phoneNumber, row: parsed.rows[previousIndex], parsed: parsed)) == phone
            }
        }
        guard !name.isEmpty, !address.isEmpty else { return false }
        return destinationCustomers.contains { customer in
            normalizeHeader(customer.name) == name && normalizeHeader(customer.address) == address
        }
    }

    private var destinationCustomers: [Customer] {
        guard destinationMode == .existingList else { return [] }
        return state.customers.filter { $0.customerListId == selectedListId }
    }

    private func normalizedPhone(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private func rowTitle(_ row: [String], parsed: ParsedCSV, index: Int) -> String {
        let name = mappedValue(.name, row: row, parsed: parsed)
        return name.isEmpty ? "\(index + 1)행 · 이름 확인 필요" : "\(index + 1)행 · \(name)"
    }

    private func rowSubtitle(_ row: [String], parsed: ParsedCSV) -> String {
        let values = [
            mappedValue(.phoneNumber, row: row, parsed: parsed),
            mappedValue(.address, row: row, parsed: parsed),
            mappedValue(.ownedAddress, row: row, parsed: parsed),
            mappedValue(.parcelAddress, row: row, parsed: parsed)
        ].filter { !$0.isEmpty }
        return values.isEmpty ? "연락처 또는 주소 없음" : values.joined(separator: " · ")
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
        return "대표 주소"
    case .ownedAddress:
        return "소유지 주소"
    case .parcelAddress:
        return "지번·필지"
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
    @State private var selectedStatusFilter: HistoryStatusFilter = .all
    @State private var isDateFilterEnabled = false
    @State private var startDate = Calendar.current.date(
        byAdding: .day,
        value: -30,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    @State private var endDate = Date()

    private var historyPreviews: [CustomerHistoryPreview] {
        guard !isDateFilterEnabled || dateRange != nil else { return [] }
        return statusFilteredCustomers.compactMap { customer in
            let logs = filteredLogs(for: customer)
            guard !isDateFilterEnabled || !logs.isEmpty else { return nil }
            let latest = logs.first
            return CustomerHistoryPreview(customer: customer, latest: latest, count: logs.count)
        }
    }

    private var statusFilteredCustomers: [Customer] {
        state.visibleCustomers.filter { customer in
            switch selectedStatusFilter {
            case .all:
                return true
            case .touched:
                return hasTouchHistory(customer)
            case .visited:
                return hasVisitHistory(customer)
            case .done:
                return customer.status == .done
            case .open:
                return customer.status != .done
            }
        }
    }

    private var visibleCustomerIds: Set<String> {
        Set(state.visibleCustomers.map(\.id))
    }

    private var touchedCustomerCount: Int {
        let ids = Set(
            state.contactLogs.map(\.customerId) +
            state.photoLogs.map(\.customerId) +
            state.visitLogs.map(\.customerId)
        )
        return ids.intersection(visibleCustomerIds).count
    }

    private var visitedCustomerCount: Int {
        Set(state.visitLogs.map(\.customerId)).intersection(visibleCustomerIds).count
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

    private var historySectionTitle: String {
        let periodText = isDateFilterEnabled ? "기간 내 " : ""
        return "\(periodText)\(selectedStatusFilter.title) 고객별 히스토리"
    }

    private func filteredLogs(for customer: Customer) -> [CustomerHistoryEntry] {
        let logs = state.historyEntries(for: customer)
        guard isDateFilterEnabled else { return logs }
        guard let dateRange else { return [] }
        return logs.filter { dateRange.contains($0.at) }
    }

    private func hasTouchHistory(_ customer: Customer) -> Bool {
        if isDateFilterEnabled, let dateRange {
            return state.historyEntries(for: customer).contains { dateRange.contains($0.at) }
        }
        return !state.historyEntries(for: customer).isEmpty
    }

    private func hasVisitHistory(_ customer: Customer) -> Bool {
        state.visitLogs.contains { log in
            guard log.customerId == customer.id else { return false }
            guard isDateFilterEnabled, let dateRange else { return true }
            return dateRange.contains(log.visitedAt)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("관리 도구") {
                    NavigationLink {
                        ManagementPeriodsView()
                            .environmentObject(state)
                    } label: {
                        Label("관리 기간", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        ActivityReportView()
                            .environmentObject(state)
                    } label: {
                        Label("내 활동", systemImage: "chart.bar.xaxis")
                    }
                }

                Section("누적 상태") {
                    historyFilterRow(.all, count: state.visibleCustomers.count)
                    historyFilterRow(.touched, count: touchedCustomerCount)
                    historyFilterRow(.visited, count: visitedCustomerCount)
                    historyFilterRow(.done, count: state.doneCustomerCount)
                    historyFilterRow(.open, count: state.openCustomerCount)
                    Text("터치 고객은 전화, 문자, 길찾기, 메모, 사진, 완료 처리 등 고객별 이력이 하나라도 있는 고객입니다. 방문 고객은 방문 완료 기록이 있는 고객입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("조회 기간") {
                    Toggle("조회 기간 사용", isOn: $isDateFilterEnabled)
                    if isDateFilterEnabled {
                        DatePicker("시작날짜", selection: $startDate, displayedComponents: .date)
                        DatePicker("종료날짜", selection: $endDate, displayedComponents: .date)
                        if dateRange == nil {
                            Text("시작날짜가 종료날짜보다 늦습니다.")
                                .foregroundStyle(.red)
                        } else {
                            LabeledContent("기간 내 고객", value: "\(historyPreviews.count)명")
                            LabeledContent("기간 내 이력", value: "\(periodLogCount)건")
                        }
                    } else {
                        Text("꺼져 있으면 전체 고객 이력을 보여줍니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(historySectionTitle) {
                    if state.visibleCustomers.isEmpty {
                        Text("기록 없음")
                            .foregroundStyle(.secondary)
                    } else if isDateFilterEnabled && dateRange == nil {
                        Text("조회 기간을 다시 선택하세요.")
                            .foregroundStyle(.secondary)
                    } else if historyPreviews.isEmpty {
                        Text(isDateFilterEnabled ? "선택한 기간에 터치 이력이 없습니다." : "아직 터치 이력이 없습니다.")
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
                                        if let latest = preview.latest {
                                            Text("\(latest.title) · \(latest.at, format: .dateTime.month().day().hour().minute())")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("아직 이력 없음")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
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

    private func historyFilterRow(_ filter: HistoryStatusFilter, count: Int) -> some View {
        Button {
            selectedStatusFilter = filter
        } label: {
            HStack {
                Label(filter.title, systemImage: filter.systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)명")
                    .foregroundStyle(.secondary)
                if selectedStatusFilter == filter {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func progressColor(for customer: Customer) -> Color {
        if customer.status == .done { return .green }
        return state.historyEntries(for: customer).isEmpty ? .secondary : .orange
    }
}

private enum HistoryStatusFilter: String, CaseIterable {
    case all
    case touched
    case visited
    case done
    case open

    var title: String {
        switch self {
        case .all: return "전체 고객"
        case .touched: return "터치 고객"
        case .visited: return "방문 고객"
        case .done: return "완료 고객"
        case .open: return "미완료 고객"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "person.3"
        case .touched: return "hand.tap"
        case .visited: return "mappin.and.ellipse"
        case .done: return "checkmark.circle"
        case .open: return "circle"
        }
    }
}

private struct CustomerHistoryPreview: Identifiable {
    let customer: Customer
    let latest: CustomerHistoryEntry?
    let count: Int

    var id: String { customer.id }
}

struct SettingsView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var showingResetConfirmation = false
    @State private var showingBackupImporter = false
    @State private var showingBackupExporter = false
    @State private var showingDriveBackup = false
    @State private var showingDriveRestore = false
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
                        Label("사진 포함 전체 백업 내보내기", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingBackupImporter = true
                    } label: {
                        Label("전체 백업 가져오기", systemImage: "square.and.arrow.down")
                    }

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("로컬 데이터 초기화", systemImage: "trash")
                    }
                }

                Section("Google Drive 동기화") {
                    if !state.isGoogleDriveConfigured {
                        Label("Google iOS OAuth Client ID 설정이 필요합니다.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if let account = state.driveAccount {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.name)
                                .font(.headline)
                            Text(account.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let last = state.lastDriveSyncAt {
                                Text("마지막 동기화: \(last, format: .dateTime.year().month().day().hour().minute())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(role: .destructive) {
                            state.disconnectGoogleDrive()
                        } label: {
                            Label("연결 해제", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            Task { await state.connectGoogleDrive() }
                        } label: {
                            Label("Google 계정으로 연결", systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(!state.isGoogleDriveConfigured || state.driveSyncBusy)
                    }

                    Button {
                        Task { await state.syncGoogleDriveAll() }
                    } label: {
                        Label("Drive와 전체 동기화", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!state.isGoogleDriveConfigured || state.driveAccount == nil || state.driveSyncBusy)

                    Button {
                        Task { await state.saveAllToGoogleDrive() }
                    } label: {
                        Label("현재 기기 전체를 Drive에 저장", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(!state.isGoogleDriveConfigured || state.driveAccount == nil || state.driveSyncBusy)

                    Button {
                        showingDriveRestore = true
                    } label: {
                        Label("Drive에서 복원", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(!state.isGoogleDriveConfigured || state.driveAccount == nil || state.driveSyncBusy)

                    Button {
                        showingDriveBackup = true
                    } label: {
                        Label("Drive 백업 파일 만들기", systemImage: "doc.badge.plus")
                    }
                    .disabled(!state.isGoogleDriveConfigured || state.driveAccount == nil || state.driveSyncBusy)

                    if state.driveSyncBusy {
                        ProgressView("Google Drive 작업 중...")
                    }
                    if !state.driveSyncMessage.isEmpty {
                        Text(state.driveSyncMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            .sheet(isPresented: $showingDriveBackup) {
                GoogleDriveBackupSheet()
                    .environmentObject(state)
            }
            .sheet(isPresented: $showingDriveRestore) {
                GoogleDriveRestoreSheet()
                    .environmentObject(state)
            }
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
