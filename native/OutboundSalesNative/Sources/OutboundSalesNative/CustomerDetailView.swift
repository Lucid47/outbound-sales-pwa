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
    @State private var noteText = ""
    @State private var visitMemo = ""

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

                    Section("빠른 실행") {
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
                            Label("사진 기록", systemImage: "camera.fill")
                        }
                    }

                    Section("사진 기록") {
                        let photos = state.photos(for: customer)
                        if photos.isEmpty {
                            Button {
                                showingPhotoSheet = true
                            } label: {
                                Label("첫 사진 추가", systemImage: "camera.fill")
                            }
                        } else {
                            CustomerPhotoGrid(photoLogs: photos)
                                .environmentObject(state)
                            Button {
                                showingPhotoSheet = true
                            } label: {
                                Label("사진 추가", systemImage: "plus")
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

                    Section("메모/방문 기록") {
                        TextField("메모", text: $noteText, axis: .vertical)
                        Button {
                            state.addNote(customer: customer, memo: noteText)
                            noteText = ""
                        } label: {
                            Label("메모 저장", systemImage: "square.and.pencil")
                        }
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        TextField("방문 메모", text: $visitMemo, axis: .vertical)
                        Button {
                            state.completeVisit(customer: customer, memo: visitMemo)
                            visitMemo = ""
                        } label: {
                            Label("방문 완료 기록", systemImage: "checkmark.seal")
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
                    CustomerPhotoCaptureSheet(customer: customer)
                        .environmentObject(state)
                }
            } else {
                ContentUnavailableView("고객을 찾을 수 없습니다.", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
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
