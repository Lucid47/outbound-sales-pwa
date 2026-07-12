import Foundation

public enum GroupSmsCampaignStatus: String, Codable, Sendable {
    case draft
    case ready
    case shortcutOpened
    case requested
    case cancelled
    case shortcutFailed
    case unknown
}

public enum GroupSmsDelayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case fixed
    case random

    public var id: String { rawValue }
}

public struct GroupSmsDelaySettings: Codable, Equatable, Sendable {
    public var mode: GroupSmsDelayMode
    public var fixedDelaySeconds: Int
    public var minDelaySeconds: Int
    public var maxDelaySeconds: Int
    public var batchRestEnabled: Bool
    public var batchSize: Int
    public var batchMinRestSeconds: Int
    public var batchMaxRestSeconds: Int

    public init(
        mode: GroupSmsDelayMode = .off,
        fixedDelaySeconds: Int = 1,
        minDelaySeconds: Int = 1,
        maxDelaySeconds: Int = 3,
        batchRestEnabled: Bool = false,
        batchSize: Int = 50,
        batchMinRestSeconds: Int = 30,
        batchMaxRestSeconds: Int = 60
    ) {
        self.mode = mode
        self.fixedDelaySeconds = fixedDelaySeconds
        self.minDelaySeconds = minDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.batchRestEnabled = batchRestEnabled
        self.batchSize = batchSize
        self.batchMinRestSeconds = batchMinRestSeconds
        self.batchMaxRestSeconds = batchMaxRestSeconds
    }
}

public struct GroupSmsTransportConfiguration: Codable, Equatable, Sendable {
    public var shortcutName: String
    public var shortcutVersion: String
    public var callbackScheme: String
    public var successPath: String
    public var cancelPath: String
    public var errorPath: String

    public init(
        shortcutName: String,
        shortcutVersion: String,
        callbackScheme: String,
        successPath: String = "/group-sms/complete",
        cancelPath: String = "/group-sms/cancel",
        errorPath: String = "/group-sms/error"
    ) {
        self.shortcutName = shortcutName
        self.shortcutVersion = shortcutVersion
        self.callbackScheme = callbackScheme
        self.successPath = successPath
        self.cancelPath = cancelPath
        self.errorPath = errorPath
    }
}

public struct GroupMessageTarget: Codable, Equatable, Sendable {
    public var sourceRecordId: String?
    public var displayName: String
    public var phoneNumber: String
    public var mergeFields: [String: String]
    public var sourceMetadata: [String: String]

    public init(
        sourceRecordId: String? = nil,
        displayName: String,
        phoneNumber: String,
        mergeFields: [String: String] = [:],
        sourceMetadata: [String: String] = [:]
    ) {
        self.sourceRecordId = sourceRecordId
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.mergeFields = mergeFields
        self.sourceMetadata = sourceMetadata
    }
}

public enum GroupSmsAttachmentKind: String, Codable, Sendable {
    case photo
    case file
}

public struct GroupSmsAttachment: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: GroupSmsAttachmentKind
    public var fileName: String
    public var contentType: String
    public var byteCount: Int64
    public var orderIndex: Int
    public var checksum: String?
    public var localReference: String

    public init(
        id: String,
        kind: GroupSmsAttachmentKind,
        fileName: String,
        contentType: String,
        byteCount: Int64,
        orderIndex: Int,
        checksum: String? = nil,
        localReference: String
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.orderIndex = orderIndex
        self.checksum = checksum
        self.localReference = localReference
    }
}

public struct GroupSmsTestInput: Equatable, Sendable {
    public var phoneNumbers: [String]
    public var repeatsPerPhone: Int
    public var messageTemplate: String
    public var delaySettings: GroupSmsDelaySettings

    public init(
        phoneNumbers: [String],
        repeatsPerPhone: Int,
        messageTemplate: String,
        delaySettings: GroupSmsDelaySettings = GroupSmsDelaySettings()
    ) {
        self.phoneNumbers = phoneNumbers
        self.repeatsPerPhone = repeatsPerPhone
        self.messageTemplate = messageTemplate
        self.delaySettings = delaySettings
    }
}

