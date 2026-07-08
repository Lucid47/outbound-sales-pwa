import MapKit
import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct CustomerDetailView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.openURL) private var openURL
    let customerId: String
    @State private var showingEdit = false
    @State private var showingMessageSheet = false
    @State private var showingPhotoSheet = false
    @State private var showingVoiceSheet = false
    @State private var showingTextMemoSheet = false
    @State private var showingVisitSheet = false
    @State private var selectedTextMemo: VisitLog?
    @State private var selectedVoiceMemo: VisitLog?

    private var customer: Customer? {
        state.customers.first { $0.id == customerId }
    }

    var body: some View {
        Group {
            if let customer {
                List {
                    Section("고객 정보") {
                        LabeledContent("이름", value: customer.name.isEmpty ? "이름 없음" : customer.name)
                        LabeledContent("연락처", value: customer.phoneNumber.isEmpty ? "연락처 없음" : customer.phoneNumber)
                        LabeledContent("주소", value: customer.address.isEmpty ? "주소 없음" : customer.address)
                        if let birthDate = customer.birthDate, !birthDate.isEmpty {
                            LabeledContent("생년월일", value: birthDate)
                        }
                        LabeledContent("상태", value: customer.status == .done ? "완료" : "미완료")
                        if !customer.notes.isEmpty {
                            Text(customer.notes)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("고객 터치") {
                        Button {
                            state.recordContact(customer: customer, type: .call)
                            if let url = URL(string: "tel:\(cleanPhone(customer.phoneNumber))") {
                                openURL(url)
                            }
                        } label: {
                            Label("전화", systemImage: "phone")
                        }
                        .disabled(!hasDialablePhone(customer.phoneNumber))

                        Button {
                            showingMessageSheet = true
                        } label: {
                            Label("문자", systemImage: "message")
                        }
                        .disabled(!hasDialablePhone(customer.phoneNumber))

                        Button {
                            openDirections(customer)
                        } label: {
                            Label("길찾기", systemImage: "location")
                        }
                        .disabled(customer.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && customer.latitude == nil)

                        Button {
                            showingPhotoSheet = true
                        } label: {
                            Label("사진 메모", systemImage: "camera.fill")
                        }

                        Button {
                            showingVoiceSheet = true
                        } label: {
                            Label("음성 메모", systemImage: "mic.fill")
                        }

                        Button {
                            showingTextMemoSheet = true
                        } label: {
                            Label("텍스트 메모", systemImage: "text.bubble")
                        }

                        Button {
                            showingVisitSheet = true
                        } label: {
                            Label("방문", systemImage: "mappin.and.ellipse")
                        }
                    }

                    Section("사진 메모") {
                        let photos = state.photos(for: customer)
                        if photos.isEmpty {
                            Button {
                                showingPhotoSheet = true
                            } label: {
                                Label("첫 사진 메모 추가", systemImage: "camera.fill")
                            }
                        } else {
                            CustomerPhotoGrid(photoLogs: photos)
                                .environmentObject(state)
                            Button {
                                showingPhotoSheet = true
                            } label: {
                                Label("사진 메모 추가", systemImage: "plus")
                            }
                        }
                    }

                    Section("음성 메모") {
                        let logs = voiceMemoLogs(for: customer)
                        if logs.isEmpty {
                            Button {
                                showingVoiceSheet = true
                            } label: {
                                Label("첫 음성 메모 추가", systemImage: "mic.fill")
                            }
                        } else {
                            ForEach(logs.prefix(6)) { log in
                                Button {
                                    selectedVoiceMemo = log
                                } label: {
                                    VisitMemoPreviewRow(log: log, kind: .voice)
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                showingVoiceSheet = true
                            } label: {
                                Label("음성 메모 추가", systemImage: "plus")
                            }
                        }
                    }

                    Section("텍스트 메모") {
                        let logs = textMemoLogs(for: customer)
                        if logs.isEmpty {
                            Button {
                                showingTextMemoSheet = true
                            } label: {
                                Label("첫 텍스트 메모 추가", systemImage: "text.bubble")
                            }
                        } else {
                            ForEach(logs.prefix(6)) { log in
                                Button {
                                    selectedTextMemo = log
                                } label: {
                                    VisitMemoPreviewRow(log: log, kind: .text)
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                showingTextMemoSheet = true
                            } label: {
                                Label("텍스트 메모 추가", systemImage: "plus")
                            }
                        }
                    }

                    Section("상태와 스케줄") {
                        Button {
                            state.toggleDone(customer)
                        } label: {
                            Label(customer.status == .done ? "완료 취소" : "완료 처리", systemImage: customer.status == .done ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        }

                        Button {
                            state.addToTodaySchedule(customer)
                        } label: {
                            Label("오늘 스케줄에 추가", systemImage: "calendar.badge.plus")
                        }

                        Button(role: .destructive) {
                            state.removeFromTodaySchedule(customer)
                        } label: {
                            Label("오늘 스케줄에서 제거", systemImage: "calendar.badge.minus")
                        }
                    }

                    Section("히스토리") {
                        let entries = state.historyEntries(for: customer)
                        if entries.isEmpty {
                            Text("기록 없음")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(entries) { entry in
                                CustomerHistoryEntryRow(entry: entry)
                                    .environmentObject(state)
                            }
                        }
                    }
                }
                .navigationTitle(customer.name.isEmpty ? "고객 상세" : customer.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("수정") {
                            showingEdit = true
                        }
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    EditCustomerView(customer: customer)
                        .environmentObject(state)
                }
                .sheet(isPresented: $showingMessageSheet) {
                    MessageComposerSheet(customer: customer)
                        .environmentObject(state)
                }
                .sheet(isPresented: $showingPhotoSheet) {
                    CustomerPhotoCaptureSheet(customer: customer, title: "사진 메모")
                        .environmentObject(state)
                }
                .sheet(isPresented: $showingVoiceSheet) {
                    #if os(iOS)
                    VisitVoiceMemoSheet(customer: customer) {}
                        .environmentObject(state)
                    #else
                    Text("음성 메모는 iPhone에서 사용할 수 있습니다.")
                    #endif
                }
                .sheet(isPresented: $showingVisitSheet) {
                    CustomerVisitPromptSheet(customer: customer)
                        .environmentObject(state)
                }
                .sheet(isPresented: $showingTextMemoSheet) {
                    VisitTextMemoSheet(customer: customer) {}
                        .environmentObject(state)
                }
                .sheet(item: $selectedTextMemo) { log in
                    TextMemoDetailSheet(log: log)
                }
                .sheet(item: $selectedVoiceMemo) { log in
                    VoiceMemoDetailSheet(log: log)
                        .environmentObject(state)
                }
            } else {
                ContentUnavailableView("고객을 찾을 수 없습니다.", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }

    private func textMemoLogs(for customer: Customer) -> [VisitLog] {
        state.visitLogs
            .filter { $0.customerId == customer.id && $0.kind == .textMemo }
            .sorted { $0.visitedAt > $1.visitedAt }
    }

    private func voiceMemoLogs(for customer: Customer) -> [VisitLog] {
        state.visitLogs
            .filter { $0.customerId == customer.id && $0.kind == .voiceMemo }
            .sorted { $0.visitedAt > $1.visitedAt }
    }

    private func openDirections(_ customer: Customer) {
        let destination = normalizedDestination(for: customer)
        let routeLabel = destination.isEmpty ? customer.name : destination
        let goalName = routeLabel
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let latitude = customer.latitude, let longitude = customer.longitude {
            if let tmapURL = URL(string: "tmap://route?goalx=\(longitude)&goaly=\(latitude)&goalname=\(goalName)") {
                openURL(tmapURL) { accepted in
                    if !accepted {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
                        item.name = customer.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    }
                }
            }
            return
        }

        let query = destination.isEmpty ? customer.name : destination
        if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let tmapURL = URL(string: "tmap://?search=\(encoded)") {
            openURL(tmapURL) { accepted in
                if !accepted, let appleURL = URL(string: "http://maps.apple.com/?daddr=\(encoded)") {
                    openURL(appleURL)
                }
            }
        }
    }

    private func normalizedDestination(for customer: Customer) -> String {
        let normalized = normalizeAddressForMapSearch(customer.address)
        return normalized.isEmpty ? customer.address : normalized
    }
}

struct EditCustomerView: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var name: String
    @State private var phoneNumber: String
    @State private var address: String
    @State private var birthDate: String
    @State private var notes: String

    init(customer: Customer) {
        self.customer = customer
        self._name = State(initialValue: customer.name)
        self._phoneNumber = State(initialValue: customer.phoneNumber)
        self._address = State(initialValue: customer.address)
        self._birthDate = State(initialValue: customer.birthDate ?? "")
        self._notes = State(initialValue: customer.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("이름", text: $name)
                TextField("연락처", text: $phoneNumber)
                TextField("주소", text: $address, axis: .vertical)
                TextField("생년월일", text: $birthDate)
                TextField("메모", text: $notes, axis: .vertical)
            }
            .navigationTitle("고객 수정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        state.updateCustomer(customer, name: name, phoneNumber: phoneNumber, address: address, birthDate: birthDate, notes: notes)
                        dismiss()
                    }
                }
            }
        }
    }
}
