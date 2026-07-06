import Foundation

public struct NativeAppSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var customerLists: [CustomerList]
    public var customers: [Customer]
    public var selectedListId: String?
    public var savedAt: Date

    public init(
        schemaVersion: Int = 1,
        customerLists: [CustomerList],
        customers: [Customer],
        selectedListId: String?,
        savedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.customerLists = customerLists
        self.customers = customers
        self.selectedListId = selectedListId
        self.savedAt = savedAt
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

    public static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("OutboundSales", isDirectory: true)
            .appendingPathComponent("native-data.json")
    }
}
