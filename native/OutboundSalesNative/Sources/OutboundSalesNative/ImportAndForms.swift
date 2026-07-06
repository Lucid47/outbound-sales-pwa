import SwiftUI
import UniformTypeIdentifiers

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("문서 스캔", systemImage: "doc.viewfinder")
            Label("Apple Vision OCR", systemImage: "text.viewfinder")
            Label("표 미리보기와 CSV 생성", systemImage: "tablecells")
            Text(state.ocrMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct AddCustomerView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var address = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
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
                        state.addCustomer(name: name, phoneNumber: phoneNumber, address: address, notes: notes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    var body: some View {
        NavigationStack {
            List {
                Section("누적 상태") {
                    LabeledContent("전체 고객", value: "\(state.visibleCustomers.count)")
                    LabeledContent("완료 고객", value: "\(state.doneCustomerCount)")
                    LabeledContent("미완료 고객", value: "\(state.openCustomerCount)")
                }
            }
            .navigationTitle("기록")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("로컬 저장") {
                    LabeledContent("상태", value: state.storageMessage.isEmpty ? "대기 중" : state.storageMessage)
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("로컬 데이터 초기화", systemImage: "trash")
                    }
                }

                Section("네이티브 앱") {
                    Label("고객리스트와 고객 정보는 기기 안에 저장합니다.", systemImage: "externaldrive")
                    Label("Google Drive 동기화는 PWA 구현을 기준으로 별도 포팅합니다.", systemImage: "icloud")
                }
            }
            .navigationTitle("설정")
            .confirmationDialog("로컬 데이터를 초기화할까요?", isPresented: $showingResetConfirmation) {
                Button("초기화", role: .destructive) {
                    state.resetLocalData()
                }
                Button("취소", role: .cancel) {}
            }
        }
    }
}
