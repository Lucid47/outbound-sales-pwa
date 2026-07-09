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
    case groupSms
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

public enum ContactRegistrationStatus: String, Codable, Sendable {
    case registered
    case updated
    case skippedDuplicate
    case failed
}

public enum CustomerPhotoSource: String, Codable, Sendable {
    case camera
    case photoLibrary
    case file
}

public enum CustomerPhotoSyncStatus: String, Codable, Sendable {
    case localOnly
    case pendingUpload
    case synced
    case failed
}

public enum VisitLogKind: String, Codable, Sendable {
    case completed
    case quickLocation
    case textMemo
    case photoMemo
    case voiceMemo
}

public enum VoiceTranscriptionStatus: String, Codable, Sendable {
    case pending
    case transcribing
    case completed
    case failed
}

public struct VoiceTranscriptionSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var timestamp: TimeInterval
    public var duration: TimeInterval

    public init(id: String, text: String, timestamp: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
    }
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
    public var contactRegistrationStatus: ContactRegistrationStatus?
    public var contactIdentifier: String?
    public var contactRegisteredAt: Date?
    public var contactRegisteredName: String?
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
        contactRegistrationStatus: ContactRegistrationStatus? = nil,
        contactIdentifier: String? = nil,
        contactRegisteredAt: Date? = nil,
        contactRegisteredName: String? = nil,
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
        self.contactRegistrationStatus = contactRegistrationStatus
        self.contactIdentifier = contactIdentifier
        self.contactRegisteredAt = contactRegisteredAt
        self.contactRegisteredName = contactRegisteredName
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
    public var kind: VisitLogKind?
    public var locationAddress: String?
    public var mapSnapshotFileName: String?
    public var audioFileName: String?
    public var audioTranscript: String?
    public var audioDuration: TimeInterval?
    public var audioSegments: [VoiceTranscriptionSegment]?
    public var transcriptionStatus: VoiceTranscriptionStatus?
    public var createdAt: Date

    public init(
        id: String,
        customerListId: String,
        customerId: String,
        visitedAt: Date,
        result: String,
        memo: String? = nil,
        kind: VisitLogKind? = nil,
        locationAddress: String? = nil,
        mapSnapshotFileName: String? = nil,
        audioFileName: String? = nil,
        audioTranscript: String? = nil,
        audioDuration: TimeInterval? = nil,
        audioSegments: [VoiceTranscriptionSegment]? = nil,
        transcriptionStatus: VoiceTranscriptionStatus? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.customerListId = customerListId
        self.customerId = customerId
        self.visitedAt = visitedAt
        self.result = result
        self.memo = memo
        self.kind = kind
        self.locationAddress = locationAddress
        self.mapSnapshotFileName = mapSnapshotFileName
        self.audioFileName = audioFileName
        self.audioTranscript = audioTranscript
        self.audioDuration = audioDuration
        self.audioSegments = audioSegments
        self.transcriptionStatus = transcriptionStatus
        self.createdAt = createdAt
    }
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

    public init(id: String, customerListId: String, customerId: String, type: ContactLogType, templateId: String? = nil, messageBody: String? = nil, result: ContactLogResult, createdAt: Date) {
        self.id = id
        self.customerListId = customerListId
        self.customerId = customerId
        self.type = type
        self.templateId = templateId
        self.messageBody = messageBody
        self.result = result
        self.createdAt = createdAt
    }
}

public struct CustomerPhotoLog: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var customerListId: String
    public var customerId: String
    public var fileName: String
    public var thumbnailFileName: String
    public var source: CustomerPhotoSource
    public var caption: String?
    public var syncStatus: CustomerPhotoSyncStatus
    public var createdAt: Date

    public init(
        id: String,
        customerListId: String,
        customerId: String,
        fileName: String,
        thumbnailFileName: String,
        source: CustomerPhotoSource,
        caption: String? = nil,
        syncStatus: CustomerPhotoSyncStatus = .localOnly,
        createdAt: Date
    ) {
        self.id = id
        self.customerListId = customerListId
        self.customerId = customerId
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.source = source
        self.caption = caption
        self.syncStatus = syncStatus
        self.createdAt = createdAt
    }
}

public struct VisitSchedule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var customerListId: String
    public var date: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, customerListId: String, date: String, title: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.customerListId = customerListId
        self.date = date
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VisitScheduleItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var scheduleId: String
    public var customerListId: String
    public var customerId: String
    public var orderIndex: Int
    public var status: ScheduleItemStatus
    public var completedAt: Date?

    public init(id: String, scheduleId: String, customerListId: String, customerId: String, orderIndex: Int, status: ScheduleItemStatus, completedAt: Date? = nil) {
        self.id = id
        self.scheduleId = scheduleId
        self.customerListId = customerListId
        self.customerId = customerId
        self.orderIndex = orderIndex
        self.status = status
        self.completedAt = completedAt
    }
}

public struct MessageTemplate: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, title: String, body: String, isDefault: Bool = false, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
