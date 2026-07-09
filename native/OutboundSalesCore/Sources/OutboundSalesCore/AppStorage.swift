import Foundation

public struct NativeAppSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var customerLists: [CustomerList]
    public var customers: [Customer]
    public var visitLogs: [VisitLog]
    public var contactLogs: [ContactLog]
    public var photoLogs: [CustomerPhotoLog]
    public var visitSchedules: [VisitSchedule]
    public var visitScheduleItems: [VisitScheduleItem]
    public var messageTemplates: [MessageTemplate]
    public var groupSmsCampaigns: [GroupSmsCampaign]
    public var selectedListId: String?
    public var savedAt: Date

    public init(
        schemaVersion: Int = 1,
        customerLists: [CustomerList],
        customers: [Customer],
        visitLogs: [VisitLog] = [],
        contactLogs: [ContactLog] = [],
        photoLogs: [CustomerPhotoLog] = [],
        visitSchedules: [VisitSchedule] = [],
        visitScheduleItems: [VisitScheduleItem] = [],
        messageTemplates: [MessageTemplate] = [],
        groupSmsCampaigns: [GroupSmsCampaign] = [],
        selectedListId: String?,
        savedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.customerLists = customerLists
        self.customers = customers
        self.visitLogs = visitLogs
        self.contactLogs = contactLogs
        self.photoLogs = photoLogs
        self.visitSchedules = visitSchedules
        self.visitScheduleItems = visitScheduleItems
        self.messageTemplates = messageTemplates
        self.groupSmsCampaigns = groupSmsCampaigns
        self.selectedListId = selectedListId
        self.savedAt = savedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.customerLists = try container.decodeIfPresent([CustomerList].self, forKey: .customerLists) ?? []
        self.customers = try container.decodeIfPresent([Customer].self, forKey: .customers) ?? []
        self.visitLogs = try container.decodeIfPresent([VisitLog].self, forKey: .visitLogs) ?? []
        self.contactLogs = try container.decodeIfPresent([ContactLog].self, forKey: .contactLogs) ?? []
        self.photoLogs = try container.decodeIfPresent([CustomerPhotoLog].self, forKey: .photoLogs) ?? []
        self.visitSchedules = try container.decodeIfPresent([VisitSchedule].self, forKey: .visitSchedules) ?? []
        self.visitScheduleItems = try container.decodeIfPresent([VisitScheduleItem].self, forKey: .visitScheduleItems) ?? []
        self.messageTemplates = try container.decodeIfPresent([MessageTemplate].self, forKey: .messageTemplates) ?? []
        self.groupSmsCampaigns = try container.decodeIfPresent([GroupSmsCampaign].self, forKey: .groupSmsCampaigns) ?? []
        self.selectedListId = try container.decodeIfPresent(String.self, forKey: .selectedListId)
        self.savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
    }
}

public enum NativeAppStorageError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

public struct NativeAppFileStore: Sendable {
    public var fileURL: URL
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder

    public init(fileURL: URL = NativeAppFileStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> NativeAppSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let snapshot = try decoder.decode(NativeAppSnapshot.self, from: data)
        guard snapshot.schemaVersion == 1 else {
            throw NativeAppStorageError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        return snapshot
    }

    public func save(_ snapshot: NativeAppSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    public func deleteAllAppData() throws {
        let directory = fileURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    public func photoURL(fileName: String) -> URL {
        assetURL(fileName: fileName)
    }

    public func writePhotoData(_ data: Data, fileName: String) throws {
        try writeAssetData(data, fileName: fileName)
    }

    public func readPhotoData(fileName: String) throws -> Data {
        try readAssetData(fileName: fileName)
    }

    public func assetURL(fileName: String) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    public func writeAssetData(_ data: Data, fileName: String) throws {
        let url = assetURL(fileName: fileName)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    public func readAssetData(fileName: String) throws -> Data {
        try Data(contentsOf: assetURL(fileName: fileName))
    }

    public static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("OutboundSales", isDirectory: true)
            .appendingPathComponent("native-data.json")
    }
}
