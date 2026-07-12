import Foundation

public enum GroupSmsTargetExclusionReason: String, Codable, CaseIterable, Sendable {
    case userExcluded
    case missingOrInvalidPhone
    case duplicatePhone
    case recentlyMessaged
}

public struct GroupSmsExcludedTarget: Codable, Equatable, Sendable {
    public var target: GroupMessageTarget
    public var normalizedPhoneNumber: String?
    public var reason: GroupSmsTargetExclusionReason
    public var duplicateOfSourceRecordId: String?

    public init(
        target: GroupMessageTarget,
        normalizedPhoneNumber: String?,
        reason: GroupSmsTargetExclusionReason,
        duplicateOfSourceRecordId: String? = nil
    ) {
        self.target = target
        self.normalizedPhoneNumber = normalizedPhoneNumber
        self.reason = reason
        self.duplicateOfSourceRecordId = duplicateOfSourceRecordId
    }
}

public struct GroupSmsTargetSelectionResult: Codable, Equatable, Sendable {
    public var totalCandidateCount: Int
    public var includedTargets: [GroupMessageTarget]
    public var excludedTargets: [GroupSmsExcludedTarget]

    public init(
        totalCandidateCount: Int,
        includedTargets: [GroupMessageTarget],
        excludedTargets: [GroupSmsExcludedTarget]
    ) {
        self.totalCandidateCount = totalCandidateCount
        self.includedTargets = includedTargets
        self.excludedTargets = excludedTargets
    }

    public func excludedCount(for reason: GroupSmsTargetExclusionReason) -> Int {
        excludedTargets.lazy.filter { $0.reason == reason }.count
    }
}

public enum GroupSmsTargetSelector {
    public static func select(
        targets: [GroupMessageTarget],
        userExcludedSourceRecordIds: Set<String> = [],
        removesDuplicatePhones: Bool = true,
        recentlyMessagedPhoneNumbers: Set<String> = []
    ) -> GroupSmsTargetSelectionResult {
        let recentPhones = Set(recentlyMessagedPhoneNumbers.map(cleanPhone).filter(hasDialablePhone))
        var firstTargetByPhone: [String: GroupMessageTarget] = [:]
        var included: [GroupMessageTarget] = []
        var excluded: [GroupSmsExcludedTarget] = []

        for target in targets {
            if let sourceRecordId = target.sourceRecordId,
               userExcludedSourceRecordIds.contains(sourceRecordId) {
                excluded.append(
                    GroupSmsExcludedTarget(
                        target: target,
                        normalizedPhoneNumber: nil,
                        reason: .userExcluded
                    )
                )
                continue
            }

            let normalizedPhone = cleanPhone(target.phoneNumber)
            guard hasDialablePhone(normalizedPhone) else {
                excluded.append(
                    GroupSmsExcludedTarget(
                        target: target,
                        normalizedPhoneNumber: normalizedPhone.isEmpty ? nil : normalizedPhone,
                        reason: .missingOrInvalidPhone
                    )
                )
                continue
            }

            if removesDuplicatePhones, let firstTarget = firstTargetByPhone[normalizedPhone] {
                excluded.append(
                    GroupSmsExcludedTarget(
                        target: target,
                        normalizedPhoneNumber: normalizedPhone,
                        reason: .duplicatePhone,
                        duplicateOfSourceRecordId: firstTarget.sourceRecordId
                    )
                )
                continue
            }

            if recentPhones.contains(normalizedPhone) {
                excluded.append(
                    GroupSmsExcludedTarget(
                        target: target,
                        normalizedPhoneNumber: normalizedPhone,
                        reason: .recentlyMessaged
                    )
                )
                continue
            }

            var normalizedTarget = target
            normalizedTarget.phoneNumber = normalizedPhone
            firstTargetByPhone[normalizedPhone] = normalizedTarget
            included.append(normalizedTarget)
        }

        return GroupSmsTargetSelectionResult(
            totalCandidateCount: targets.count,
            includedTargets: included,
            excludedTargets: excluded
        )
    }
}

public enum GroupSmsAutomationReadiness: String, Codable, CaseIterable, Sendable {
    case notInstalled
    case installedNeedsTest
    case messagePermissionRequired
    case attachmentPermissionRequired
    case ready
    case updateRequired
    case unavailable
}

public enum GroupSmsEstimatedMessageKind: String, Codable, Sendable {
    case sms
    case lms
    case mms
}

public enum GroupSmsPreflightBlockingReason: String, Codable, CaseIterable, Sendable {
    case noRecipients
    case emptyContent
    case automationNotReady
    case policyLimitExceeded
    case invalidAttachments
}

public enum GroupSmsAttachmentIssueReason: String, Codable, Sendable {
    case emptyFileName
    case emptyContentType
    case emptyLocalReference
    case invalidByteCount
    case duplicateOrderIndex
}

public struct GroupSmsAttachmentIssue: Codable, Equatable, Sendable {
    public var attachmentId: String
    public var reason: GroupSmsAttachmentIssueReason

