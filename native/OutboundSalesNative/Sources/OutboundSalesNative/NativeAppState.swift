import CoreLocation
import Foundation
import OutboundSalesCore

@MainActor
public final class NativeAppState: ObservableObject {
    @Published public private(set) var customerLists: [CustomerList]
    @Published public private(set) var customers: [Customer]
    @Published public private(set) var visitLogs: [VisitLog]
    @Published public private(set) var contactLogs: [ContactLog]
    @Published public private(set) var visitSchedules: [VisitSchedule]
    @Published public private(set) var visitScheduleItems: [VisitScheduleItem]
    @Published public private(set) var messageTemplates: [MessageTemplate]
    @Published public private(set) var selectedListId: String?
    @Published public var searchText = ""
    @Published public var importMessage = ""
    @Published public var ocrMessage = "사진을 선택하면 Apple Vision OCR로 표를 CSV로 변환합니다."
    @Published public private(set) var storageMessage = ""
    @Published public private(set) var actionMessage = ""
    @Published public private(set) var geocodeMessage = ""

    private let fileStore: NativeAppFileStore
    private let geocoder = CLGeocoder()
    private var didRunStartupMaintenance = false

    public init(seedSamples: Bool = false, fileStore: NativeAppFileStore = NativeAppFileStore()) {
        self.fileStore = fileStore

        do {
            if let snapshot = try fileStore.load() {
                self.customerLists = snapshot.customerLists
                self.customers = snapshot.customers
                self.visitLogs = snapshot.visitLogs
                self.contactLogs = snapshot.contactLogs
                self.visitSchedules = snapshot.visitSchedules
                self.visitScheduleItems = snapshot.visitScheduleItems
                self.messageTemplates = snapshot.messageTemplates.isEmpty ? Self.defaultTemplates() : snapshot.messageTemplates
                self.selectedListId = snapshot.selectedListId ?? snapshot.customerLists.first?.id
                self.storageMessage = "저장된 데이터를 불러왔습니다."
                return
            }
        } catch {
            self.storageMessage = "저장된 데이터를 읽지 못했습니다."
        }

        if seedSamples {
            let seed = Self.sampleData()
            self.customerLists = seed.lists
            self.customers = seed.customers
            self.visitLogs = seed.visitLogs
            self.contactLogs = []
            self.visitSchedules = []
            self.visitScheduleItems = []
            self.messageTemplates = Self.defaultTemplates()
            self.selectedListId = seed.lists.first?.id
        } else {
            self.customerLists = []
            self.customers = []
            self.visitLogs = []
            self.contactLogs = []
            self.visitSchedules = []
            self.visitScheduleItems = []
            self.messageTemplates = Self.defaultTemplates()
            self.selectedListId = nil
        }
    }

    public var selectedList: CustomerList? {
        customerLists.first { $0.id == selectedListId }
    }

