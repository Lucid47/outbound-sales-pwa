import Foundation

public enum CustomerStatus: String, Codable, Sendable {
    case open
    case done
    case hold
    case needsGeocode
}

public enum ScheduleItemStatus: String, Codable, Sendable {
    case pending
    case completed
    case skipped
    case hold
}

public enum ContactLogType: String, Codable, Sendable {
    case call
    case manualSms
    case templateSms
    case note
    case statusComplete
    case statusReopen
}

public enum ContactLogResult: String, Codable, Sendable {
    case opened
    case sentByUser
    case completed
    case reopened
    case saved
    case cancelled
    case unknown
}

public enum CoordinateSource: String, Codable, Sendable {
    case sample
    case csv
    case geocoded
}

public struct CustomerList: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var companyName: String
    public var sourceFileName: String
    public var importedAt: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, name: String, companyName: String, sourceFileName: String, importedAt: Date, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.companyName = companyName
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Customer: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var customerListId: String
    public var name: String
    public var phoneNumber: String
    public var address: String
    public var birthDate: String?
    public var notes: String
    public var latitude: Double?
    public var longitude: Double?
    public var coordinateSource: CoordinateSource?
    public var geocodedAt: Date?
    public var geocodeQuery: String?
    public var region: String?
    public var status: CustomerStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        customerListId: String,
        name: String,
        phoneNumber: String,
        address: String,
        birthDate: String? = nil,
        notes: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        coordinateSource: CoordinateSource? = nil,
        geocodedAt: Date? = nil,
        geocodeQuery: String? = nil,
        region: String? = nil,
        status: CustomerStatus = .open,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.customerListId = customerListId
        self.name = name
        self.phoneNumber = phoneNumber
        self.address = address
        self.birthDate = birthDate
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.coordinateSource = coordinateSource
        self.geocodedAt = geocodedAt
        self.geocodeQuery = geocodeQuery
        self.region = region
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VisitLog: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var customerListId: String
    public var customerId: String
    public var visitedAt: Date
    public var result: String
    public var memo: String?
    public var createdAt: Date
}

public struct ContactLog: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var customerListId: String
    public var customerId: String
    public var type: ContactLogType
    public var templateId: String?
    public var messageBody: String?
    public var result: ContactLogResult
    public var createdAt: Date
}

public struct VisitSchedule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var customerListId: String
    public var date: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
}

public struct VisitScheduleItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var scheduleId: String
    public var customerListId: String
    public var customerId: String
    public var orderIndex: Int
    public var status: ScheduleItemStatus
    public var completedAt: Date?
}

public struct MessageTemplate: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date
}

