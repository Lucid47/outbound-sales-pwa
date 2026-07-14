import AuthenticationServices
import CoreLocation
import Foundation
import OutboundSalesCore
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

public struct CustomerHistoryEntry: Identifiable, Equatable {
    public var id: String
    public var at: Date
    public var title: String
    public var detail: String
    public var photoLog: CustomerPhotoLog?
    public var visitLog: VisitLog?
}

@MainActor
public final class NativeAppState: ObservableObject {
    @Published public private(set) var customerLists: [CustomerList]
    @Published public private(set) var customers: [Customer]
    @Published public private(set) var visitLogs: [VisitLog]
    @Published public private(set) var contactLogs: [ContactLog]
    @Published public private(set) var photoLogs: [CustomerPhotoLog]
    @Published public private(set) var visitSchedules: [VisitSchedule]
    @Published public private(set) var visitScheduleItems: [VisitScheduleItem]
    @Published public private(set) var messageTemplates: [MessageTemplate]
    @Published public private(set) var groupSmsCampaigns: [GroupSmsCampaign]
    @Published public private(set) var contactExportBatches: [ContactExportBatch]
    @Published public private(set) var dashboardStatuses: [DashboardStatusDefinition]
    @Published public private(set) var dashboardSettings: DashboardHeatmapSettings
    @Published public private(set) var selectedListId: String?
    @Published public var searchText = ""
    @Published public var importMessage = ""
    @Published public var ocrMessage = "사진을 선택하면 Apple Vision OCR로 표를 CSV로 변환합니다."
    @Published public private(set) var storageMessage = ""
    @Published public var actionMessage = ""
    @Published public private(set) var geocodeMessage = ""
    @Published public private(set) var driveAccount: GoogleDriveAccount?
    @Published public private(set) var driveSyncMessage = ""
    @Published public private(set) var driveSyncBusy = false
    @Published public private(set) var lastDriveSyncAt: Date?
    @Published public private(set) var remoteDriveLists: [CustomerList] = []

    private let fileStore: NativeAppFileStore
    private let geocoder = CLGeocoder()
    private var didRunStartupMaintenance = false
    private let driveService = GoogleDriveSyncService()
    private var cachedRemoteBackup: NativeFullBackup?

