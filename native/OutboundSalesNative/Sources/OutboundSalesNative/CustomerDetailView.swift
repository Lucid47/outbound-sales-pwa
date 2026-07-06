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
                            state.recordContact(customer: customer, type: .manualSms)
                            if let url = URL(string: "sms:\(cleanPhone(customer.phoneNumber))") {
                                openURL(url)
                            }
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
                    }

                    Section("템플릿 문자") {
                        ForEach(state.messageTemplates) { template in
                            Button {
                                let body = template.body.replacingOccurrences(of: "{고객명}", with: customer.name)
                                copyToClipboard(body)
                                state.recordContact(customer: customer, type: .templateSms, result: .opened, messageBody: body, templateId: template.id)
                                if let url = URL(string: "sms:\(cleanPhone(customer.phoneNumber))") {
                                    openURL(url)
                                }
                            } label: {
                                Label(template.title, systemImage: "text.bubble")
                            }
                            .disabled(!hasDialablePhone(customer.phoneNumber))
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
                        let logs = state.logs(for: customer)
                        if logs.isEmpty {
                            Text("기록 없음")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.1)
                                        .font(.headline)
                                    Text(log.2)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(log.0, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
            } else {
                ContentUnavailableView("고객을 찾을 수 없습니다.", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }

    private func openDirections(_ customer: Customer) {
        let goalName = (customer.name.isEmpty ? customer.address : customer.name)
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

        let query = normalizeAddressForMapSearch(customer.address).isEmpty ? customer.address : normalizeAddressForMapSearch(customer.address)
        if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let tmapURL = URL(string: "tmap://?search=\(encoded)") {
            openURL(tmapURL) { accepted in
                if !accepted, let appleURL = URL(string: "http://maps.apple.com/?daddr=\(encoded)") {
                    openURL(appleURL)
                }
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
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