public struct GroupSmsRecipient: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var customerId: String?
    public var displayName: String
    public var phoneNumber: String
    public var messageBody: String
    public var orderIndex: Int
    public var plannedDelaySeconds: Int

    public init(
        id: String,
        customerId: String? = nil,
        displayName: String,
        phoneNumber: String,
        messageBody: String,
        orderIndex: Int,
        plannedDelaySeconds: Int
    ) {
        self.id = id
        self.customerId = customerId
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.messageBody = messageBody
        self.orderIndex = orderIndex
        self.plannedDelaySeconds = plannedDelaySeconds
    }
}

public struct GroupSmsCampaignPayload: Codable, Equatable, Sendable {
    public var campaignId: String
    public var campaignTitle: String
    public var callbackScheme: String
    public var successPath: String
    public var cancelPath: String
    public var errorPath: String
    public var recipients: [GroupSmsRecipient]
    public var attachments: [GroupSmsAttachment]?
    public var createdAt: Date

    public init(
        campaignId: String,
        campaignTitle: String,
        callbackScheme: String,
        successPath: String,
        cancelPath: String,
        errorPath: String,
        recipients: [GroupSmsRecipient],
        attachments: [GroupSmsAttachment]? = nil,
        createdAt: Date
    ) {
        self.campaignId = campaignId
        self.campaignTitle = campaignTitle
        self.callbackScheme = callbackScheme
        self.successPath = successPath
        self.cancelPath = cancelPath
        self.errorPath = errorPath
        self.recipients = recipients
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

public struct GroupSmsCampaign: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var customerListId: String?
    public var targetDescription: String
    public var messageTemplate: String
    public var status: GroupSmsCampaignStatus
    public var recipients: [GroupSmsRecipient]
    public var attachments: [GroupSmsAttachment]?
    public var requestedAt: Date?
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        customerListId: String?,
        targetDescription: String,
        messageTemplate: String,
        status: GroupSmsCampaignStatus = .draft,
        recipients: [GroupSmsRecipient],
        attachments: [GroupSmsAttachment]? = nil,
        requestedAt: Date? = nil,
        completedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.customerListId = customerListId
        self.targetDescription = targetDescription
        self.messageTemplate = messageTemplate
        self.status = status
        self.recipients = recipients
        self.attachments = attachments
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct GroupSmsPolicySummary: Equatable, Sendable {
    public var totalCount: Int
    public var dailyLimit: Int
    public var recommendedDailyLimit: Int
    public var warning: String?
    public var isBlocked: Bool

    public init(totalCount: Int, dailyLimit: Int, recommendedDailyLimit: Int, warning: String?, isBlocked: Bool) {
        self.totalCount = totalCount
        self.dailyLimit = dailyLimit
        self.recommendedDailyLimit = recommendedDailyLimit
        self.warning = warning
        self.isBlocked = isBlocked
    }
}

public enum GroupSmsBuilderError: Error, Equatable {
    case noPhoneNumbers
    case invalidRepeatCount
    case emptyMessage
    case noRecipients
}

public enum GroupSmsBuilder {
    public static func normalizedPhoneNumbers(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(cleanPhone)
            .filter(hasDialablePhone)
    }

    public static func buildTestRecipients(
        input: GroupSmsTestInput,
        idGenerator: () -> String = { UUID().uuidString },
        randomInt: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    ) throws -> [GroupSmsRecipient] {
        let phones = input.phoneNumbers.map(cleanPhone).filter(hasDialablePhone)
        guard !phones.isEmpty else { throw GroupSmsBuilderError.noPhoneNumbers }
        guard input.repeatsPerPhone > 0 else { throw GroupSmsBuilderError.invalidRepeatCount }
        let template = input.messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { throw GroupSmsBuilderError.emptyMessage }

        let total = phones.count * input.repeatsPerPhone
        var recipients: [GroupSmsRecipient] = []
        recipients.reserveCapacity(total)

        var order = 0
        for repeatIndex in 1...input.repeatsPerPhone {
            for phoneIndex in phones.indices {
                order += 1
                let body = renderTestMessage(
                    template,
                    sequence: order,
                    total: total,
                    phoneIndex: phoneIndex + 1,
                    repeatIndex: repeatIndex
                )
                recipients.append(
                    GroupSmsRecipient(
                        id: idGenerator(),
                        displayName: "테스트 \(order)",
                        phoneNumber: phones[phoneIndex],
                        messageBody: body,
                        orderIndex: order - 1,
                        plannedDelaySeconds: delaySeconds(
                            forOrder: order,
                            settings: input.delaySettings,
                            randomInt: randomInt
                        )
                    )
                )
            }
        }
        return recipients
    }

    public static func buildCustomerRecipients(
        customers: [Customer],
        messageTemplate: String,
        delaySettings: GroupSmsDelaySettings,
        removesDuplicatePhones: Bool = true,
        idGenerator: () -> String = { UUID().uuidString },
        randomInt: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    ) throws -> [GroupSmsRecipient] {
        let targets = customers.map { customer in
            GroupMessageTarget(
                sourceRecordId: customer.id,
                displayName: customer.name,
                phoneNumber: customer.phoneNumber,
                mergeFields: [
                    "고객명": customer.name,
                    "이름": customer.name,
                    "연락처": customer.phoneNumber,
                    "주소": customer.address,
                    "메모": customer.notes
                ],
                sourceMetadata: ["customerListId": customer.customerListId]
            )
        }

        return try buildRecipients(
            targets: targets,
            messageTemplate: messageTemplate,
            delaySettings: delaySettings,
            removesDuplicatePhones: removesDuplicatePhones,
            idGenerator: idGenerator,
            randomInt: randomInt
        )
    }

    public static func buildRecipients(
        targets: [GroupMessageTarget],
        messageTemplate: String,
        delaySettings: GroupSmsDelaySettings,
        removesDuplicatePhones: Bool = true,
        idGenerator: () -> String = { UUID().uuidString },
        randomInt: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    ) throws -> [GroupSmsRecipient] {
        let template = messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { throw GroupSmsBuilderError.emptyMessage }

        var seenPhones = Set<String>()
        let dialableTargets = targets.compactMap { target -> (GroupMessageTarget, String)? in
            let phone = cleanPhone(target.phoneNumber)
            guard hasDialablePhone(phone) else { return nil }
            if removesDuplicatePhones {
                guard seenPhones.insert(phone).inserted else { return nil }
            }
            return (target, phone)
        }
        guard !dialableTargets.isEmpty else { throw GroupSmsBuilderError.noRecipients }

        let total = dialableTargets.count
        return dialableTargets.enumerated().map { index, item in
            let target = item.0
            return GroupSmsRecipient(
                id: idGenerator(),
                customerId: target.sourceRecordId,
                displayName: target.displayName.isEmpty ? item.1 : target.displayName,
                phoneNumber: item.1,
                messageBody: renderMessage(
                    template,
                    mergeFields: target.mergeFields,
                    sequence: index + 1,
                    total: total
                ),
                orderIndex: index,
                plannedDelaySeconds: delaySeconds(
                    forOrder: index + 1,
                    settings: delaySettings,
                    randomInt: randomInt
                )
            )
        }
    }

    public static func makePayload(
        configuration: GroupSmsTransportConfiguration,
        campaignId: String = UUID().uuidString,
        campaignTitle: String,
        recipients: [GroupSmsRecipient],
        attachments: [GroupSmsAttachment] = [],
        createdAt: Date = Date()
    ) -> GroupSmsCampaignPayload {
        GroupSmsCampaignPayload(
            campaignId: campaignId,
            campaignTitle: campaignTitle,
            callbackScheme: configuration.callbackScheme,
            successPath: configuration.successPath,
            cancelPath: configuration.cancelPath,
            errorPath: configuration.errorPath,
            recipients: recipients,
            attachments: attachments.isEmpty ? nil : attachments,
            createdAt: createdAt
        )
    }

    public static func encodePayload(_ payload: GroupSmsCampaignPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    public static func shortcutsRunURL(
        configuration: GroupSmsTransportConfiguration,
        campaignId: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: configuration.shortcutName),
            URLQueryItem(name: "input", value: "clipboard"),
            URLQueryItem(name: "x-success", value: "\(configuration.callbackScheme):\(configuration.successPath)?campaignId=\(campaignId)"),
            URLQueryItem(name: "x-cancel", value: "\(configuration.callbackScheme):\(configuration.cancelPath)?campaignId=\(campaignId)"),
            URLQueryItem(name: "x-error", value: "\(configuration.callbackScheme):\(configuration.errorPath)?campaignId=\(campaignId)")
        ]
        return components.url
    }

    public static func shortcutsOpenURL(configuration: GroupSmsTransportConfiguration) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "open-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: configuration.shortcutName)
        ]
        return components.url
    }

    public static func policySummary(totalCount: Int, sentTodayCount: Int = 0) -> GroupSmsPolicySummary {
        let projected = sentTodayCount + totalCount
        if projected > 500 {
            return GroupSmsPolicySummary(
                totalCount: totalCount,
                dailyLimit: 500,
                recommendedDailyLimit: 200,
                warning: "SKT 일 500건 제한을 넘을 수 있어 발송을 중단해야 합니다.",
                isBlocked: true
            )
        }
        if projected > 200 {
            return GroupSmsPolicySummary(
                totalCount: totalCount,
                dailyLimit: 500,
                recommendedDailyLimit: 200,
                warning: "오늘 누적 200건을 초과할 수 있습니다. 기본제공 혜택 제한 가능성을 확인하세요.",
                isBlocked: false
            )
        }
        if projected > 180 {
            return GroupSmsPolicySummary(
                totalCount: totalCount,
                dailyLimit: 500,
                recommendedDailyLimit: 200,
                warning: "오늘 누적 180건을 넘습니다. 200건 보호선에 가까워졌습니다.",
                isBlocked: false
            )
        }
        return GroupSmsPolicySummary(
            totalCount: totalCount,
            dailyLimit: 500,
            recommendedDailyLimit: 200,
            warning: nil,
            isBlocked: false
        )
    }

    private static func delaySeconds(
        forOrder order: Int,
        settings: GroupSmsDelaySettings,
        randomInt: (ClosedRange<Int>) -> Int
    ) -> Int {
        guard order > 1 else { return 0 }

        if settings.batchRestEnabled,
           settings.batchSize > 0,
           (order - 1).isMultiple(of: settings.batchSize) {
            let minRest = min(settings.batchMinRestSeconds, settings.batchMaxRestSeconds)
            let maxRest = max(settings.batchMinRestSeconds, settings.batchMaxRestSeconds)
            return randomInt(minRest...maxRest)
        }

        switch settings.mode {
        case .off:
            return 0
        case .fixed:
            return max(0, settings.fixedDelaySeconds)
        case .random:
            let minDelay = min(settings.minDelaySeconds, settings.maxDelaySeconds)
            let maxDelay = max(settings.minDelaySeconds, settings.maxDelaySeconds)
            return randomInt(max(0, minDelay)...max(0, maxDelay))
        }
    }

    private static func renderTestMessage(
        _ template: String,
        sequence: Int,
        total: Int,
        phoneIndex: Int,
        repeatIndex: Int
    ) -> String {
        template
            .replacingOccurrences(of: "{순번}", with: String(format: "%03d", sequence))
            .replacingOccurrences(of: "{전체}", with: "\(total)")
            .replacingOccurrences(of: "{번호순번}", with: "\(phoneIndex)")
            .replacingOccurrences(of: "{반복}", with: "\(repeatIndex)")
    }

    private static func renderMessage(
        _ template: String,
        mergeFields: [String: String],
        sequence: Int,
        total: Int
    ) -> String {
        var fields = mergeFields
        fields["순번"] = String(format: "%03d", sequence)
        fields["전체"] = "\(total)"

        return fields.reduce(template) { rendered, field in
            rendered
                .replacingOccurrences(of: "{{\(field.key)}}", with: field.value)
                .replacingOccurrences(of: "{\(field.key)}", with: field.value)
        }
    }
}
