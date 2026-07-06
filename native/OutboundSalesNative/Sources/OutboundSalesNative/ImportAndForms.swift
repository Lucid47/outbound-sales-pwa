import SwiftUI

struct ImportView: View {
    @EnvironmentObject private var state: NativeAppState
    @State private var companyName = ""
    @State private var listName = ""
    @State private var csvText = """
    이름,전화번호,주소,메모
    홍길동,010-1234-5678,서울 강남구 테헤란로 152,방문 상담
    """

    var body: some View {
        NavigationStack {
            Form {
                Section("리스트 정보") {
                    TextField("고객사 이름", text: $companyName)
                    TextField("고객리스트 이름", text: $listName)
                }

                Section("CSV 텍스트") {
                    TextEditor(text: $csvText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                }

                Button("CSV 가져오기") {
                    state.importCSV(text: csvText, companyName: companyName, listName: listName)
                }

                if !state.importMessage.isEmpty {
                    Text(state.importMessage)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("가져오기")
        }
    }
}

struct OCRImportView: View {
    @EnvironmentObject private var state: NativeAppState

    var body: some View {
        NavigationStack {
            List {
                Section("OCR 가져오기") {
                    Label("문서 스캔", systemImage: "doc.viewfinder")
                    Label("Apple Vision OCR", systemImage: "text.viewfinder")
                    Label("표 미리보기와 CSV 생성", systemImage: "tablecells")
                }

                Section("상태") {
                    Text(state.ocrMessage)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("OCR")
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
    @State private var companyName = ""
    @State private var listName = ""

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