    public init(seedSamples: Bool = false, fileStore: NativeAppFileStore = NativeAppFileStore()) {
        let savedDriveAccount = Self.loadDriveAccount()
        let needsDriveReconnect = savedDriveAccount != nil && !GoogleDriveSyncService.hasStoredAuthorization
        self.fileStore = fileStore
        self.driveAccount = needsDriveReconnect ? nil : savedDriveAccount
        self.lastDriveSyncAt = Self.loadLastDriveSyncAt()

        do {
            if let snapshot = try fileStore.load() {
                self.customerLists = snapshot.customerLists
                self.customers = snapshot.customers
                self.visitLogs = snapshot.visitLogs
                self.contactLogs = snapshot.contactLogs
                self.photoLogs = snapshot.photoLogs
                self.visitSchedules = snapshot.visitSchedules
                self.visitScheduleItems = snapshot.visitScheduleItems
                self.messageTemplates = snapshot.messageTemplates.isEmpty ? Self.defaultTemplates() : snapshot.messageTemplates
                self.groupSmsCampaigns = snapshot.groupSmsCampaigns
                self.contactExportBatches = snapshot.contactExportBatches
                let resolvedDashboardStatuses = snapshot.dashboardStatuses.isEmpty
                    ? Self.defaultDashboardStatuses()
                    : Self.migratingDefaultDashboardColors(snapshot.dashboardStatuses)
                self.dashboardStatuses = resolvedDashboardStatuses
                var resolvedDashboardSettings = snapshot.dashboardSettings
                resolvedDashboardSettings.statusCount = resolvedDashboardStatuses.count
                self.dashboardSettings = resolvedDashboardSettings
                self.selectedListId = snapshot.selectedListId ?? snapshot.customerLists.first?.id
                self.storageMessage = "저장된 데이터를 불러왔습니다."
                self.customers = Self.repairingDashboardAssignments(
                    self.customers,
                    statuses: resolvedDashboardStatuses
                )
                if needsDriveReconnect {
                    self.driveSyncMessage = "보안 인증 방식이 갱신되었습니다. Google 계정을 한 번 다시 연결하세요."
                }
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
            self.photoLogs = []
            self.visitSchedules = []
            self.visitScheduleItems = []
            self.messageTemplates = Self.defaultTemplates()
            self.groupSmsCampaigns = []
            self.contactExportBatches = []
            self.dashboardStatuses = Self.defaultDashboardStatuses()
            self.dashboardSettings = DashboardHeatmapSettings()
            self.selectedListId = seed.lists.first?.id
        } else {
            self.customerLists = []
            self.customers = []
            self.visitLogs = []
            self.contactLogs = []
            self.photoLogs = []
            self.visitSchedules = []
            self.visitScheduleItems = []
            self.messageTemplates = Self.defaultTemplates()
            self.groupSmsCampaigns = []
            self.contactExportBatches = []
            self.dashboardStatuses = Self.defaultDashboardStatuses()
            self.dashboardSettings = DashboardHeatmapSettings()
            self.selectedListId = nil
        }
        if needsDriveReconnect {
            self.driveSyncMessage = "보안 인증 방식이 갱신되었습니다. Google 계정을 한 번 다시 연결하세요."
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

    public var activeDashboardColorPalette: [String] {
        Self.dashboardColorPalette(for: dashboardSettings.paletteFamily)
    }

    public var openCustomerCount: Int {
        visibleCustomers.filter { $0.status != .done }.count
    }

    public var doneCustomerCount: Int {
        visibleCustomers.filter { $0.status == .done }.count
    }

    public var touchLogCount: Int {
        contactLogs.count + photoLogs.count
    }

    public var isGoogleDriveConfigured: Bool {
        driveService.isConfigured
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

    func importContactCustomers(_ contacts: [ContactImportCustomer], listName: String, sourceFileName: String = "contacts", skipDuplicatePhones: Bool = true) {
        let now = Date()
        let resolvedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "연락처 가져오기" : listName
        let list = CustomerList(
            id: UUID().uuidString,
            name: resolvedListName,
            companyName: resolvedListName,
            sourceFileName: sourceFileName,
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )
        let importedCustomers = makeCustomers(from: contacts, customerListId: list.id, now: now, skipDuplicatePhones: skipDuplicatePhones)
        customerLists.insert(list, at: 0)
        customers.append(contentsOf: importedCustomers.customers)
        selectedListId = list.id
        importMessage = "\(importedCustomers.customers.count)명의 연락처를 가져왔습니다." + (importedCustomers.skippedCount > 0 ? " 중복 \(importedCustomers.skippedCount)명은 건너뛰었습니다." : "")
        persist()
        Task {
            await geocodeVisibleCustomers()
        }
    }

    func appendContactCustomers(_ contacts: [ContactImportCustomer], to listId: String, sourceFileName: String = "contacts", skipDuplicatePhones: Bool = true) {
        guard let listIndex = customerLists.firstIndex(where: { $0.id == listId }) else {
            importMessage = "추가할 고객리스트를 찾지 못했습니다."
            return
        }

        let now = Date()
        let importedCustomers = makeCustomers(from: contacts, customerListId: listId, now: now, skipDuplicatePhones: skipDuplicatePhones)
        customers.append(contentsOf: importedCustomers.customers)
        customerLists[listIndex].updatedAt = now
        selectedListId = listId
        importMessage = "\(customerLists[listIndex].name)에 \(importedCustomers.customers.count)명의 연락처를 추가했습니다." + (importedCustomers.skippedCount > 0 ? " 중복 \(importedCustomers.skippedCount)명은 건너뛰었습니다." : "")
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

    public func dashboardStatus(for customer: Customer) -> DashboardStatusDefinition? {
        let resolvedId = customer.dashboardStatusId ?? dashboardStatuses.first?.id
        return dashboardStatuses.first { $0.id == resolvedId }
    }

    public func setDashboardStatus(customerId: String, statusId: String) {
        guard dashboardStatuses.contains(where: { $0.id == statusId }),
              let index = customers.firstIndex(where: { $0.id == customerId }) else { return }
        customers[index].dashboardStatusId = statusId
        customers[index].updatedAt = Date()
        persist()
    }

    public func addDashboardStatus() {
        guard dashboardStatuses.count < 10 else { return }
        setDashboardStatusCount(dashboardStatuses.count + 1)
    }

    public func setDashboardStatusCount(_ requestedCount: Int) {
        let resolvedCount = min(max(requestedCount, 1), 10)
        guard resolvedCount != dashboardStatuses.count else { return }

        let now = Date()
        if resolvedCount < dashboardStatuses.count {
            let removedIds = Set(dashboardStatuses.dropFirst(resolvedCount).map(\.id))
            dashboardStatuses = Array(dashboardStatuses.prefix(resolvedCount))
            if let fallbackId = dashboardStatuses.last?.id {
                for index in customers.indices where customers[index].dashboardStatusId.map(removedIds.contains) ?? false {
                    customers[index].dashboardStatusId = fallbackId
                    customers[index].updatedAt = now
                }
            }
        } else {
            for index in dashboardStatuses.count..<resolvedCount {
                dashboardStatuses.append(
                    DashboardStatusDefinition(
                        id: UUID().uuidString,
                        name: "상태 \(index + 1)",
                        colorHex: activeDashboardColorPalette.last ?? "5B8FF9",
                        orderIndex: index,
                        updatedAt: now
                    )
                )
            }
        }

        dashboardSettings.statusCount = resolvedCount
        dashboardSettings.updatedAt = now
        normalizeDashboardStatusOrder(updatedAt: now)
        applyActiveDashboardPalette(updatedAt: now)
        persist()
    }

    public func updateDashboardPaletteFamily(_ family: DashboardPaletteFamily) {
        let palette = Self.dashboardColorPalette(for: family)
        let now = Date()
        dashboardSettings.paletteFamily = family
        dashboardSettings.updatedAt = now
        applyDashboardPalette(palette, updatedAt: now)
        persist()
    }

    public func setDashboardLegendVisible(_ isVisible: Bool) {
        guard dashboardSettings.showsLegend != isVisible else { return }
        dashboardSettings.showsLegend = isVisible
        dashboardSettings.updatedAt = Date()
        persist()
    }

    public func updateDashboardStatus(id: String, name: String? = nil, colorHex: String? = nil) {
        guard let index = dashboardStatuses.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            dashboardStatuses[index].name = trimmed.isEmpty ? "상태 \(index + 1)" : trimmed
        }
        if let colorHex {
            dashboardStatuses[index].colorHex = colorHex
        }
        dashboardStatuses[index].updatedAt = now
        dashboardSettings.updatedAt = now
        persist()
    }

    public func moveDashboardStatuses(from source: IndexSet, to destination: Int) {
        dashboardStatuses.move(fromOffsets: source, toOffset: destination)
        let now = Date()
        dashboardSettings.updatedAt = now
        normalizeDashboardStatusOrder(updatedAt: now)
        applyActiveDashboardPalette(updatedAt: now)
        persist()
    }

    public func removeDashboardStatuses(at offsets: IndexSet) {
        guard dashboardStatuses.count - offsets.count >= 1 else { return }
        let removedIds = Set(offsets.compactMap { dashboardStatuses.indices.contains($0) ? dashboardStatuses[$0].id : nil })
        dashboardStatuses.remove(atOffsets: offsets)
        guard let fallbackId = dashboardStatuses.last?.id else { return }
        for index in customers.indices where customers[index].dashboardStatusId.map(removedIds.contains) ?? false {
            customers[index].dashboardStatusId = fallbackId
            customers[index].updatedAt = Date()
        }
        let now = Date()
        dashboardSettings.statusCount = dashboardStatuses.count
        dashboardSettings.updatedAt = now
        normalizeDashboardStatusOrder(updatedAt: now)
        applyActiveDashboardPalette(updatedAt: now)
        persist()
    }

    public func saveGroupSmsCampaign(
        id: String,
        title: String,
        customerListId: String?,
        targetDescription: String,
        messageTemplate: String,
        recipients: [GroupSmsRecipient],
        status: GroupSmsCampaignStatus,
        scheduledAt: Date? = nil,
        scheduleNotificationIdentifier: String? = nil,
        scheduleDeviceIdentifier: String? = nil
    ) {
        let now = Date()
        let campaign = GroupSmsCampaign(
            id: id,
            title: title,
            customerListId: customerListId,
            targetDescription: targetDescription,
            messageTemplate: messageTemplate,
            status: status,
            recipients: recipients,
            scheduledAt: scheduledAt,
            scheduleNotificationIdentifier: scheduleNotificationIdentifier,
            scheduleDeviceIdentifier: scheduleDeviceIdentifier,
            requestedAt: status == .shortcutOpened || status == .requested ? now : nil,
            createdAt: now,
            updatedAt: now
        )
        groupSmsCampaigns.removeAll { $0.id == id }
        groupSmsCampaigns.insert(campaign, at: 0)
        persist()
    }

    public func groupSmsCampaign(id: String) -> GroupSmsCampaign? {
        groupSmsCampaigns.first { $0.id == id }
    }

    public func rescheduleGroupSmsCampaign(
        _ campaignId: String,
        scheduledAt: Date,
        notificationIdentifier: String
    ) {
        guard let index = groupSmsCampaigns.firstIndex(where: { $0.id == campaignId }) else { return }
        groupSmsCampaigns[index].status = .scheduled
        groupSmsCampaigns[index].scheduledAt = scheduledAt
        groupSmsCampaigns[index].scheduleNotificationIdentifier = notificationIdentifier
        groupSmsCampaigns[index].completedAt = nil
        groupSmsCampaigns[index].updatedAt = Date()
        actionMessage = "단체문자 예약 시간을 변경했습니다."
        persist()
    }

    public func markGroupSmsCampaign(_ campaignId: String, status: GroupSmsCampaignStatus) {
        guard let index = groupSmsCampaigns.firstIndex(where: { $0.id == campaignId }) else {
            actionMessage = "단체문자 캠페인을 찾지 못했습니다."
            return
        }

        let now = Date()
        groupSmsCampaigns[index].status = status
        groupSmsCampaigns[index].updatedAt = now
        if status == .shortcutOpened || status == .requested {
            groupSmsCampaigns[index].requestedAt = groupSmsCampaigns[index].requestedAt ?? now
        }
        if status == .requested || status == .cancelled || status == .shortcutFailed {
            groupSmsCampaigns[index].completedAt = now
        }

        if status == .requested {
            recordGroupSmsContactLogs(for: groupSmsCampaigns[index])
        }
        actionMessage = groupSmsStatusMessage(status)
        persist()
    }

    public func handleGroupSmsCallback(url: URL) {
        guard url.scheme == SoheeGroupSmsProductConfiguration.transport.callbackScheme else { return }
        let path = url.path
        guard path.hasPrefix("/group-sms") else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let campaignId = components?.queryItems?.first(where: { $0.name == "campaignId" })?.value else {
            actionMessage = "단체문자 콜백에 캠페인 ID가 없습니다."
            return
        }

        switch path {
        case "/group-sms/complete":
            markGroupSmsCampaign(campaignId, status: .requested)
        case "/group-sms/cancel":
            markGroupSmsCampaign(campaignId, status: .cancelled)
        case "/group-sms/error":
            markGroupSmsCampaign(campaignId, status: .shortcutFailed)
        default:
            break
        }
    }

    public func addNote(customer: Customer, memo: String) {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordContact(customer: customer, type: .note, result: .saved, messageBody: trimmed)
    }

    public func photos(for customer: Customer) -> [CustomerPhotoLog] {
        photoLogs
            .filter { $0.customerId == customer.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func photoURL(for log: CustomerPhotoLog, thumbnail: Bool = false) -> URL {
        fileStore.photoURL(fileName: thumbnail ? log.thumbnailFileName : log.fileName)
    }

    public func assetURL(fileName: String) -> URL {
        fileStore.assetURL(fileName: fileName)
    }

    public func addPhoto(customer: Customer, imageData: Data, source: CustomerPhotoSource, caption: String = "") {
        let now = Date()
        let photoId = UUID().uuidString
        let basePath = "customer-photos/\(customer.customerListId)/\(customer.id)"
        let fileName = "\(basePath)/\(photoId).jpg"
        let thumbnailFileName = "\(basePath)/\(photoId)-thumb.jpg"
        let originalData = Self.jpegData(from: imageData, maxDimension: 2200, compression: 0.86) ?? imageData
        let thumbnailData = Self.jpegData(from: imageData, maxDimension: 420, compression: 0.78) ?? originalData

        do {
            try fileStore.writePhotoData(originalData, fileName: fileName)
            try fileStore.writePhotoData(thumbnailData, fileName: thumbnailFileName)
            photoLogs.insert(
                CustomerPhotoLog(
                    id: photoId,
                    customerListId: customer.customerListId,
                    customerId: customer.id,
                    fileName: fileName,
                    thumbnailFileName: thumbnailFileName,
                    source: source,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption,
                    syncStatus: .localOnly,
                    createdAt: now
                ),
                at: 0
            )
            actionMessage = "\(photoSourceText(source)) 사진 메모를 저장했습니다."
            persist()
        } catch {
            actionMessage = "사진 메모 저장에 실패했습니다."
        }
    }

    func recordContactExport(_ summary: ContactExportSummary) {
        let results = summary.customerResults
        guard !results.isEmpty else { return }
        let now = Date()
        for result in results {
            guard let index = customers.firstIndex(where: { $0.id == result.customerId }) else { continue }
            customers[index].contactRegistrationStatus = result.status
            if let contactIdentifier = result.contactIdentifier {
                if customers[index].contactRegistrationOwnership != .createdByApp ||
                    customers[index].contactIdentifier != contactIdentifier {
                    customers[index].contactRegistrationOwnership = result.ownership
                }
                customers[index].contactIdentifier = contactIdentifier
                customers[index].contactRegisteredAt = now
                customers[index].contactRegisteredName = result.registeredName
            }
            customers[index].updatedAt = now
        }
        if let batch = summary.batch {
            contactExportBatches.append(batch)
        }
        actionMessage = "연락처 등록 결과를 저장했습니다."
        persist()
    }

    func applyContactCleanup(_ summary: ContactCleanupSummary) {
        let now = Date()
        let deletedContacts = Set(summary.deletedContactIdentifiers)
        let deletedGroups = Set(summary.deletedGroupIdentifiers)

        for index in customers.indices where customers[index].contactIdentifier.map(deletedContacts.contains) ?? false {
            customers[index].contactRegistrationStatus = nil
            customers[index].contactRegistrationOwnership = nil
            customers[index].contactIdentifier = nil
            customers[index].contactRegisteredAt = nil
            customers[index].contactRegisteredName = nil
            customers[index].updatedAt = now
        }

        for index in contactExportBatches.indices {
            let batchContacts = Set(contactExportBatches[index].records.map(\.contactIdentifier))
            let deletedInBatch = batchContacts.intersection(deletedContacts)
            if !deletedInBatch.isEmpty {
                contactExportBatches[index].deletedContactIdentifiers = Array(
                    Set(contactExportBatches[index].deletedContactIdentifiers).union(deletedInBatch)
                ).sorted()
                contactExportBatches[index].updatedAt = now
            }
            if let groupIdentifier = contactExportBatches[index].groupIdentifier,
               deletedGroups.contains(groupIdentifier) {
                contactExportBatches[index].groupDeletedAt = now
                contactExportBatches[index].updatedAt = now
            }
        }

        actionMessage = "연락처 \(deletedContacts.count)명과 그룹 \(deletedGroups.count)개를 삭제했습니다."
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
                kind: .completed,
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

    public func addVisitHistory(
        customer: Customer,
        kind: VisitLogKind,
        memo: String = "",
        locationAddress: String? = nil,
        mapSnapshotData: Data? = nil,
        audioData: Data? = nil,
        audioDuration: TimeInterval? = nil
    ) -> VisitLog? {
        let now = Date()
        let logId = UUID().uuidString
        let basePath = "visit-history/\(customer.customerListId)/\(customer.id)"
        var mapSnapshotFileName: String?
        var audioFileName: String?

        do {
            if let mapSnapshotData {
                let fileName = "\(basePath)/\(logId)-map.jpg"
                try fileStore.writeAssetData(mapSnapshotData, fileName: fileName)
                mapSnapshotFileName = fileName
            }
            if let audioData {
                let fileName = "\(basePath)/\(logId)-voice.m4a"
                try fileStore.writeAssetData(audioData, fileName: fileName)
                audioFileName = fileName
            }
        } catch {
            actionMessage = "방문 기록 파일 저장에 실패했습니다."
            return nil
        }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = VisitLog(
            id: logId,
            customerListId: customer.customerListId,
            customerId: customer.id,
            visitedAt: now,
            result: kind.rawValue,
            memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
            kind: kind,
            locationAddress: locationAddress?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            mapSnapshotFileName: mapSnapshotFileName,
            audioFileName: audioFileName,
            audioDuration: audioDuration,
            transcriptionStatus: audioFileName == nil ? nil : .pending,
            createdAt: now
        )
        visitLogs.insert(log, at: 0)
        actionMessage = "방문 히스토리를 저장했습니다."
        persist()

        if audioFileName != nil {
            transcribeVoiceMemoIfNeeded(logId: logId)
        }
        return log
    }

    public func updateVoiceTranscription(
        logId: String,
        transcript: String?,
        status: VoiceTranscriptionStatus,
        segments: [VoiceTranscriptionSegment]? = nil
    ) {
        guard let index = visitLogs.firstIndex(where: { $0.id == logId }) else { return }
        visitLogs[index].audioTranscript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        visitLogs[index].transcriptionStatus = status
        if let segments {
            visitLogs[index].audioSegments = segments
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
        historyEntries(for: customer).map { ($0.at, $0.title, $0.detail) }
    }

    public func historyEntries(for customer: Customer) -> [CustomerHistoryEntry] {
        let contacts = contactLogs
            .filter { $0.customerId == customer.id }
            .map {
                CustomerHistoryEntry(
                    id: "contact-\($0.id)",
                    at: $0.createdAt,
                    title: contactTitle($0),
                    detail: $0.messageBody ?? contactResultText($0.result)
                )
            }
        let visits = visitLogs
            .filter { $0.customerId == customer.id }
            .map {
                CustomerHistoryEntry(
                    id: "visit-\($0.id)",
                    at: $0.visitedAt,
                    title: visitTitle($0),
                    detail: visitDetail($0),
                    visitLog: $0
                )
            }
        let photos = photoLogs
            .filter { $0.customerId == customer.id }
            .map {
                CustomerHistoryEntry(
                    id: "photo-\($0.id)",
                    at: $0.createdAt,
                    title: "사진 메모",
                    detail: $0.caption ?? photoSourceText($0.source),
                    photoLog: $0
                )
            }
        return (contacts + visits + photos).sorted { $0.at > $1.at }
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

    public func exportSnapshotData(listIds: Set<String>? = nil) throws -> Data {
        try fileStore.encoder.encode(buildBackup(listIds: listIds))
    }

    func buildBackup(listIds: Set<String>? = nil) throws -> NativeFullBackup {
        let snapshot = snapshot(listIds: listIds)
        let photos = snapshot.photoLogs.map { log in
            NativePhotoBackupItem(
                id: log.id,
                fileName: log.fileName,
                thumbnailFileName: log.thumbnailFileName,
                imageDataBase64: try? fileStore.readPhotoData(fileName: log.fileName).base64EncodedString(),
                thumbnailDataBase64: try? fileStore.readPhotoData(fileName: log.thumbnailFileName).base64EncodedString()
            )
        }
        let visitAssets = snapshot.visitLogs.compactMap { log -> NativeAssetBackupItem? in
            guard log.mapSnapshotFileName != nil || log.audioFileName != nil else { return nil }
            return NativeAssetBackupItem(
                id: log.id,
                mapSnapshotFileName: log.mapSnapshotFileName,
                mapSnapshotDataBase64: log.mapSnapshotFileName.flatMap { try? fileStore.readAssetData(fileName: $0).base64EncodedString() },
                audioFileName: log.audioFileName,
                audioDataBase64: log.audioFileName.flatMap { try? fileStore.readAssetData(fileName: $0).base64EncodedString() }
            )
        }
        return NativeFullBackup(schemaVersion: 3, snapshot: snapshot, photos: photos, visitAssets: visitAssets)
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
            if let backup = try? fileStore.decoder.decode(NativeFullBackup.self, from: data) {
                restore(backup: backup, selectedListIds: nil)
                persist()
                storageMessage = "사진을 포함한 전체 백업을 가져왔습니다."
                return
            }

            let snapshot = try fileStore.decoder.decode(NativeAppSnapshot.self, from: data)
            restore(snapshot: snapshot)
            persist()
            storageMessage = "백업을 가져왔습니다."
        } catch {
            storageMessage = "백업을 가져오지 못했습니다."
        }
    }

    public func connectGoogleDrive() async {
        guard isGoogleDriveConfigured else {
            driveSyncMessage = "Google iOS OAuth Client ID 설정이 필요합니다."
            return
        }
        await runDriveOperation { [self] in
            let account = try await driveService.connect()
            driveAccount = account
            Self.saveDriveAccount(account)
            driveSyncMessage = "\(account.email) 계정으로 연결했습니다."
        }
    }

    public func disconnectGoogleDrive() {
        driveService.clearAuthorization()
        driveAccount = nil
        lastDriveSyncAt = nil
        cachedRemoteBackup = nil
        remoteDriveLists = []
        Self.clearDriveAccount()
        driveSyncMessage = "이 기기의 Google Drive 연결 정보를 삭제했습니다."
    }

    public func syncGoogleDriveAll() async {
        guard canUseDrive() else { return }
        await runDriveOperation { [self] in
            let accessToken = try await driveService.accessToken(for: GoogleDriveSyncService.appDataScopes)
            let localBackup = try buildBackup()
            if let remoteFile = try await driveService.findAppDataSyncFile(accessToken: accessToken) {
                let remoteBackup = try await driveService.downloadBackup(accessToken: accessToken, fileId: remoteFile.id)
                let merged = mergeBackups(remoteBackup, localBackup)
                restore(backup: merged, selectedListIds: nil)
                persist()
                try await driveService.updateAppDataSyncFile(accessToken: accessToken, fileId: remoteFile.id, backup: merged)
            } else {
                try await driveService.createAppDataSyncFile(accessToken: accessToken, backup: localBackup)
            }
            markDriveSyncComplete(message: "Google Drive 동기화를 완료했습니다.")
        }
    }

    public func saveAllToGoogleDrive() async {
        guard canUseDrive() else { return }
        await runDriveOperation { [self] in
            let accessToken = try await driveService.accessToken(for: GoogleDriveSyncService.appDataScopes)
            let backup = try buildBackup()
            if let remoteFile = try await driveService.findAppDataSyncFile(accessToken: accessToken) {
                try await driveService.updateAppDataSyncFile(accessToken: accessToken, fileId: remoteFile.id, backup: backup)
            } else {
                try await driveService.createAppDataSyncFile(accessToken: accessToken, backup: backup)
            }
            markDriveSyncComplete(message: "현재 기기 전체 데이터를 Drive에 저장했습니다.")
        }
    }

    public func loadRemoteDriveBackup() async {
        guard canUseDrive() else { return }
        await runDriveOperation { [self] in
            let accessToken = try await driveService.accessToken(for: GoogleDriveSyncService.appDataScopes)
            guard let remoteFile = try await driveService.findAppDataSyncFile(accessToken: accessToken) else {
                cachedRemoteBackup = nil
                remoteDriveLists = []
                driveSyncMessage = "Google Drive에 동기화 파일이 없습니다."
                return
            }
            let backup = try await driveService.downloadBackup(accessToken: accessToken, fileId: remoteFile.id)
            cachedRemoteBackup = backup
            remoteDriveLists = backup.snapshot.customerLists
            driveSyncMessage = "\(remoteDriveLists.count)개 고객리스트를 Drive에서 확인했습니다."
        }
    }

    public func restoreFromGoogleDrive(listIds: Set<String>? = nil) async {
        guard canUseDrive() else { return }
        await runDriveOperation { [self] in
            let backup: NativeFullBackup
            if let cachedRemoteBackup {
                backup = cachedRemoteBackup
            } else {
                let accessToken = try await driveService.accessToken(for: GoogleDriveSyncService.appDataScopes)
                guard let remoteFile = try await driveService.findAppDataSyncFile(accessToken: accessToken) else {
                    driveSyncMessage = "Google Drive에 동기화 파일이 없습니다."
                    return
                }
                backup = try await driveService.downloadBackup(accessToken: accessToken, fileId: remoteFile.id)
            }
            restore(backup: backup, selectedListIds: listIds)
            persist()
            markDriveSyncComplete(message: listIds == nil ? "Drive 전체 데이터를 이 기기에 복원했습니다." : "선택한 고객리스트를 Drive에서 복원했습니다.")
        }
    }

    public func createVisibleGoogleDriveBackup(listIds: Set<String>? = nil) async {
        guard canUseDrive() else { return }
        await runDriveOperation { [self] in
            let accessToken = try await driveService.accessToken(for: GoogleDriveSyncService.fileScopes)
            let backup = try buildBackup(listIds: listIds)
            try await driveService.createVisibleBackup(accessToken: accessToken, fileName: driveBackupFileName(listIds: listIds), backup: backup)
            driveSyncMessage = listIds == nil ? "Google Drive에 전체 백업 파일을 만들었습니다." : "Google Drive에 선택 고객리스트 백업 파일을 만들었습니다."
        }
    }

    private func restore(snapshot: NativeAppSnapshot) {
        customerLists = snapshot.customerLists
        customers = snapshot.customers
        visitLogs = snapshot.visitLogs
        contactLogs = snapshot.contactLogs
        photoLogs = snapshot.photoLogs
        visitSchedules = snapshot.visitSchedules
        visitScheduleItems = snapshot.visitScheduleItems
        messageTemplates = snapshot.messageTemplates.isEmpty ? Self.defaultTemplates() : snapshot.messageTemplates
        groupSmsCampaigns = snapshot.groupSmsCampaigns
        contactExportBatches = snapshot.contactExportBatches
        dashboardStatuses = snapshot.dashboardStatuses.isEmpty
            ? Self.defaultDashboardStatuses()
            : Self.migratingDefaultDashboardColors(snapshot.dashboardStatuses)
        dashboardSettings = snapshot.dashboardSettings
        dashboardSettings.statusCount = dashboardStatuses.count
        customers = Self.repairingDashboardAssignments(customers, statuses: dashboardStatuses)
        selectedListId = snapshot.selectedListId ?? customerLists.first?.id
    }

    private func restore(backup: NativeFullBackup, selectedListIds: Set<String>?) {
        guard let selectedListIds, !selectedListIds.isEmpty else {
            restore(snapshot: backup.snapshot)
            writePhotoData(from: backup.photos)
            writeVisitAssetData(from: backup.visitAssets)
            return
        }

        let remoteSnapshot = backup.snapshot
        let targetCustomerIds = Set(remoteSnapshot.customers.filter { selectedListIds.contains($0.customerListId) }.map(\.id))
        let targetScheduleIds = Set(remoteSnapshot.visitSchedules.filter { selectedListIds.contains($0.customerListId) }.map(\.id))

        customerLists.removeAll { selectedListIds.contains($0.id) }
        customers.removeAll { selectedListIds.contains($0.customerListId) }
        visitLogs.removeAll { selectedListIds.contains($0.customerListId) || targetCustomerIds.contains($0.customerId) }
        contactLogs.removeAll { selectedListIds.contains($0.customerListId) || targetCustomerIds.contains($0.customerId) }
        photoLogs.removeAll { selectedListIds.contains($0.customerListId) || targetCustomerIds.contains($0.customerId) }
        visitSchedules.removeAll { selectedListIds.contains($0.customerListId) }
        visitScheduleItems.removeAll { selectedListIds.contains($0.customerListId) || targetScheduleIds.contains($0.scheduleId) || targetCustomerIds.contains($0.customerId) }
        groupSmsCampaigns.removeAll { campaign in
            campaign.customerListId.map { selectedListIds.contains($0) } ?? false ||
            campaign.recipients.contains { $0.customerId.map { targetCustomerIds.contains($0) } ?? false }
        }
        contactExportBatches.removeAll { selectedListIds.contains($0.customerListId) }

        let restoredLists = remoteSnapshot.customerLists.filter { selectedListIds.contains($0.id) }
        let restoredCustomers = remoteSnapshot.customers.filter { selectedListIds.contains($0.customerListId) }
        let restoredCustomerIds = Set(restoredCustomers.map(\.id))
        let restoredSchedules = remoteSnapshot.visitSchedules.filter { selectedListIds.contains($0.customerListId) }
        let restoredScheduleIds = Set(restoredSchedules.map(\.id))
        let restoredPhotoLogs = remoteSnapshot.photoLogs.filter { selectedListIds.contains($0.customerListId) && restoredCustomerIds.contains($0.customerId) }

        customerLists.append(contentsOf: restoredLists)
        customers.append(contentsOf: restoredCustomers)
        visitLogs.append(contentsOf: remoteSnapshot.visitLogs.filter { selectedListIds.contains($0.customerListId) && restoredCustomerIds.contains($0.customerId) })
        contactLogs.append(contentsOf: remoteSnapshot.contactLogs.filter { selectedListIds.contains($0.customerListId) && restoredCustomerIds.contains($0.customerId) })
        photoLogs.append(contentsOf: restoredPhotoLogs)
        visitSchedules.append(contentsOf: restoredSchedules)
        visitScheduleItems.append(contentsOf: remoteSnapshot.visitScheduleItems.filter { selectedListIds.contains($0.customerListId) && restoredScheduleIds.contains($0.scheduleId) && restoredCustomerIds.contains($0.customerId) })
        groupSmsCampaigns.append(contentsOf: remoteSnapshot.groupSmsCampaigns.filter { campaign in
            campaign.customerListId.map { selectedListIds.contains($0) } ?? false ||
            campaign.recipients.contains { $0.customerId.map { restoredCustomerIds.contains($0) } ?? false }
        })
        contactExportBatches.append(contentsOf: remoteSnapshot.contactExportBatches.filter { selectedListIds.contains($0.customerListId) })
        messageTemplates = mergeById(messageTemplates, remoteSnapshot.messageTemplates) { $0.updatedAt < $1.updatedAt }
        if !remoteSnapshot.dashboardStatuses.isEmpty {
            dashboardStatuses = Self.migratingDefaultDashboardColors(remoteSnapshot.dashboardStatuses)
        }
        dashboardSettings = remoteSnapshot.dashboardSettings
        dashboardSettings.statusCount = dashboardStatuses.count
        customers = Self.repairingDashboardAssignments(customers, statuses: dashboardStatuses)
        selectedListId = restoredLists.first?.id ?? selectedListId ?? customerLists.first?.id

        let restoredVisitLogs = remoteSnapshot.visitLogs.filter { selectedListIds.contains($0.customerListId) && restoredCustomerIds.contains($0.customerId) }
        let photoFileNames = Set(restoredPhotoLogs.flatMap { [$0.fileName, $0.thumbnailFileName] })
        let visitFileNames = Set(restoredVisitLogs.flatMap { [$0.mapSnapshotFileName, $0.audioFileName].compactMap { $0 } })
        writePhotoData(from: backup.photos.filter { photoFileNames.contains($0.fileName) || photoFileNames.contains($0.thumbnailFileName) })
        writeVisitAssetData(from: backup.visitAssets.filter { asset in
            asset.mapSnapshotFileName.map { visitFileNames.contains($0) } ?? false ||
            asset.audioFileName.map { visitFileNames.contains($0) } ?? false
        })
    }

    private func writePhotoData(from photos: [NativePhotoBackupItem]) {
        for photo in photos {
            if let imageBase64 = photo.imageDataBase64,
               let imageData = Data(base64Encoded: imageBase64) {
                try? fileStore.writePhotoData(imageData, fileName: photo.fileName)
            }
            if let thumbnailBase64 = photo.thumbnailDataBase64,
               let thumbnailData = Data(base64Encoded: thumbnailBase64) {
                try? fileStore.writePhotoData(thumbnailData, fileName: photo.thumbnailFileName)
            }
        }
    }

    private func writeVisitAssetData(from assets: [NativeAssetBackupItem]) {
        for asset in assets {
            if let fileName = asset.mapSnapshotFileName,
               let base64 = asset.mapSnapshotDataBase64,
               let data = Data(base64Encoded: base64) {
                try? fileStore.writeAssetData(data, fileName: fileName)
            }
            if let fileName = asset.audioFileName,
               let base64 = asset.audioDataBase64,
               let data = Data(base64Encoded: base64) {
                try? fileStore.writeAssetData(data, fileName: fileName)
            }
        }
    }

    private func canUseDrive() -> Bool {
        guard isGoogleDriveConfigured else {
            driveSyncMessage = "Google iOS OAuth Client ID 설정이 필요합니다."
            return false
        }
        guard driveAccount != nil else {
            driveSyncMessage = "먼저 Google 계정으로 연결하세요."
            return false
        }
        guard driveService.hasStoredAuthorization else {
            driveAccount = nil
            driveSyncMessage = "Google 계정 보안 인증을 갱신해야 합니다. 계정을 한 번 다시 연결하세요."
            return false
        }
        return true
    }

    private func runDriveOperation(_ operation: @escaping () async throws -> Void) async {
        guard !driveSyncBusy else { return }
        driveSyncBusy = true
        defer { driveSyncBusy = false }
        do {
            try await operation()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            driveSyncMessage = "Google 로그인을 취소했습니다."
        } catch let error as GoogleDriveSyncError {
            if case .authorizationRequired = error {
                driveAccount = nil
                Self.clearDriveAccount()
            }
            driveSyncMessage = error.localizedDescription
        } catch {
            driveSyncMessage = "Google Drive 작업에 실패했습니다: \(error.localizedDescription)"
        }
    }

    private func markDriveSyncComplete(message: String) {
        let now = Date()
        lastDriveSyncAt = now
        Self.saveLastDriveSyncAt(now)
        driveSyncMessage = message
    }

    private func driveBackupFileName(listIds: Set<String>?) -> String {
        let date = DateFormatter.nativeDriveBackupDate.string(from: Date())
        guard let listIds, !listIds.isEmpty else {
            return "소희가간다-전체백업-\(date).json"
        }
        if listIds.count == 1,
           let listName = customerLists.first(where: { listIds.contains($0.id) })?.name {
            return "소희가간다-\(safeDriveFileName(listName))-백업-\(date).json"
        }
        return "소희가간다-\(listIds.count)개리스트-백업-\(date).json"
    }

    private func safeDriveFileName(_ name: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: disallowed).joined(separator: "_")
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
            photoLogs = []
            visitSchedules = []
            visitScheduleItems = []
            messageTemplates = Self.defaultTemplates()
            groupSmsCampaigns = []
            contactExportBatches = []
            dashboardStatuses = Self.defaultDashboardStatuses()
            dashboardSettings = DashboardHeatmapSettings()
            selectedListId = seed.lists.first?.id
        } else {
            customerLists = []
            customers = []
            visitLogs = []
            contactLogs = []
            photoLogs = []
            visitSchedules = []
            visitScheduleItems = []
            messageTemplates = Self.defaultTemplates()
            groupSmsCampaigns = []
            contactExportBatches = []
            dashboardStatuses = Self.defaultDashboardStatuses()
            dashboardSettings = DashboardHeatmapSettings()
            selectedListId = nil
        }
        do {
            try fileStore.deleteAllAppData()
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

    private func snapshot(listIds: Set<String>? = nil) -> NativeAppSnapshot {
        let filteredLists = customerLists.filter { listIds?.contains($0.id) ?? true }
        let filteredListIds = Set(filteredLists.map(\.id))
        let filteredCustomers = customers.filter { filteredListIds.contains($0.customerListId) }
        let filteredCustomerIds = Set(filteredCustomers.map(\.id))
        let filteredSchedules = visitSchedules.filter { filteredListIds.contains($0.customerListId) }
        let filteredScheduleIds = Set(filteredSchedules.map(\.id))

        return NativeAppSnapshot(
            customerLists: filteredLists,
            customers: filteredCustomers,
            visitLogs: visitLogs.filter { filteredListIds.contains($0.customerListId) && filteredCustomerIds.contains($0.customerId) },
            contactLogs: contactLogs.filter { filteredListIds.contains($0.customerListId) && filteredCustomerIds.contains($0.customerId) },
            photoLogs: photoLogs.filter { filteredListIds.contains($0.customerListId) && filteredCustomerIds.contains($0.customerId) },
            visitSchedules: filteredSchedules,
            visitScheduleItems: visitScheduleItems.filter { filteredListIds.contains($0.customerListId) && filteredScheduleIds.contains($0.scheduleId) && filteredCustomerIds.contains($0.customerId) },
            messageTemplates: messageTemplates,
            groupSmsCampaigns: groupSmsCampaigns.filter { campaign in
                campaign.customerListId.map { filteredListIds.contains($0) } ?? false ||
                campaign.recipients.contains { $0.customerId.map { filteredCustomerIds.contains($0) } ?? false }
            },
            contactExportBatches: contactExportBatches.filter { filteredListIds.contains($0.customerListId) },
            dashboardStatuses: dashboardStatuses,
            dashboardSettings: dashboardSettings,
            selectedListId: selectedListId.flatMap { filteredListIds.contains($0) ? $0 : nil } ?? filteredLists.first?.id
        )
    }

    private func makeCustomers(
        from importedContacts: [ContactImportCustomer],
        customerListId: String,
        now: Date,
        skipDuplicatePhones: Bool
    ) -> (customers: [Customer], skippedCount: Int) {
        var existingPhones = Set(customers.map { ContactExportService.normalizedPhone($0.phoneNumber) }.filter { !$0.isEmpty })
        var skippedCount = 0
        var nextCustomers: [Customer] = []

        for imported in importedContacts {
            let normalizedPhone = ContactExportService.normalizedPhone(imported.phoneNumber)
            if skipDuplicatePhones, !normalizedPhone.isEmpty, existingPhones.contains(normalizedPhone) {
                skippedCount += 1
                continue
            }
            if !normalizedPhone.isEmpty {
                existingPhones.insert(normalizedPhone)
            }
            let address = imported.address.trimmingCharacters(in: .whitespacesAndNewlines)
            nextCustomers.append(
                Customer(
                    id: UUID().uuidString,
                    customerListId: customerListId,
                    name: imported.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "이름 없음" : imported.name,
                    phoneNumber: imported.phoneNumber,
                    address: address,
                    notes: imported.notes,
                    region: extractRegion(address),
                    status: .open,
                    contactIdentifier: imported.contactIdentifier,
                    contactRegisteredName: imported.name,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        return (nextCustomers, skippedCount)
    }

    private func contactTitle(_ log: ContactLog) -> String {
        switch log.type {
        case .call: return "전화 시도"
        case .manualSms: return "문자 시도"
        case .templateSms: return "템플릿 문자"
        case .groupSms: return "단체문자 요청"
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

    private func recordGroupSmsContactLogs(for campaign: GroupSmsCampaign) {
        let now = Date()
        let knownCustomers = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0) })
        let existingKeys = Set(contactLogs.compactMap { log -> String? in
            guard log.type == .groupSms, log.templateId == campaign.id else { return nil }
            return "\(log.customerId)-\(campaign.id)"
        })

        let newLogs = campaign.recipients.compactMap { recipient -> ContactLog? in
            guard let customerId = recipient.customerId,
                  let customer = knownCustomers[customerId],
                  !existingKeys.contains("\(customerId)-\(campaign.id)") else {
                return nil
            }
            return ContactLog(
                id: UUID().uuidString,
                customerListId: customer.customerListId,
                customerId: customer.id,
                type: .groupSms,
                templateId: campaign.id,
                messageBody: recipient.messageBody,
                result: .opened,
                createdAt: now
            )
        }
        contactLogs.insert(contentsOf: newLogs, at: 0)
    }

    private func groupSmsStatusMessage(_ status: GroupSmsCampaignStatus) -> String {
        switch status {
        case .draft:
            return "단체문자 캠페인을 임시 저장했습니다."
        case .ready:
            return "단체문자 캠페인을 준비했습니다."
        case .scheduled:
            return "단체문자 발송 알림을 예약했습니다."
        case .due:
            return "예약한 단체문자의 발송 시간이 되었습니다."
        case .shortcutOpened:
            return "단체문자 단축어를 열었습니다."
        case .requested:
            return "단체문자 발송 요청 완료 콜백을 받았습니다."
        case .cancelled:
            return "단체문자 단축어 실행이 취소되었습니다."
        case .shortcutFailed:
            return "단체문자 단축어 실행 오류가 기록되었습니다."
        case .unknown:
            return "단체문자 상태를 확인하지 못했습니다."
        }
    }

    private func photoSourceText(_ source: CustomerPhotoSource) -> String {
        switch source {
        case .camera:
            return "카메라 촬영"
        case .photoLibrary:
            return "사진앱에서 불러옴"
        case .file:
            return "이미지 파일에서 불러옴"
        }
    }

    private func visitTitle(_ log: VisitLog) -> String {
        switch log.kind {
        case .quickLocation:
            return "방문"
        case .textMemo:
            return "텍스트 메모"
        case .photoMemo:
            return "사진 메모"
        case .voiceMemo:
            return "음성 메모"
        case .completed:
            return "방문 완료"
        case .none:
            return log.result == "completed" ? "방문 완료" : "방문"
        }
    }

    private func visitDetail(_ log: VisitLog) -> String {
        var parts: [String] = []
        if let memo = log.memo, !memo.isEmpty {
            parts.append(memo)
        }
        if let locationAddress = log.locationAddress, !locationAddress.isEmpty {
            parts.append(locationAddress)
        }
        if log.kind == .voiceMemo {
            if let transcript = log.audioTranscript, !transcript.isEmpty {
                parts.append(transcript)
            } else if let status = log.transcriptionStatus {
                parts.append(voiceTranscriptionText(status))
            }
        }
        return parts.isEmpty ? "방문 기록" : parts.joined(separator: " · ")
    }

    private func voiceTranscriptionText(_ status: VoiceTranscriptionStatus) -> String {
        switch status {
        case .pending:
            return "전사 대기중"
        case .transcribing:
            return "전사중"
        case .completed:
            return "전사 완료"
        case .failed:
            return "전사 실패"
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

    private func mergeBackups(_ remote: NativeFullBackup, _ local: NativeFullBackup) -> NativeFullBackup {
        let mergedLists = mergeById(remote.snapshot.customerLists, local.snapshot.customerLists) { $0.updatedAt < $1.updatedAt }
        let mergedCustomers = mergeById(remote.snapshot.customers, local.snapshot.customers) { $0.updatedAt < $1.updatedAt }
        let mergedVisitLogs = mergeById(remote.snapshot.visitLogs, local.snapshot.visitLogs) { $0.createdAt < $1.createdAt }
        let mergedContactLogs = mergeById(remote.snapshot.contactLogs, local.snapshot.contactLogs) { $0.createdAt < $1.createdAt }
        let mergedPhotoLogs = mergeById(remote.snapshot.photoLogs, local.snapshot.photoLogs) { $0.createdAt < $1.createdAt }
        let mergedSchedules = mergeById(remote.snapshot.visitSchedules, local.snapshot.visitSchedules) { $0.updatedAt < $1.updatedAt }
        let mergedScheduleItems = mergeById(remote.snapshot.visitScheduleItems, local.snapshot.visitScheduleItems) { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let mergedTemplates = mergeById(remote.snapshot.messageTemplates, local.snapshot.messageTemplates) { $0.updatedAt < $1.updatedAt }
        let mergedGroupSmsCampaigns = mergeById(remote.snapshot.groupSmsCampaigns, local.snapshot.groupSmsCampaigns) { $0.updatedAt < $1.updatedAt }
        let mergedContactExportBatches = mergeById(remote.snapshot.contactExportBatches, local.snapshot.contactExportBatches) { $0.updatedAt < $1.updatedAt }
        let localDashboardSettingsAreNewer = remote.snapshot.dashboardSettings.updatedAt < local.snapshot.dashboardSettings.updatedAt
        let mergedDashboardSettings = localDashboardSettingsAreNewer
            ? local.snapshot.dashboardSettings
            : remote.snapshot.dashboardSettings
        let settingsHaveNoMergeVersion = remote.snapshot.dashboardSettings.updatedAt == .distantPast
            && local.snapshot.dashboardSettings.updatedAt == .distantPast
        let authoritativeDashboardStatuses = localDashboardSettingsAreNewer
            ? local.snapshot.dashboardStatuses
            : remote.snapshot.dashboardStatuses
        let mergedDashboardStatuses = settingsHaveNoMergeVersion || authoritativeDashboardStatuses.isEmpty
            ? mergeById(remote.snapshot.dashboardStatuses, local.snapshot.dashboardStatuses) { $0.updatedAt < $1.updatedAt }
            : authoritativeDashboardStatuses
        var resolvedDashboardSettings = mergedDashboardSettings
        resolvedDashboardSettings.statusCount = mergedDashboardStatuses.count
        let snapshot = NativeAppSnapshot(
            customerLists: mergedLists,
            customers: mergedCustomers,
            visitLogs: mergedVisitLogs,
            contactLogs: mergedContactLogs,
            photoLogs: mergedPhotoLogs,
            visitSchedules: mergedSchedules,
            visitScheduleItems: mergedScheduleItems,
            messageTemplates: mergedTemplates,
            groupSmsCampaigns: mergedGroupSmsCampaigns,
            contactExportBatches: mergedContactExportBatches,
            dashboardStatuses: mergedDashboardStatuses.sorted { $0.orderIndex < $1.orderIndex },
            dashboardSettings: resolvedDashboardSettings,
            selectedListId: local.snapshot.selectedListId ?? remote.snapshot.selectedListId,
            savedAt: Date()
        )
        let mergedPhotos = mergeById(remote.photos, local.photos) { lhs, rhs in
            (lhs.imageDataBase64 == nil && rhs.imageDataBase64 != nil) || (lhs.thumbnailDataBase64 == nil && rhs.thumbnailDataBase64 != nil)
        }
        let mergedVisitAssets = mergeById(remote.visitAssets, local.visitAssets) { lhs, rhs in
            (lhs.mapSnapshotDataBase64 == nil && rhs.mapSnapshotDataBase64 != nil) || (lhs.audioDataBase64 == nil && rhs.audioDataBase64 != nil)
        }
        return NativeFullBackup(schemaVersion: max(remote.schemaVersion, local.schemaVersion), snapshot: snapshot, photos: mergedPhotos, visitAssets: mergedVisitAssets)
    }

    private func mergeById<T: Identifiable>(_ first: [T], _ second: [T], preferSecond: (T, T) -> Bool) -> [T] where T.ID: Hashable {
        var merged: [T.ID: T] = [:]
        for item in first {
            merged[item.id] = item
        }
        for item in second {
            if let existing = merged[item.id] {
                if preferSecond(existing, item) {
                    merged[item.id] = item
                }
            } else {
                merged[item.id] = item
            }
        }
        return Array(merged.values)
    }

    private func normalizeDashboardStatusOrder(updatedAt: Date) {
        for index in dashboardStatuses.indices {
            dashboardStatuses[index].orderIndex = index
            dashboardStatuses[index].updatedAt = updatedAt
        }
    }

    private func applyActiveDashboardPalette(updatedAt: Date) {
        applyDashboardPalette(activeDashboardColorPalette, updatedAt: updatedAt)
    }

    private func applyDashboardPalette(_ palette: [String], updatedAt: Date) {
        for index in dashboardStatuses.indices {
            dashboardStatuses[index].colorHex = Self.dashboardColor(
                at: index,
                statusCount: dashboardStatuses.count,
                palette: palette
            )
            dashboardStatuses[index].updatedAt = updatedAt
        }
    }

    public static func dashboardColorPalette(for family: DashboardPaletteFamily) -> [String] {
        switch family {
        case .blue:
            return ["EAF3FF", "D8EAFF", "C2DDFF", "A5CEFF", "7EB7FF", "579EF2", "367FD9", "1F64BE", "124A96", "08366F"]
        case .green:
            return ["EAF8EF", "D8F1E2", "BFE7D0", "9CD9B7", "72C496", "4AAA72", "2F8F56", "237443", "185C34", "0E4326"]
        case .purple:
            return ["F4EEFF", "E9DDFF", "D8C6FF", "C1A5F7", "A989EB", "8C6AD8", "704FC2", "5939A8", "43287F", "2E1959"]
        case .orange:
            return ["FFF4E8", "FFE8CF", "FFD7AD", "FFC17F", "F6A855", "E98C32", "D5721E", "B85A12", "93440C", "6D3007"]
        case .red:
            return ["FFEDEE", "FFDADC", "FFC0C4", "FC9DA4", "F47782", "E15462", "C63C4B", "A92B39", "861E2B", "64121D"]
        case .gray:
            return ["F5F7FA", "E8EBF0", "D7DCE3", "C1C8D2", "A7B0BD", "8995A5", "6D7989", "535E6C", "3B444F", "252C34"]
        }
    }

    private static let legacyDashboardColorPalette = [
        "5B8FF9", "8067DC", "5D9CEC", "22B8A7", "66B86B",
        "B3C83F", "F2C94C", "F2994A", "EB6A5B", "8A94A6",
        "D65DB1", "00A6A6", "7A9E35", "C77D31", "9B6BCE"
    ]

    private static func migratingDefaultDashboardColors(
        _ statuses: [DashboardStatusDefinition]
    ) -> [DashboardStatusDefinition] {
        let legacyColors = Set(legacyDashboardColorPalette)
        let migrationDate = Date()
        let sortedStatuses = statuses.sorted { $0.orderIndex < $1.orderIndex }
        let bluePalette = dashboardColorPalette(for: .blue)

        return sortedStatuses.map { status in
            let normalizedColor = status.colorHex.uppercased()
            guard status.id.hasPrefix("dashboard-status-"),
                  legacyColors.contains(normalizedColor) else {
                return status
            }

            var migrated = status
            migrated.colorHex = dashboardColor(
                at: status.orderIndex,
                statusCount: sortedStatuses.count,
                palette: bluePalette
            )
            migrated.updatedAt = migrationDate
            return migrated
        }
    }

    private static func defaultDashboardStatuses() -> [DashboardStatusDefinition] {
        let names = ["신규", "연락 대기", "상담 진행", "후속 관리", "완료"]
        let palette = dashboardColorPalette(for: .blue)
        let now = Date()
        return names.enumerated().map { index, name in
            DashboardStatusDefinition(
                id: "dashboard-status-\(index + 1)",
                name: name,
                colorHex: dashboardColor(at: index, statusCount: names.count, palette: palette),
                orderIndex: index,
                updatedAt: now
            )
        }
    }

    private static func dashboardColor(at index: Int, statusCount: Int, palette: [String]) -> String {
        guard let first = palette.first else { return "5B8FF9" }
        guard statusCount > 1 else { return first }
        let position = Double(index) * Double(palette.count - 1) / Double(statusCount - 1)
        return palette[min(max(Int(position.rounded()), 0), palette.count - 1)]
    }

    private static func repairingDashboardAssignments(
        _ customers: [Customer],
        statuses: [DashboardStatusDefinition]
    ) -> [Customer] {
        let validStatusIds = Set(statuses.map(\.id))
        guard let fallbackStatusId = statuses.last?.id else { return customers }

        return customers.map { customer in
            guard let statusId = customer.dashboardStatusId,
                  !validStatusIds.contains(statusId) else {
                return customer
            }
            var repaired = customer
            repaired.dashboardStatusId = fallbackStatusId
            return repaired
        }
    }

    private static func loadDriveAccount() -> GoogleDriveAccount? {
        guard let data = UserDefaults.standard.data(forKey: "nativeGoogleDriveAccount") else { return nil }
        return try? JSONDecoder().decode(GoogleDriveAccount.self, from: data)
    }

    private static func saveDriveAccount(_ account: GoogleDriveAccount) {
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: "nativeGoogleDriveAccount")
        }
    }

    private static func clearDriveAccount() {
        UserDefaults.standard.removeObject(forKey: "nativeGoogleDriveAccount")
        UserDefaults.standard.removeObject(forKey: "nativeGoogleDriveLastSyncAt")
    }

    private static func loadLastDriveSyncAt() -> Date? {
        UserDefaults.standard.object(forKey: "nativeGoogleDriveLastSyncAt") as? Date
    }

    private static func saveLastDriveSyncAt(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "nativeGoogleDriveLastSyncAt")
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

    private static func jpegData(from data: Data, maxDimension: CGFloat, compression: CGFloat) -> Data? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        let scaled = image.scaled(maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: compression)
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        let scaled = image.scaled(maxDimension: maxDimension)
        guard let tiffData = scaled.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
        #else
        return nil
        #endif
    }
}

struct NativeFullBackup: Codable {
    var schemaVersion: Int
    var snapshot: NativeAppSnapshot
    var photos: [NativePhotoBackupItem]
    var visitAssets: [NativeAssetBackupItem] = []

    init(schemaVersion: Int, snapshot: NativeAppSnapshot, photos: [NativePhotoBackupItem], visitAssets: [NativeAssetBackupItem] = []) {
        self.schemaVersion = schemaVersion
        self.snapshot = snapshot
        self.photos = photos
        self.visitAssets = visitAssets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        snapshot = try container.decode(NativeAppSnapshot.self, forKey: .snapshot)
        photos = try container.decodeIfPresent([NativePhotoBackupItem].self, forKey: .photos) ?? []
        visitAssets = try container.decodeIfPresent([NativeAssetBackupItem].self, forKey: .visitAssets) ?? []
    }
}

struct NativePhotoBackupItem: Codable, Identifiable {
    var id: String
    var fileName: String
    var thumbnailFileName: String
    var imageDataBase64: String?
    var thumbnailDataBase64: String?
}

struct NativeAssetBackupItem: Codable, Identifiable {
    var id: String
    var mapSnapshotFileName: String?
    var mapSnapshotDataBase64: String?
    var audioFileName: String?
    var audioDataBase64: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#if os(iOS)
private extension UIImage {
    func scaled(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return self }
        let ratio = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
#endif

#if os(macOS)
private extension NSImage {
    func scaled(maxDimension: CGFloat) -> NSImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return self }
        let ratio = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        draw(in: CGRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }
}
#endif

private extension DateFormatter {
    static let nativeDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let nativeDriveBackupDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