    public init(attachmentId: String, reason: GroupSmsAttachmentIssueReason) {
        self.attachmentId = attachmentId
        self.reason = reason
    }
}

public struct GroupSmsPreflightSummary: Equatable, Sendable {
    public var selection: GroupSmsTargetSelectionResult
    public var recipientCount: Int
    public var estimatedMessageKind: GroupSmsEstimatedMessageKind
    public var estimatedDurationSeconds: Int
    public var totalAttachmentBytes: Int64
    public var attachmentIssues: [GroupSmsAttachmentIssue]
    public var policySummary: GroupSmsPolicySummary
    public var automationReadiness: GroupSmsAutomationReadiness
    public var blockingReasons: [GroupSmsPreflightBlockingReason]

    public var canLaunch: Bool { blockingReasons.isEmpty }

    public init(
        selection: GroupSmsTargetSelectionResult,
        recipientCount: Int,
        estimatedMessageKind: GroupSmsEstimatedMessageKind,
        estimatedDurationSeconds: Int,
        totalAttachmentBytes: Int64,
        attachmentIssues: [GroupSmsAttachmentIssue],
        policySummary: GroupSmsPolicySummary,
        automationReadiness: GroupSmsAutomationReadiness,
        blockingReasons: [GroupSmsPreflightBlockingReason]
    ) {
        self.selection = selection
        self.recipientCount = recipientCount
        self.estimatedMessageKind = estimatedMessageKind
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.totalAttachmentBytes = totalAttachmentBytes
        self.attachmentIssues = attachmentIssues
        self.policySummary = policySummary
        self.automationReadiness = automationReadiness
        self.blockingReasons = blockingReasons
    }
}

public enum GroupSmsPreflightEvaluator {
    public static func evaluate(
        selection: GroupSmsTargetSelectionResult,
        recipients: [GroupSmsRecipient],
        messageTemplate: String,
        attachments: [GroupSmsAttachment],
        automationReadiness: GroupSmsAutomationReadiness,
        sentTodayCount: Int = 0,
        smsEstimatedByteLimit: Int = 90
    ) -> GroupSmsPreflightSummary {
        let attachmentIssues = validateAttachments(attachments)
        let policy = GroupSmsBuilder.policySummary(
            totalCount: selection.includedTargets.count,
            sentTodayCount: sentTodayCount
        )
        var blockingReasons: [GroupSmsPreflightBlockingReason] = []

        if selection.includedTargets.isEmpty {
            blockingReasons.append(.noRecipients)
        }
        if messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           attachments.isEmpty {
            blockingReasons.append(.emptyContent)
        }
        if automationReadiness != .ready {
            blockingReasons.append(.automationNotReady)
        }
        if policy.isBlocked {
            blockingReasons.append(.policyLimitExceeded)
        }
        if !attachmentIssues.isEmpty {
            blockingReasons.append(.invalidAttachments)
        }

        let messageKind: GroupSmsEstimatedMessageKind
        if !attachments.isEmpty {
            messageKind = .mms
        } else {
            let maximumBodyBytes = recipients.map { $0.messageBody.lengthOfBytes(using: .utf8) }.max() ?? 0
            messageKind = maximumBodyBytes <= smsEstimatedByteLimit ? .sms : .lms
        }

        return GroupSmsPreflightSummary(
            selection: selection,
            recipientCount: recipients.count,
            estimatedMessageKind: messageKind,
            estimatedDurationSeconds: recipients.reduce(0) { $0 + max(0, $1.plannedDelaySeconds) },
            totalAttachmentBytes: attachments.reduce(0) { $0 + max(0, $1.byteCount) },
            attachmentIssues: attachmentIssues,
            policySummary: policy,
            automationReadiness: automationReadiness,
            blockingReasons: blockingReasons
        )
    }

    private static func validateAttachments(_ attachments: [GroupSmsAttachment]) -> [GroupSmsAttachmentIssue] {
        var issues: [GroupSmsAttachmentIssue] = []
        let duplicateOrderIndexes = Dictionary(grouping: attachments, by: \.orderIndex)
            .filter { $0.value.count > 1 }
            .keys

        for attachment in attachments {
            if attachment.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(GroupSmsAttachmentIssue(attachmentId: attachment.id, reason: .emptyFileName))
            }
            if attachment.contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(GroupSmsAttachmentIssue(attachmentId: attachment.id, reason: .emptyContentType))
            }
            if attachment.localReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(GroupSmsAttachmentIssue(attachmentId: attachment.id, reason: .emptyLocalReference))
            }
            if attachment.byteCount <= 0 {
                issues.append(GroupSmsAttachmentIssue(attachmentId: attachment.id, reason: .invalidByteCount))
            }
            if duplicateOrderIndexes.contains(attachment.orderIndex) {
                issues.append(GroupSmsAttachmentIssue(attachmentId: attachment.id, reason: .duplicateOrderIndex))
            }
        }
        return issues
    }
}