    public var visibleCustomers: [Customer] {
        let scoped = selectedListId.map { id in customers.filter { $0.customerListId == id } } ?? customers
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { customer in
            [customer.name, customer.phoneNumber, customer.address]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public var openCustomerCount: Int {
        visibleCustomers.filter { $0.status != .done }.count
    }

    public var doneCustomerCount: Int {
        visibleCustomers.filter { $0.status == .done }.count
    }

    public var todaySchedule: VisitSchedule? {
        guard let selectedListId else { return nil }
        return visitSchedules.first { $0.customerListId == selectedListId && $0.date == Self.todayKey() }
    }

    public var todayScheduledCustomers: [Customer] {
        guard let schedule = todaySchedule else { return [] }
        let ids = visitScheduleItems
            .filter { $0.scheduleId == schedule.id }
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(\.customerId)
        return ids.compactMap { id in customers.first { $0.id == id } }
    }

    public func performStartupMaintenance() async {
        guard !didRunStartupMaintenance else { return }
        didRunStartupMaintenance = true
        await geocodeVisibleCustomers()
    }

    public func selectList(_ list: CustomerList) {
        selectedListId = list.id
        persist()
    }

    public func createEmptyList(listName: String) {
        let now = Date()
        let resolvedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "새 고객리스트" : listName
        let list = CustomerList(
            id: UUID().uuidString,
            name: resolvedListName,
            companyName: resolvedListName,
            sourceFileName: "",
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )
        customerLists.insert(list, at: 0)
        selectedListId = list.id
        persist()
    }

    public func importCSV(text: String, listName: String, sourceFileName: String = "import.csv") {
        do {
            let parsed = try parseCSV(text)
            importParsedCSV(parsed, listName: listName, sourceFileName: sourceFileName)
        } catch {
            importMessage = "CSV를 읽지 못했습니다."
        }
    }

    public func importParsedCSV(_ parsed: ParsedCSV, listName: String, sourceFileName: String = "import.csv") {
        let now = Date()
        let resolvedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sourceFileName : listName
        let list = CustomerList(
            id: UUID().uuidString,
            name: resolvedListName,
            companyName: resolvedListName,
            sourceFileName: sourceFileName,
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )
        let importedCustomers = customersFromCSV(parsed, customerListId: list.id, now: now)
        customerLists.insert(list, at: 0)
        customers.append(contentsOf: importedCustomers)
        selectedListId = list.id
        importMessage = "\(importedCustomers.count)명의 고객을 가져왔습니다."
        persist()
        Task {
            await geocodeVisibleCustomers()
        }
    }

    public func appendParsedCSV(_ parsed: ParsedCSV, to listId: String, sourceFileName: String = "import.csv") {
        guard let listIndex = customerLists.firstIndex(where: { $0.id == listId }) else {
            importMessage = "추가할 고객리스트를 찾지 못했습니다."
            return
        }

        let now = Date()
        let importedCustomers = customersFromCSV(parsed, customerListId: listId, now: now)
        customers.append(contentsOf: importedCustomers)
        customerLists[listIndex].updatedAt = now
        selectedListId = listId
        importMessage = "\(customerLists[listIndex].name)에 \(importedCustomers.count)명의 고객을 추가했습니다."
        persist()
        Task {
            await geocodeVisibleCustomers()
        }
    }

    public func importFile(url: URL, listName: String) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()

        guard fileExtension != "xlsx" && fileExtension != "xls" else {
            importMessage = "엑셀 파일 가져오기는 다음 단계에서 연결합니다. 현재는 CSV 파일을 사용할 수 있습니다."
            return
        }

        do {
            let text = try decodeCSVText(data: Data(contentsOf: url))
            importCSV(text: text, listName: listName, sourceFileName: fileName)
        } catch {
            importMessage = "파일을 읽지 못했습니다."
        }
    }

    public func addCustomer(name: String, phoneNumber: String, address: String, notes: String) {
        guard let listId = selectedListId else { return }
        addCustomer(to: listId, name: name, phoneNumber: phoneNumber, address: address, notes: notes)
    }

    public func addCustomer(to listId: String, name: String, phoneNumber: String, address: String, notes: String) {
        guard customerLists.contains(where: { $0.id == listId }) else { return }
        let now = Date()
        customers.insert(
            Customer(
                id: UUID().uuidString,
                customerListId: listId,
                name: name,
                phoneNumber: phoneNumber,
                address: address,
                notes: notes,
                region: extractRegion(address),
                status: .open,
                createdAt: now,
                updatedAt: now
            ),
            at: 0
        )
        selectedListId = listId
        persist()
        let customerId = customers.first?.id
        Task {
            await geocodeCustomerIfNeeded(id: customerId)
        }
    }

    public func updateCustomer(_ customer: Customer, name: String, phoneNumber: String, address: String, birthDate: String, notes: String) {
        guard let index = customers.firstIndex(where: { $0.id == customer.id }) else { return }
        customers[index].name = name
        customers[index].phoneNumber = phoneNumber
        customers[index].address = address
        customers[index].birthDate = birthDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : birthDate
        customers[index].notes = notes
        customers[index].region = extractRegion(address)
        if customer.address != address {
            customers[index].latitude = nil
            customers[index].longitude = nil
            customers[index].coordinateSource = nil
            customers[index].geocodedAt = nil
            customers[index].geocodeQuery = nil
        }
        customers[index].updatedAt = Date()
        persist()
        Task {
            await geocodeCustomerIfNeeded(id: customer.id)
        }
    }

    public func toggleDone(_ customer: Customer) {
        guard let index = customers.firstIndex(where: { $0.id == customer.id }) else { return }
        let completed = customers[index].status != .done
        customers[index].status = completed ? .done : .open
        customers[index].updatedAt = Date()
        contactLogs.insert(
            ContactLog(
                id: UUID().uuidString,
                customerListId: customer.customerListId,
                customerId: customer.id,
                type: completed ? .statusComplete : .statusReopen,
                result: completed ? .completed : .reopened,
                createdAt: Date()
            ),
            at: 0
        )
        persist()
    }

    public func recordContact(customer: Customer, type: ContactLogType, result: ContactLogResult = .opened, messageBody: String? = nil, templateId: String? = nil) {
        contactLogs.insert(
            ContactLog(
                id: UUID().uuidString,
                customerListId: customer.customerListId,
                customerId: customer.id,
                type: type,
                templateId: templateId,
                messageBody: messageBody,
                result: result,
                createdAt: Date()
            ),
            at: 0
        )
        actionMessage = "기록을 남겼습니다."
        persist()
    }

    public func addNote(customer: Customer, memo: String) {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordContact(customer: customer, type: .note, result: .saved, messageBody: trimmed)
    }

    func markContactExportResults(_ results: [ContactExportCustomerResult]) {
        guard !results.isEmpty else { return }
        let now = Date()
        for result in results {
            guard let index = customers.firstIndex(where: { $0.id == result.customerId }) else { continue }
            customers[index].contactRegistrationStatus = result.status
            customers[index].contactIdentifier = result.contactIdentifier
            customers[index].contactRegisteredAt = now
            customers[index].contactRegisteredName = result.registeredName
            customers[index].updatedAt = now
        }
        actionMessage = "연락처 등록 결과를 저장했습니다."
        persist()
    }

    public func completeVisit(customer: Customer, memo: String = "") {
        let now = Date()
        visitLogs.insert(
            VisitLog(
                id: UUID().uuidString,
                customerListId: customer.customerListId,
                customerId: customer.id,
                visitedAt: now,
                result: "completed",
                memo: memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : memo,
                createdAt: now
            ),
            at: 0
        )
        if let index = customers.firstIndex(where: { $0.id == customer.id }) {
            customers[index].status = .done
            customers[index].updatedAt = now
        }
        persist()
    }

    public func ensureTodaySchedule() -> VisitSchedule? {
        guard let selectedListId else { return nil }
        if let schedule = todaySchedule { return schedule }
        let now = Date()
        let schedule = VisitSchedule(
            id: UUID().uuidString,
            customerListId: selectedListId,
            date: Self.todayKey(),
            title: "\(selectedList?.name ?? "고객리스트") 오늘 방문",
            createdAt: now,
            updatedAt: now
        )
        visitSchedules.insert(schedule, at: 0)
        persist()
        return schedule
    }

    public func addToTodaySchedule(_ customer: Customer) {
        guard let schedule = ensureTodaySchedule() else { return }
        guard !visitScheduleItems.contains(where: { $0.scheduleId == schedule.id && $0.customerId == customer.id }) else { return }
        let orderIndex = visitScheduleItems.filter { $0.scheduleId == schedule.id }.count
        visitScheduleItems.append(
            VisitScheduleItem(
                id: UUID().uuidString,
                scheduleId: schedule.id,
                customerListId: customer.customerListId,
                customerId: customer.id,
                orderIndex: orderIndex,
                status: .pending
            )
        )
        persist()
    }

    public func removeFromTodaySchedule(_ customer: Customer) {
        guard let schedule = todaySchedule else { return }
        visitScheduleItems.removeAll { $0.scheduleId == schedule.id && $0.customerId == customer.id }
        persist()
    }

    public func logs(for customer: Customer) -> [(Date, String, String)] {
        let contacts = contactLogs
            .filter { $0.customerId == customer.id }
            .map { ($0.createdAt, contactTitle($0), $0.messageBody ?? contactResultText($0.result)) }
        let visits = visitLogs
            .filter { $0.customerId == customer.id }
            .map { ($0.visitedAt, "방문 완료", $0.memo ?? "방문 기록") }
        return (contacts + visits).sorted { $0.0 > $1.0 }
    }

    public func latestHistorySummary(for customer: Customer) -> (title: String, detail: String, at: Date)? {
        guard let latest = logs(for: customer).first else { return nil }
        return (latest.1, latest.2, latest.0)
    }

    public func latestTouchDate(for customer: Customer) -> Date? {
        logs(for: customer).first?.0
    }

    public func progressLabel(for customer: Customer) -> String {
        if customer.status == .done {
            return "완료"
        }
        return logs(for: customer).isEmpty ? "미터치" : "진행중"
    }

    public func updateMessageTemplate(_ template: MessageTemplate, title: String, body: String, isDefault: Bool) {
        guard let index = messageTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        messageTemplates[index].title = title
        messageTemplates[index].body = body
        messageTemplates[index].isDefault = isDefault
        messageTemplates[index].updatedAt = Date()
        persist()
    }

    public func createMessageTemplate(title: String, body: String) {
        let now = Date()
        messageTemplates.append(
            MessageTemplate(
                id: UUID().uuidString,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "새 문자 템플릿" : title,
                body: body,
                createdAt: now,
                updatedAt: now
            )
        )
        persist()
    }

    public func deleteMessageTemplate(_ template: MessageTemplate) {
        messageTemplates.removeAll { $0.id == template.id }
        persist()
    }

    public func recognizeOCRCSV(url: URL, headers: [String] = []) async -> String? {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        ocrMessage = "사진에서 텍스트를 인식하는 중..."
        do {
            let result = try await Task.detached {
                try recognizeCustomerListImage(at: url, headers: headers, headerMode: .auto)
            }.value
            ocrMessage = "OCR 완료: \(result.boxes.count)개 텍스트, \(result.table.rows.count)행, \(result.table.columnCount)열"
            if !result.table.warnings.isEmpty {
                ocrMessage += " · 일부 행은 확인이 필요합니다."
            }
            return result.csv.csv
        } catch {
            ocrMessage = "사진 OCR에 실패했습니다."
            return nil
        }
    }

    public func exportSnapshotData() throws -> Data {
        try fileStore.encoder.encode(snapshot())
    }

    public func importSnapshot(url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try fileStore.decoder.decode(NativeAppSnapshot.self, from: data)
            customerLists = snapshot.customerLists
            customers = snapshot.customers
            visitLogs = snapshot.visitLogs
            contactLogs = snapshot.contactLogs
            visitSchedules = snapshot.visitSchedules
            visitScheduleItems = snapshot.visitScheduleItems
            messageTemplates = snapshot.messageTemplates.isEmpty ? Self.defaultTemplates() : snapshot.messageTemplates
            selectedListId = snapshot.selectedListId ?? customerLists.first?.id
            persist()
            storageMessage = "백업을 가져왔습니다."
        } catch {
            storageMessage = "백업을 가져오지 못했습니다."
        }
    }

