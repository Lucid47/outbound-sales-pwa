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

public struct CustomerListDeletionImpact: Equatable {
    public var customerCount: Int
    public var visitLogCount: Int
    public var contactLogCount: Int
    public var photoLogCount: Int
    public var scheduleCount: Int
    public var campaignCount: Int

    public var storedFileCount: Int {
        photoLogCount * 2
    }
}

public struct CustomerDeletionImpact: Equatable {
    public var visitLogCount: Int
    public var contactLogCount: Int
    public var photoLogCount: Int
    public var scheduleItemCount: Int
}

public struct CustomerActivitySummary: Equatable {
    public var totalCount: Int
    public var callCount: Int
    public var messageCount: Int
    public var visitCount: Int
    public var memoCount: Int
    public var customerCount: Int
}

@MainActor
public final class NativeAppState: ObservableObject {
    @Published private var storedCustomerLists: [CustomerList]
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
    @Published public private(set) var managementPeriods: [ManagementPeriod]
    @Published public private(set) var activityEvents: [CustomerActivityEvent]
    @Published public private(set) var stageChangeLogs: [CustomerStageChangeLog]
    @Published public private(set) var deletionTombstones: [DeletedRecordTombstone]
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
                self.storedCustomerLists = snapshot.customerLists
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
                self.managementPeriods = snapshot.managementPeriods
                self.activityEvents = snapshot.activityEvents
                self.stageChangeLogs = snapshot.stageChangeLogs
                self.deletionTombstones = snapshot.deletionTombstones
                let activeLists = snapshot.customerLists.filter { $0.archivedAt == nil }
                self.selectedListId = snapshot.selectedListId.flatMap { selectedId in
                    activeLists.contains { $0.id == selectedId } ? selectedId : nil
                } ?? activeLists.first?.id
                self.applyDeletionTombstonesToLoadedData()
                self.resolveSelectedList()
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
            self.storedCustomerLists = seed.lists
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
            self.managementPeriods = []
            self.activityEvents = []
            self.stageChangeLogs = []
            self.deletionTombstones = []
            self.selectedListId = seed.lists.first?.id
        } else {
            self.storedCustomerLists = []
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
            self.managementPeriods = []
            self.activityEvents = []
            self.stageChangeLogs = []
            self.deletionTombstones = []
            self.selectedListId = nil
        }
        if needsDriveReconnect {
            self.driveSyncMessage = "보안 인증 방식이 갱신되었습니다. Google 계정을 한 번 다시 연결하세요."
        }
    }

    public var customerLists: [CustomerList] {
        storedCustomerLists.filter { $0.archivedAt == nil }
    }

    public var archivedCustomerLists: [CustomerList] {
        storedCustomerLists.filter { $0.archivedAt != nil }
    }

    public var selectedList: CustomerList? {
        customerLists.first { $0.id == selectedListId }
    }

    public var visibleCustomers: [Customer] {
        let activeListIds = Set(customerLists.map(\.id))
        let scoped = selectedListId.map { id in
            customers.filter { $0.customerListId == id }
        } ?? customers.filter { activeListIds.contains($0.customerListId) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { customer in
            let additionalValues = (customer.additionalAddresses ?? []).flatMap { [$0.label, $0.value] }
            let customValues = (customer.customFields ?? []).flatMap { [$0.label, $0.value] }
            return ([customer.name, customer.phoneNumber, customer.address, customer.notes] + additionalValues + customValues)
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
        guard list.archivedAt == nil else { return }
        selectedListId = list.id
        persist()
    }

    public func customerCount(in listId: String) -> Int {
        customers.count { $0.customerListId == listId }
    }

    public func deletionImpact(for listId: String) -> CustomerListDeletionImpact {
        let customerIds = Set(customers.filter { $0.customerListId == listId }.map(\.id))
        return CustomerListDeletionImpact(
            customerCount: customerIds.count,
            visitLogCount: visitLogs.count { $0.customerListId == listId || customerIds.contains($0.customerId) },
            contactLogCount: contactLogs.count { $0.customerListId == listId || customerIds.contains($0.customerId) },
            photoLogCount: photoLogs.count { $0.customerListId == listId || customerIds.contains($0.customerId) },
            scheduleCount: visitSchedules.count { $0.customerListId == listId },
            campaignCount: groupSmsCampaigns.count { campaign in
                campaign.customerListId == listId || campaign.recipients.contains { recipient in
                    recipient.customerId.map(customerIds.contains) ?? false
                }
            }
        )
    }

    public func deletionImpact(forCustomerId customerId: String) -> CustomerDeletionImpact {
        CustomerDeletionImpact(
            visitLogCount: visitLogs.count { $0.customerId == customerId },
            contactLogCount: contactLogs.count { $0.customerId == customerId },
            photoLogCount: photoLogs.count { $0.customerId == customerId },
            scheduleItemCount: visitScheduleItems.count { $0.customerId == customerId }
        )
    }

    public func renameCustomerList(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = storedCustomerLists.firstIndex(where: { $0.id == id }) else { return }
        let previousName = storedCustomerLists[index].name
        guard previousName != trimmed else { return }
        let now = Date()
        storedCustomerLists[index].name = trimmed
        storedCustomerLists[index].companyName = trimmed
        storedCustomerLists[index].updatedAt = now
        recordActivity(
            kind: .listRenamed,
            occurredAt: now,
            customerListId: id,
            title: "고객리스트 이름 변경",
            detail: "\(previousName) -> \(trimmed)"
        )
        persist()
    }

    public func archiveCustomerList(id: String) {
        guard let index = storedCustomerLists.firstIndex(where: { $0.id == id && $0.archivedAt == nil }) else { return }
        let now = Date()
        let listName = storedCustomerLists[index].name
        storedCustomerLists[index].archivedAt = now
        storedCustomerLists[index].updatedAt = now
        recordActivity(
            kind: .listArchived,
            occurredAt: now,
            customerListId: id,
            title: "고객리스트 보관",
            detail: listName
        )
        resolveSelectedList(excluding: id)
        actionMessage = "\(listName)을 보관했습니다. 언제든 복원할 수 있습니다."
        persist()
    }

    public func restoreCustomerList(id: String) {
        guard let index = storedCustomerLists.firstIndex(where: { $0.id == id && $0.archivedAt != nil }) else { return }
        let now = Date()
        let listName = storedCustomerLists[index].name
        storedCustomerLists[index].archivedAt = nil
        storedCustomerLists[index].updatedAt = now
        recordActivity(
            kind: .listRestored,
            occurredAt: now,
            customerListId: id,
            title: "고객리스트 복원",
            detail: listName
        )
        selectedListId = id
        actionMessage = "\(listName)을 복원했습니다."
        persist()
    }

    public func moveAllCustomers(from sourceListId: String, to targetListId: String) {
        guard sourceListId != targetListId,
              let sourceIndex = storedCustomerLists.firstIndex(where: { $0.id == sourceListId }),
              let targetIndex = storedCustomerLists.firstIndex(where: { $0.id == targetListId && $0.archivedAt == nil }) else { return }
        let movedCustomerIds = Set(customers.filter { $0.customerListId == sourceListId }.map(\.id))
        guard !movedCustomerIds.isEmpty else { return }
        let now = Date()
        let sourceName = storedCustomerLists[sourceIndex].name
        let targetName = storedCustomerLists[targetIndex].name

        for index in customers.indices where movedCustomerIds.contains(customers[index].id) {
            customers[index].customerListId = targetListId
            customers[index].updatedAt = now
        }
        for index in visitLogs.indices where visitLogs[index].customerListId == sourceListId || movedCustomerIds.contains(visitLogs[index].customerId) {
            visitLogs[index].customerListId = targetListId
        }
        for index in contactLogs.indices where contactLogs[index].customerListId == sourceListId || movedCustomerIds.contains(contactLogs[index].customerId) {
            contactLogs[index].customerListId = targetListId
        }
        for index in photoLogs.indices where photoLogs[index].customerListId == sourceListId || movedCustomerIds.contains(photoLogs[index].customerId) {
            photoLogs[index].customerListId = targetListId
        }
        for index in visitSchedules.indices where visitSchedules[index].customerListId == sourceListId {
            visitSchedules[index].customerListId = targetListId
            visitSchedules[index].updatedAt = now
        }
        for index in visitScheduleItems.indices where visitScheduleItems[index].customerListId == sourceListId || movedCustomerIds.contains(visitScheduleItems[index].customerId) {
            visitScheduleItems[index].customerListId = targetListId
        }
        for index in groupSmsCampaigns.indices where groupSmsCampaigns[index].customerListId == sourceListId {
            groupSmsCampaigns[index].customerListId = targetListId
            groupSmsCampaigns[index].updatedAt = now
        }
        for index in contactExportBatches.indices where contactExportBatches[index].customerListId == sourceListId {
            contactExportBatches[index].customerListId = targetListId
            contactExportBatches[index].updatedAt = now
        }
        for index in stageChangeLogs.indices where stageChangeLogs[index].customerListId == sourceListId || movedCustomerIds.contains(stageChangeLogs[index].customerId) {
            stageChangeLogs[index].customerListId = targetListId
        }
        for index in activityEvents.indices where activityEvents[index].customerListId == sourceListId && activityEvents[index].customerId.map(movedCustomerIds.contains) ?? false {
            activityEvents[index].customerListId = targetListId
        }
        for index in managementPeriods.indices {
            if managementPeriods[index].customerListIds.contains(sourceListId) {
                managementPeriods[index].customerListIds.removeAll { $0 == sourceListId }
                if !managementPeriods[index].customerListIds.contains(targetListId) {
                    managementPeriods[index].customerListIds.append(targetListId)
                }
                managementPeriods[index].updatedAt = now
            }
        }

        storedCustomerLists[sourceIndex].updatedAt = now
        storedCustomerLists[targetIndex].updatedAt = now
        recordActivity(
            kind: .customersMoved,
            occurredAt: now,
            customerListId: targetListId,
            title: "고객 일괄 이동",
            detail: "\(sourceName) -> \(targetName), \(movedCustomerIds.count)명"
        )
        selectedListId = targetListId
        actionMessage = "\(movedCustomerIds.count)명을 \(targetName)(으)로 이동했습니다."
        persist()
    }

    public func permanentlyDeleteCustomerList(id: String) {
        guard let list = storedCustomerLists.first(where: { $0.id == id }) else { return }
        let now = Date()
        let customerIds = Set(customers.filter { $0.customerListId == id }.map(\.id))
        let scheduleIds = Set(visitSchedules.filter { $0.customerListId == id }.map(\.id))
        let removedPhotoLogs = photoLogs.filter { $0.customerListId == id || customerIds.contains($0.customerId) }
        let removedVisitLogs = visitLogs.filter { $0.customerListId == id || customerIds.contains($0.customerId) }

        for log in removedPhotoLogs {
            try? fileStore.deleteAssetIfPresent(fileName: log.fileName)
            try? fileStore.deleteAssetIfPresent(fileName: log.thumbnailFileName)
        }
        for log in removedVisitLogs {
            if let fileName = log.mapSnapshotFileName { try? fileStore.deleteAssetIfPresent(fileName: fileName) }
            if let fileName = log.audioFileName { try? fileStore.deleteAssetIfPresent(fileName: fileName) }
        }

        storedCustomerLists.removeAll { $0.id == id }
        customers.removeAll { $0.customerListId == id }
        visitLogs.removeAll { $0.customerListId == id || customerIds.contains($0.customerId) }
        contactLogs.removeAll { $0.customerListId == id || customerIds.contains($0.customerId) }
        photoLogs.removeAll { $0.customerListId == id || customerIds.contains($0.customerId) }
        visitSchedules.removeAll { $0.customerListId == id }
        visitScheduleItems.removeAll { $0.customerListId == id || scheduleIds.contains($0.scheduleId) || customerIds.contains($0.customerId) }
        groupSmsCampaigns.removeAll { campaign in
            campaign.customerListId == id || campaign.recipients.contains { $0.customerId.map(customerIds.contains) ?? false }
        }
        contactExportBatches.removeAll { $0.customerListId == id }
        stageChangeLogs.removeAll { $0.customerListId == id || customerIds.contains($0.customerId) }
        activityEvents.removeAll { event in
            event.customerListId == id || event.customerId.map(customerIds.contains) ?? false
        }
        for index in managementPeriods.indices {
            managementPeriods[index].customerListIds.removeAll { $0 == id }
            managementPeriods[index].customerIds.removeAll { customerIds.contains($0) }
            managementPeriods[index].updatedAt = now
        }
        deletionTombstones.removeAll { $0.kind == .customerList && $0.recordId == id }
        deletionTombstones.append(DeletedRecordTombstone(kind: .customerList, recordId: id, deletedAt: now))
        recordActivity(
            kind: .listDeleted,
            occurredAt: now,
            title: "고객리스트 영구삭제",
            detail: "\(list.name), 고객 \(customerIds.count)명"
        )
        resolveSelectedList(excluding: id)
        actionMessage = "\(list.name)을 영구삭제했습니다. 기기 연락처는 삭제하지 않았습니다."
        persist()
    }

    @discardableResult
    public func createManagementPeriod(
        name: String,
        startDate: Date,
        endDate: Date,
        customerListIds: [String],
        customerIds: [String] = [],
        colorHex: String = "2563EB"
    ) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let validListIds = Array(Set(customerListIds.filter { listId in
            storedCustomerLists.contains { $0.id == listId }
        })).sorted()
        guard !trimmed.isEmpty, !validListIds.isEmpty else { return nil }
        let calendar = Calendar.current
        let resolvedStart = calendar.startOfDay(for: min(startDate, endDate))
        let resolvedEnd = calendar.startOfDay(for: max(startDate, endDate))
        let validCustomerIds = Array(Set(customerIds.filter { customerId in
            customers.contains { customer in
                customer.id == customerId && validListIds.contains(customer.customerListId)
            }
        })).sorted()
        let now = Date()
        let period = ManagementPeriod(
            id: UUID().uuidString,
            name: trimmed,
            startDate: resolvedStart,
            endDate: resolvedEnd,
            customerListIds: validListIds,
            customerIds: validCustomerIds,
            colorHex: colorHex,
            createdAt: now,
            updatedAt: now
        )
        managementPeriods.insert(period, at: 0)
        recordActivity(
            kind: .managementPeriodCreated,
            occurredAt: now,
            title: "관리 기간 생성",
            detail: trimmed
        )
        actionMessage = "\(trimmed) 관리 기간을 만들었습니다."
        persist()
        return period.id
    }

    public func updateManagementPeriod(
        id: String,
        name: String,
        startDate: Date,
        endDate: Date,
        customerListIds: [String],
        customerIds: [String],
        colorHex: String,
        summaryNote: String
    ) {
        guard let index = managementPeriods.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let calendar = Calendar.current
        let resolvedStart = calendar.startOfDay(for: min(startDate, endDate))
        let resolvedEnd = calendar.startOfDay(for: max(startDate, endDate))
        let validListIds = Array(Set(customerListIds.filter { listId in
            storedCustomerLists.contains { $0.id == listId }
        })).sorted()
        guard !validListIds.isEmpty else { return }
        let validCustomerIds = Array(Set(customerIds.filter { customerId in
            customers.contains { customer in
                customer.id == customerId && validListIds.contains(customer.customerListId)
            }
        })).sorted()
        let now = Date()
        managementPeriods[index].name = trimmed
        managementPeriods[index].startDate = resolvedStart
        managementPeriods[index].endDate = resolvedEnd
        managementPeriods[index].customerListIds = validListIds
        managementPeriods[index].customerIds = validCustomerIds
        managementPeriods[index].colorHex = colorHex
        managementPeriods[index].summaryNote = summaryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        managementPeriods[index].updatedAt = now
        recordActivity(
            kind: .managementPeriodUpdated,
            occurredAt: now,
            title: "관리 기간 수정",
            detail: trimmed
        )
        persist()
    }

    public func closeManagementPeriod(id: String, summaryNote: String) {
        guard let index = managementPeriods.firstIndex(where: { $0.id == id && $0.state == .active }) else { return }
        let now = Date()
        managementPeriods[index].state = .closed
        managementPeriods[index].summaryNote = summaryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        managementPeriods[index].closedAt = now
        managementPeriods[index].updatedAt = now
        recordActivity(
            kind: .managementPeriodClosed,
            occurredAt: now,
            title: "관리 기간 마감",
            detail: managementPeriods[index].name
        )
        actionMessage = "\(managementPeriods[index].name)을 마감했습니다."
        persist()
    }

    public func archiveManagementPeriod(id: String) {
        guard let index = managementPeriods.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        managementPeriods[index].state = .archived
        managementPeriods[index].updatedAt = now
        recordActivity(
            kind: .managementPeriodArchived,
            occurredAt: now,
            title: "관리 기간 보관",
            detail: managementPeriods[index].name
        )
        persist()
    }

    public func activityReport(
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        listIds: Set<String>? = nil,
        managementPeriodId: String? = nil
    ) -> [CustomerActivityEvent] {
        let period = managementPeriodId.flatMap { id in managementPeriods.first { $0.id == id } }
        let calendar = Calendar.current
        let effectiveStart = period?.startDate ?? startDate
        let effectiveEnd = period?.endDate ?? endDate
        let endBoundary = effectiveEnd.flatMap { date in
            calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: date))
        }
        let effectiveListIds = period.map { Set($0.customerListIds) } ?? listIds
        let effectiveCustomerIds = period.flatMap { $0.customerIds.isEmpty ? nil : Set($0.customerIds) }

        return combinedActivityEvents()
            .filter { event in
                if let effectiveStart, event.occurredAt < calendar.startOfDay(for: effectiveStart) { return false }
                if let endBoundary, event.occurredAt > endBoundary { return false }
                if let effectiveListIds,
                   !(event.customerListId.map(effectiveListIds.contains) ?? false) { return false }
                if let effectiveCustomerIds,
                   !(event.customerId.map(effectiveCustomerIds.contains) ?? false) { return false }
                return true
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    public func activitySummary(for events: [CustomerActivityEvent]) -> CustomerActivitySummary {
        let customerIds = Set(events.compactMap(\.customerId))
        return CustomerActivitySummary(
            totalCount: events.count,
            callCount: events.count { $0.kind == .call },
            messageCount: events.count { $0.kind == .message },
            visitCount: events.count { $0.kind == .visit },
            memoCount: events.count { [.textMemo, .photoMemo, .voiceMemo].contains($0.kind) },
            customerCount: customerIds.count
        )
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
        storedCustomerLists.insert(list, at: 0)
        selectedListId = list.id
        recordActivity(
            kind: .listCreated,
            occurredAt: now,
            customerListId: list.id,
            title: "고객리스트 생성",
            detail: resolvedListName
        )
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
        storedCustomerLists.insert(list, at: 0)
        customers.append(contentsOf: importedCustomers)
        selectedListId = list.id
        importMessage = "\(importedCustomers.count)명의 고객을 가져왔습니다."
        recordActivity(
            kind: .listCreated,
            occurredAt: now,
            customerListId: list.id,
            title: "고객리스트 생성",
            detail: resolvedListName
        )
        recordActivity(
            kind: .customersImported,
            occurredAt: now,
            customerListId: list.id,
            title: "고객 가져오기",
            detail: "\(sourceFileName), \(importedCustomers.count)명"
        )
        persist()
        Task {
            await geocodeVisibleCustomers()
        }
    }

    public func appendParsedCSV(_ parsed: ParsedCSV, to listId: String, sourceFileName: String = "import.csv") {
        guard let listIndex = storedCustomerLists.firstIndex(where: { $0.id == listId && $0.archivedAt == nil }) else {
            importMessage = "추가할 고객리스트를 찾지 못했습니다."
            return
        }

        let now = Date()
        let importedCustomers = customersFromCSV(parsed, customerListId: listId, now: now)
        customers.append(contentsOf: importedCustomers)
        storedCustomerLists[listIndex].updatedAt = now
        selectedListId = listId
        importMessage = "\(storedCustomerLists[listIndex].name)에 \(importedCustomers.count)명의 고객을 추가했습니다."
        recordActivity(
            kind: .customersImported,
            occurredAt: now,
            customerListId: listId,
            title: "고객 추가 가져오기",
            detail: "\(sourceFileName), \(importedCustomers.count)명"
        )
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
        storedCustomerLists.insert(list, at: 0)
        customers.append(contentsOf: importedCustomers.customers)
        selectedListId = list.id
        importMessage = "\(importedCustomers.customers.count)명의 연락처를 가져왔습니다." + (importedCustomers.skippedCount > 0 ? " 중복 \(importedCustomers.skippedCount)명은 건너뛰었습니다." : "")
        recordActivity(
            kind: .listCreated,
            occurredAt: now,
            customerListId: list.id,
            title: "고객리스트 생성",
            detail: resolvedListName
        )
        recordActivity(
            kind: .customersImported,
            occurredAt: now,
            customerListId: list.id,
            title: "연락처에서 고객 가져오기",
            detail: "\(importedCustomers.customers.count)명, 중복 제외 \(importedCustomers.skippedCount)명"
        )
        persist()
        Task {
            await geocodeVisibleCustomers()
        }
    }

    func appendContactCustomers(_ contacts: [ContactImportCustomer], to listId: String, sourceFileName: String = "contacts", skipDuplicatePhones: Bool = true) {
        guard let listIndex = storedCustomerLists.firstIndex(where: { $0.id == listId && $0.archivedAt == nil }) else {
            importMessage = "추가할 고객리스트를 찾지 못했습니다."
            return
        }

        let now = Date()
        let importedCustomers = makeCustomers(from: contacts, customerListId: listId, now: now, skipDuplicatePhones: skipDuplicatePhones)
        customers.append(contentsOf: importedCustomers.customers)
        storedCustomerLists[listIndex].updatedAt = now
        selectedListId = listId
        importMessage = "\(storedCustomerLists[listIndex].name)에 \(importedCustomers.customers.count)명의 연락처를 추가했습니다." + (importedCustomers.skippedCount > 0 ? " 중복 \(importedCustomers.skippedCount)명은 건너뛰었습니다." : "")
        recordActivity(
            kind: .customersImported,
            occurredAt: now,
            customerListId: listId,
            title: "연락처에서 고객 추가",
            detail: "\(importedCustomers.customers.count)명, 중복 제외 \(importedCustomers.skippedCount)명"
        )
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
        let customer = Customer(
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
        )
        customers.insert(customer, at: 0)
        selectedListId = listId
        recordActivity(
            kind: .customerCreated,
            occurredAt: now,
            customerListId: listId,
            customerId: customer.id,
            title: "고객 추가",
            detail: customer.name
        )
        persist()
        Task {
            await geocodeCustomerIfNeeded(id: customer.id)
        }
    }

    public func updateCustomer(
        _ customer: Customer,
        name: String,
        phoneNumber: String,
        address: String,
        birthDate: String,
        notes: String,
        additionalAddresses: [CustomerAddress]? = nil,
        customFields: [CustomerCustomField]? = nil
    ) {
        guard let index = customers.firstIndex(where: { $0.id == customer.id }) else { return }
        let resolvedBirthDate = birthDate.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var changedFields: [String] = []
        if customers[index].name != name { changedFields.append("이름") }
        if customers[index].phoneNumber != phoneNumber { changedFields.append("연락처") }
        if customers[index].address != address { changedFields.append("주소") }
        if customers[index].birthDate != resolvedBirthDate { changedFields.append("생년월일") }
        if customers[index].notes != notes { changedFields.append("메모") }
        let resolvedAdditionalAddresses = additionalAddresses ?? customers[index].additionalAddresses ?? []
        let resolvedCustomFields = customFields ?? customers[index].customFields ?? []
        if (customers[index].additionalAddresses ?? []) != resolvedAdditionalAddresses { changedFields.append("추가 주소") }
        if (customers[index].customFields ?? []) != resolvedCustomFields { changedFields.append("사용자 항목") }
        guard !changedFields.isEmpty else { return }
        let now = Date()
        customers[index].name = name
        customers[index].phoneNumber = phoneNumber
        customers[index].address = address
        customers[index].birthDate = resolvedBirthDate
        customers[index].notes = notes
        customers[index].additionalAddresses = resolvedAdditionalAddresses.isEmpty ? nil : resolvedAdditionalAddresses
        customers[index].customFields = resolvedCustomFields.isEmpty ? nil : resolvedCustomFields
        customers[index].region = extractRegion(address)
        if customer.address != address {
            customers[index].latitude = nil
            customers[index].longitude = nil
            customers[index].coordinateSource = nil
            customers[index].geocodedAt = nil
            customers[index].geocodeQuery = nil
        }
        customers[index].updatedAt = now
        recordActivity(
            kind: .customerUpdated,
            occurredAt: now,
            customerListId: customers[index].customerListId,
            customerId: customer.id,
            title: "고객 정보 수정",
            detail: changedFields.joined(separator: ", ")
        )
        persist()
        Task {
            await geocodeCustomerIfNeeded(id: customer.id)
        }
    }

    public func permanentlyDeleteCustomer(id: String) {
        guard let customer = customers.first(where: { $0.id == id }) else { return }
        let now = Date()
        let removedPhotoLogs = photoLogs.filter { $0.customerId == id }
        let removedVisitLogs = visitLogs.filter { $0.customerId == id }

        for log in removedPhotoLogs {
            try? fileStore.deleteAssetIfPresent(fileName: log.fileName)
            try? fileStore.deleteAssetIfPresent(fileName: log.thumbnailFileName)
        }
        for log in removedVisitLogs {
            if let fileName = log.mapSnapshotFileName { try? fileStore.deleteAssetIfPresent(fileName: fileName) }
            if let fileName = log.audioFileName { try? fileStore.deleteAssetIfPresent(fileName: fileName) }
        }

        customers.removeAll { $0.id == id }
        visitLogs.removeAll { $0.customerId == id }
        contactLogs.removeAll { $0.customerId == id }
        photoLogs.removeAll { $0.customerId == id }
        visitScheduleItems.removeAll { $0.customerId == id }
        stageChangeLogs.removeAll { $0.customerId == id }
        activityEvents.removeAll { $0.customerId == id }
        for index in managementPeriods.indices {
            managementPeriods[index].customerIds.removeAll { $0 == id }
            managementPeriods[index].updatedAt = now
        }
        for campaignIndex in groupSmsCampaigns.indices {
            var changed = false
            for recipientIndex in groupSmsCampaigns[campaignIndex].recipients.indices where groupSmsCampaigns[campaignIndex].recipients[recipientIndex].customerId == id {
                groupSmsCampaigns[campaignIndex].recipients[recipientIndex].customerId = nil
                changed = true
            }
            if changed { groupSmsCampaigns[campaignIndex].updatedAt = now }
        }
        for batchIndex in contactExportBatches.indices {
            let previousCount = contactExportBatches[batchIndex].records.count
            contactExportBatches[batchIndex].records.removeAll { $0.customerId == id }
            if contactExportBatches[batchIndex].records.count != previousCount {
                contactExportBatches[batchIndex].updatedAt = now
            }
        }
        deletionTombstones.removeAll { $0.kind == .customer && $0.recordId == id }
        deletionTombstones.append(DeletedRecordTombstone(kind: .customer, recordId: id, deletedAt: now))
        recordActivity(
            kind: .customerUpdated,
            occurredAt: now,
            customerListId: customer.customerListId,
            title: "고객 영구삭제",
            detail: customer.name
        )
        actionMessage = "\(customer.name.isEmpty ? "고객" : customer.name)을 영구삭제했습니다. iPhone 연락처는 삭제하지 않았습니다."
        persist()
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
        let previousStatusId = customers[index].dashboardStatusId ?? dashboardStatuses.first?.id
        guard previousStatusId != statusId else { return }
        let now = Date()
        customers[index].dashboardStatusId = statusId
        customers[index].updatedAt = now
        stageChangeLogs.insert(
            CustomerStageChangeLog(
                id: UUID().uuidString,
                customerListId: customers[index].customerListId,
                customerId: customerId,
                previousStageId: previousStatusId,
                nextStageId: statusId,
                changedAt: now
            ),
            at: 0
        )
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
        let now = Date()
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
        recordActivity(
            kind: .scheduleAdded,
            occurredAt: now,
            customerListId: customer.customerListId,
            customerId: customer.id,
            title: "오늘 스케줄 추가",
            detail: customer.name
        )
        persist()
    }

    public func removeFromTodaySchedule(_ customer: Customer) {
        guard let schedule = todaySchedule else { return }
        guard visitScheduleItems.contains(where: { $0.scheduleId == schedule.id && $0.customerId == customer.id }) else { return }
        let now = Date()
        visitScheduleItems.removeAll { $0.scheduleId == schedule.id && $0.customerId == customer.id }
        recordActivity(
            kind: .scheduleRemoved,
            occurredAt: now,
            customerListId: customer.customerListId,
            customerId: customer.id,
            title: "오늘 스케줄 해제",
            detail: customer.name
        )
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
            remoteDriveLists = backup.snapshot.customerLists.filter { $0.archivedAt == nil }
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
        storedCustomerLists = snapshot.customerLists
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
        managementPeriods = snapshot.managementPeriods
        activityEvents = snapshot.activityEvents
        stageChangeLogs = snapshot.stageChangeLogs
        deletionTombstones = snapshot.deletionTombstones
        customers = Self.repairingDashboardAssignments(customers, statuses: dashboardStatuses)
        selectedListId = snapshot.selectedListId.flatMap { selectedId in
            customerLists.contains { $0.id == selectedId } ? selectedId : nil
        } ?? customerLists.first?.id
        applyDeletionTombstonesToLoadedData()
        resolveSelectedList()
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

        storedCustomerLists.removeAll { selectedListIds.contains($0.id) }
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
        managementPeriods.removeAll { period in
            period.customerListIds.contains { selectedListIds.contains($0) }
        }
        activityEvents.removeAll { event in
            event.customerListId.map { selectedListIds.contains($0) } ?? false ||
            event.customerId.map { targetCustomerIds.contains($0) } ?? false
        }
        stageChangeLogs.removeAll { selectedListIds.contains($0.customerListId) || targetCustomerIds.contains($0.customerId) }

        let restoredLists = remoteSnapshot.customerLists.filter { selectedListIds.contains($0.id) }
        let restoredCustomers = remoteSnapshot.customers.filter { selectedListIds.contains($0.customerListId) }
        let restoredCustomerIds = Set(restoredCustomers.map(\.id))
        let restoredSchedules = remoteSnapshot.visitSchedules.filter { selectedListIds.contains($0.customerListId) }
        let restoredScheduleIds = Set(restoredSchedules.map(\.id))
        let restoredPhotoLogs = remoteSnapshot.photoLogs.filter { selectedListIds.contains($0.customerListId) && restoredCustomerIds.contains($0.customerId) }

        storedCustomerLists.append(contentsOf: restoredLists)
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
        managementPeriods.append(contentsOf: remoteSnapshot.managementPeriods.filter { period in
            period.customerListIds.contains { selectedListIds.contains($0) }
        })
        activityEvents.append(contentsOf: remoteSnapshot.activityEvents.filter { event in
            event.customerListId.map { selectedListIds.contains($0) } ?? false ||
            event.customerId.map { restoredCustomerIds.contains($0) } ?? false
        })
        stageChangeLogs.append(contentsOf: remoteSnapshot.stageChangeLogs.filter {
            selectedListIds.contains($0.customerListId) && restoredCustomerIds.contains($0.customerId)
        })
        deletionTombstones = mergeById(deletionTombstones, remoteSnapshot.deletionTombstones) { $0.deletedAt < $1.deletedAt }
        messageTemplates = mergeById(messageTemplates, remoteSnapshot.messageTemplates) { $0.updatedAt < $1.updatedAt }
        if !remoteSnapshot.dashboardStatuses.isEmpty {
            dashboardStatuses = Self.migratingDefaultDashboardColors(remoteSnapshot.dashboardStatuses)
        }
        dashboardSettings = remoteSnapshot.dashboardSettings
        dashboardSettings.statusCount = dashboardStatuses.count
        customers = Self.repairingDashboardAssignments(customers, statuses: dashboardStatuses)
        selectedListId = restoredLists.first?.id ?? selectedListId ?? customerLists.first?.id
        applyDeletionTombstonesToLoadedData()
        resolveSelectedList()

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
            storedCustomerLists = seed.lists
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
            managementPeriods = []
            activityEvents = []
            stageChangeLogs = []
            deletionTombstones = []
            selectedListId = seed.lists.first?.id
        } else {
            storedCustomerLists = []
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
            managementPeriods = []
            activityEvents = []
            stageChangeLogs = []
            deletionTombstones = []
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

    private func resolveSelectedList(excluding excludedId: String? = nil) {
        if let selectedListId,
           selectedListId != excludedId,
           customerLists.contains(where: { $0.id == selectedListId }) {
            return
        }
        selectedListId = customerLists.first { $0.id != excludedId }?.id
    }

    private func applyDeletionTombstonesToLoadedData() {
        let deletedListIds = Set(deletionTombstones.filter { $0.kind == .customerList }.map(\.recordId))
        let deletedCustomerIds = Set(deletionTombstones.filter { $0.kind == .customer }.map(\.recordId))
        let customerIdsFromDeletedLists = Set(customers.filter { deletedListIds.contains($0.customerListId) }.map(\.id))
        let allDeletedCustomerIds = deletedCustomerIds.union(customerIdsFromDeletedLists)

        storedCustomerLists.removeAll { deletedListIds.contains($0.id) }
        customers.removeAll { deletedListIds.contains($0.customerListId) || allDeletedCustomerIds.contains($0.id) }
        visitLogs.removeAll { deletedListIds.contains($0.customerListId) || allDeletedCustomerIds.contains($0.customerId) }
        contactLogs.removeAll { deletedListIds.contains($0.customerListId) || allDeletedCustomerIds.contains($0.customerId) }
        photoLogs.removeAll { deletedListIds.contains($0.customerListId) || allDeletedCustomerIds.contains($0.customerId) }
        visitSchedules.removeAll { deletedListIds.contains($0.customerListId) }
        visitScheduleItems.removeAll { deletedListIds.contains($0.customerListId) || allDeletedCustomerIds.contains($0.customerId) }
        stageChangeLogs.removeAll { deletedListIds.contains($0.customerListId) || allDeletedCustomerIds.contains($0.customerId) }
        activityEvents.removeAll { event in
            event.customerListId.map(deletedListIds.contains) ?? false ||
            event.customerId.map(allDeletedCustomerIds.contains) ?? false
        }
        contactExportBatches.removeAll { deletedListIds.contains($0.customerListId) }
        for batchIndex in contactExportBatches.indices {
            contactExportBatches[batchIndex].records.removeAll { allDeletedCustomerIds.contains($0.customerId) }
        }
        for campaignIndex in groupSmsCampaigns.indices {
            if let listId = groupSmsCampaigns[campaignIndex].customerListId, deletedListIds.contains(listId) {
                groupSmsCampaigns[campaignIndex].customerListId = nil
            }
            for recipientIndex in groupSmsCampaigns[campaignIndex].recipients.indices where groupSmsCampaigns[campaignIndex].recipients[recipientIndex].customerId.map(allDeletedCustomerIds.contains) ?? false {
                groupSmsCampaigns[campaignIndex].recipients[recipientIndex].customerId = nil
            }
        }
        for periodIndex in managementPeriods.indices {
            managementPeriods[periodIndex].customerListIds.removeAll { deletedListIds.contains($0) }
            managementPeriods[periodIndex].customerIds.removeAll { allDeletedCustomerIds.contains($0) }
        }
        managementPeriods.removeAll { $0.customerListIds.isEmpty }
    }

    private func recordActivity(
        kind: CustomerActivityKind,
        occurredAt: Date,
        customerListId: String? = nil,
        customerId: String? = nil,
        title: String,
        detail: String = ""
    ) {
        activityEvents.insert(
            CustomerActivityEvent(
                id: UUID().uuidString,
                kind: kind,
                occurredAt: occurredAt,
                customerListId: customerListId,
                customerId: customerId,
                title: title,
                detail: detail,
                createdAt: Date()
            ),
            at: 0
        )
    }

    private func combinedActivityEvents() -> [CustomerActivityEvent] {
        let customerNames = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0.name) })
        let contactEvents = contactLogs.map { log in
            let kind: CustomerActivityKind
            let title: String
            switch log.type {
            case .call:
                kind = .call
                title = "전화"
            case .manualSms, .templateSms, .groupSms:
                kind = .message
                title = "문자"
            case .note:
                kind = .textMemo
                title = "텍스트 메모"
            case .statusComplete, .statusReopen:
                kind = .customerUpdated
                title = log.type == .statusComplete ? "완료 처리" : "완료 취소"
            }
            return CustomerActivityEvent(
                id: "contact:\(log.id)",
                kind: kind,
                occurredAt: log.createdAt,
                customerListId: log.customerListId,
                customerId: log.customerId,
                title: title,
                detail: log.messageBody ?? customerNames[log.customerId] ?? "",
                source: .contactLog,
                sourceRecordId: log.id,
                createdAt: log.createdAt
            )
        }
        let visitEvents = visitLogs.map { log in
            let kind: CustomerActivityKind
            let title: String
            switch log.kind ?? .completed {
            case .completed, .quickLocation:
                kind = .visit
                title = "방문"
            case .textMemo:
                kind = .textMemo
                title = "텍스트 메모"
            case .photoMemo:
                kind = .photoMemo
                title = "사진 메모"
            case .voiceMemo:
                kind = .voiceMemo
                title = "음성 메모"
            }
            return CustomerActivityEvent(
                id: "visit:\(log.id)",
                kind: kind,
                occurredAt: log.visitedAt,
                customerListId: log.customerListId,
                customerId: log.customerId,
                title: title,
                detail: log.memo ?? log.locationAddress ?? customerNames[log.customerId] ?? "",
                source: .visitLog,
                sourceRecordId: log.id,
                createdAt: log.createdAt
            )
        }
        let photoEvents = photoLogs.map { log in
            CustomerActivityEvent(
                id: "photo:\(log.id)",
                kind: .photoMemo,
                occurredAt: log.createdAt,
                customerListId: log.customerListId,
                customerId: log.customerId,
                title: "사진 메모",
                detail: log.caption ?? customerNames[log.customerId] ?? "",
                source: .photoLog,
                sourceRecordId: log.id,
                createdAt: log.createdAt
            )
        }
        let stageEvents = stageChangeLogs.map { log in
            let previousName = log.previousStageId.flatMap { id in dashboardStatuses.first { $0.id == id }?.name }
            let nextName = dashboardStatuses.first { $0.id == log.nextStageId }?.name ?? log.nextStageId
            return CustomerActivityEvent(
                id: "stage:\(log.id)",
                kind: .dashboardStageChanged,
                occurredAt: log.changedAt,
                customerListId: log.customerListId,
                customerId: log.customerId,
                title: "진행 상태 변경",
                detail: [previousName, nextName].compactMap { $0 }.joined(separator: " -> "),
                source: .stageChangeLog,
                sourceRecordId: log.id,
                createdAt: log.changedAt
            )
        }
        return activityEvents + contactEvents + visitEvents + photoEvents + stageEvents
    }

    private func snapshot(listIds: Set<String>? = nil) -> NativeAppSnapshot {
        let filteredLists = storedCustomerLists.filter { listIds?.contains($0.id) ?? true }
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
            managementPeriods: managementPeriods.filter { period in
                listIds == nil || period.customerListIds.contains { filteredListIds.contains($0) }
            },
            activityEvents: activityEvents.filter { event in
                listIds == nil ||
                event.customerListId.map { filteredListIds.contains($0) } ?? false ||
                event.customerId.map { filteredCustomerIds.contains($0) } ?? false
            },
            stageChangeLogs: stageChangeLogs.filter {
                listIds == nil || (filteredListIds.contains($0.customerListId) && filteredCustomerIds.contains($0.customerId))
            },
            deletionTombstones: deletionTombstones,
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
        let mergedTombstones = mergeById(remote.snapshot.deletionTombstones, local.snapshot.deletionTombstones) { $0.deletedAt < $1.deletedAt }
        let deletedListIds = Set(mergedTombstones.filter { $0.kind == .customerList }.map(\.recordId))
        let deletedCustomerIds = Set(mergedTombstones.filter { $0.kind == .customer }.map(\.recordId))
        let mergedLists = mergeById(remote.snapshot.customerLists, local.snapshot.customerLists) { $0.updatedAt < $1.updatedAt }
            .filter { !deletedListIds.contains($0.id) }
        let validListIds = Set(mergedLists.map(\.id))
        let mergedCustomers = mergeById(remote.snapshot.customers, local.snapshot.customers) { $0.updatedAt < $1.updatedAt }
            .filter { validListIds.contains($0.customerListId) && !deletedCustomerIds.contains($0.id) }
        let validCustomerIds = Set(mergedCustomers.map(\.id))
        let mergedVisitLogs = mergeById(remote.snapshot.visitLogs, local.snapshot.visitLogs) { $0.createdAt < $1.createdAt }
            .filter { validListIds.contains($0.customerListId) && validCustomerIds.contains($0.customerId) }
        let mergedContactLogs = mergeById(remote.snapshot.contactLogs, local.snapshot.contactLogs) { $0.createdAt < $1.createdAt }
            .filter { validListIds.contains($0.customerListId) && validCustomerIds.contains($0.customerId) }
        let mergedPhotoLogs = mergeById(remote.snapshot.photoLogs, local.snapshot.photoLogs) { $0.createdAt < $1.createdAt }
            .filter { validListIds.contains($0.customerListId) && validCustomerIds.contains($0.customerId) }
        let mergedSchedules = mergeById(remote.snapshot.visitSchedules, local.snapshot.visitSchedules) { $0.updatedAt < $1.updatedAt }
            .filter { validListIds.contains($0.customerListId) }
        let validScheduleIds = Set(mergedSchedules.map(\.id))
        let mergedScheduleItems = mergeById(remote.snapshot.visitScheduleItems, local.snapshot.visitScheduleItems) { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .filter {
                validListIds.contains($0.customerListId) &&
                validScheduleIds.contains($0.scheduleId) &&
                validCustomerIds.contains($0.customerId)
            }
        let mergedTemplates = mergeById(remote.snapshot.messageTemplates, local.snapshot.messageTemplates) { $0.updatedAt < $1.updatedAt }
        let mergedGroupSmsCampaigns = mergeById(remote.snapshot.groupSmsCampaigns, local.snapshot.groupSmsCampaigns) { $0.updatedAt < $1.updatedAt }
            .filter { campaign in
                if let listId = campaign.customerListId, deletedListIds.contains(listId) { return false }
                return !campaign.recipients.contains { recipient in
                    recipient.customerId.map { !validCustomerIds.contains($0) } ?? false
                }
            }
        let mergedContactExportBatches = mergeById(remote.snapshot.contactExportBatches, local.snapshot.contactExportBatches) { $0.updatedAt < $1.updatedAt }
            .filter { validListIds.contains($0.customerListId) }
        let mergedPeriods = mergeById(remote.snapshot.managementPeriods, local.snapshot.managementPeriods) { $0.updatedAt < $1.updatedAt }
            .compactMap { period -> ManagementPeriod? in
                var resolved = period
                resolved.customerListIds.removeAll { !validListIds.contains($0) }
                resolved.customerIds.removeAll { !validCustomerIds.contains($0) }
                return resolved.customerListIds.isEmpty ? nil : resolved
            }
        let mergedActivityEvents = mergeById(remote.snapshot.activityEvents, local.snapshot.activityEvents) { $0.createdAt < $1.createdAt }
            .filter { event in
                if let listId = event.customerListId, !validListIds.contains(listId) { return false }
                if let customerId = event.customerId, !validCustomerIds.contains(customerId) { return false }
                return true
            }
        let mergedStageChangeLogs = mergeById(remote.snapshot.stageChangeLogs, local.snapshot.stageChangeLogs) { $0.changedAt < $1.changedAt }
            .filter { validListIds.contains($0.customerListId) && validCustomerIds.contains($0.customerId) }
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
            managementPeriods: mergedPeriods,
            activityEvents: mergedActivityEvents,
            stageChangeLogs: mergedStageChangeLogs,
            deletionTombstones: mergedTombstones,
            selectedListId: [local.snapshot.selectedListId, remote.snapshot.selectedListId]
                .compactMap { $0 }
                .first { validListIds.contains($0) }
                ?? mergedLists.first(where: { $0.archivedAt == nil })?.id,
            savedAt: Date()
        )
        let validPhotoFileNames = Set(mergedPhotoLogs.flatMap { [$0.fileName, $0.thumbnailFileName] })
        let mergedPhotos = mergeById(remote.photos, local.photos) { lhs, rhs in
            (lhs.imageDataBase64 == nil && rhs.imageDataBase64 != nil) || (lhs.thumbnailDataBase64 == nil && rhs.thumbnailDataBase64 != nil)
        }.filter { validPhotoFileNames.contains($0.fileName) || validPhotoFileNames.contains($0.thumbnailFileName) }
        let validVisitAssetFileNames = Set(mergedVisitLogs.flatMap { [$0.mapSnapshotFileName, $0.audioFileName].compactMap { $0 } })
        let mergedVisitAssets = mergeById(remote.visitAssets, local.visitAssets) { lhs, rhs in
            (lhs.mapSnapshotDataBase64 == nil && rhs.mapSnapshotDataBase64 != nil) || (lhs.audioDataBase64 == nil && rhs.audioDataBase64 != nil)
        }.filter { asset in
            validVisitAssetFileNames.contains(asset.mapSnapshotFileName ?? "") ||
            validVisitAssetFileNames.contains(asset.audioFileName ?? "")
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