    public func geocodeVisibleCustomers() async {
        let targets = visibleCustomers.filter { ($0.latitude == nil || $0.longitude == nil) && isSearchableAddress($0.address) }
        guard !targets.isEmpty else {
            geocodeMessage = "좌표 변환할 주소가 없습니다."
            return
        }

        geocodeMessage = "주소 좌표 변환 중..."
        var successCount = 0
        for customer in targets {
            guard let index = customers.firstIndex(where: { $0.id == customer.id }) else { continue }
            if await geocodeCustomer(at: index) {
                successCount += 1
            } else {
                customers[index].status = .needsGeocode
                customers[index].updatedAt = Date()
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        geocodeMessage = "\(successCount)/\(targets.count)개 주소를 변환했습니다."
        persist()
    }

    public func geocodeCustomerIfNeeded(id: String?) async {
        guard let id, let index = customers.firstIndex(where: { $0.id == id }) else { return }
        guard customers[index].latitude == nil || customers[index].longitude == nil else { return }
        guard isSearchableAddress(customers[index].address) else {
            geocodeMessage = "도로명주소를 인식하지 못했습니다."
            return
        }
        if await geocodeCustomer(at: index) {
            geocodeMessage = "주소를 지도 좌표로 변환했습니다."
        } else {
            customers[index].status = .needsGeocode
            customers[index].updatedAt = Date()
            geocodeMessage = "주소 좌표 변환에 실패했습니다."
        }
        persist()
    }

    public func resetLocalData(seedSamples: Bool = false) {
        if seedSamples {
            let seed = Self.sampleData()
            customerLists = seed.lists
            customers = seed.customers
            visitLogs = seed.visitLogs
            contactLogs = []
            visitSchedules = []
            visitScheduleItems = []
            messageTemplates = Self.defaultTemplates()
            selectedListId = seed.lists.first?.id
        } else {
            customerLists = []
            customers = []
            visitLogs = []
            contactLogs = []
            visitSchedules = []
            visitScheduleItems = []
            messageTemplates = Self.defaultTemplates()
            selectedListId = nil
        }
        do {
            try fileStore.delete()
            storageMessage = "로컬 데이터를 초기화했습니다."
        } catch {
            storageMessage = "로컬 데이터 초기화에 실패했습니다."
        }
    }

    private func persist() {
        do {
            try fileStore.save(snapshot())
            storageMessage = "로컬에 저장했습니다."
        } catch {
            storageMessage = "로컬 저장에 실패했습니다."
        }
    }

    private func snapshot() -> NativeAppSnapshot {
        NativeAppSnapshot(
            customerLists: customerLists,
            customers: customers,
            visitLogs: visitLogs,
            contactLogs: contactLogs,
            visitSchedules: visitSchedules,
            visitScheduleItems: visitScheduleItems,
            messageTemplates: messageTemplates,
            selectedListId: selectedListId
        )
    }

    private func contactTitle(_ log: ContactLog) -> String {
        switch log.type {
        case .call: return "전화 시도"
        case .manualSms: return "문자 시도"
        case .templateSms: return "템플릿 문자"
        case .note: return "메모"
        case .statusComplete: return "완료 처리"
        case .statusReopen: return "완료 취소"
        }
    }

    private func contactResultText(_ result: ContactLogResult) -> String {
        switch result {
        case .opened: return "앱 실행"
        case .sentByUser: return "사용자 발송"
        case .completed: return "완료"
        case .reopened: return "다시 열림"
        case .saved: return "저장됨"
        case .cancelled: return "취소"
        case .unknown: return "상태 미확인"
        }
    }

    private func geocodeCustomer(at index: Int) async -> Bool {
        for query in geocodeQueries(for: customers[index].address) {
            do {
                let placemarks = try await geocoder.geocodeAddressString(query)
                if let location = placemarks.first?.location {
                    customers[index].latitude = location.coordinate.latitude
                    customers[index].longitude = location.coordinate.longitude
                    customers[index].coordinateSource = .geocoded
                    customers[index].geocodedAt = Date()
                    customers[index].geocodeQuery = query
                    customers[index].updatedAt = Date()
                    if customers[index].status == .needsGeocode {
                        customers[index].status = .open
                    }
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    private func geocodeQueries(for address: String) -> [String] {
        geocodeCandidateQueries(address)
    }

    static func todayKey() -> String {
        DateFormatter.nativeDateOnly.string(from: Date())
    }

    static func sampleData() -> (lists: [CustomerList], customers: [Customer], visitLogs: [VisitLog]) {
        let now = Date()
        let list = CustomerList(
            id: "sample-list",
            name: "샘플 고객리스트",
            companyName: "샘플 고객사",
            sourceFileName: "sample.csv",
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )
        let customers = [
            Customer(
                id: "sample-customer-1",
                customerListId: list.id,
                name: "홍길동",
                phoneNumber: "010-1234-5678",
                address: "서울 강남구 테헤란로 152",
                notes: "방문 상담",
                latitude: 37.5012,
                longitude: 127.0396,
                coordinateSource: .sample,
                region: "강남구 테헤란로",
                status: .open,
                createdAt: now,
                updatedAt: now
            ),
            Customer(
                id: "sample-customer-2",
                customerListId: list.id,
                name: "김영희",
                phoneNumber: "010-2468-1357",
                address: "서울 서초구 서초대로 396",
                notes: "자료 문자 선호",
                latitude: 37.4973,
                longitude: 127.0246,
                coordinateSource: .sample,
                region: "서초구 서초대로",
                status: .done,
                createdAt: now,
                updatedAt: now
            )
        ]
        let logs = [
            VisitLog(
                id: "sample-visit-1",
                customerListId: list.id,
                customerId: "sample-customer-2",
                visitedAt: now,
                result: "completed",
                memo: "샘플 방문 기록",
                createdAt: now
            )
        ]
        return ([list], customers, logs)
    }

    static func defaultTemplates() -> [MessageTemplate] {
        let now = Date()
        return [
            MessageTemplate(
                id: "tpl-visit",
                title: "방문 상담 안내",
                body: "안녕하세요, {고객명}님. 방문 상담차 연락드렸습니다. 가능하실 때 회신 부탁드립니다.",
                isDefault: true,
                createdAt: now,
                updatedAt: now
            ),
            MessageTemplate(
                id: "tpl-arrival",
                title: "도착 전 연락",
                body: "안녕하세요, {고객명}님. 근처에 도착하여 연락드립니다. 잠시 후 뵙겠습니다.",
                createdAt: now,
                updatedAt: now
            )
        ]
    }
}

private extension DateFormatter {
    static let nativeDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
