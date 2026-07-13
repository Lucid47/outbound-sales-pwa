import Contacts
import Foundation
import OutboundSalesCore

enum ContactCleanupMode: String, CaseIterable, Identifiable {
    case groupOnly
    case appCreatedContactsAndGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groupOnly: return "그룹만 삭제"
        case .appCreatedContactsAndGroup: return "앱 생성 연락처와 그룹 삭제"
        }
    }
}

struct ContactCleanupCandidate: Identifiable, Equatable {
    var id: String { contactIdentifier }
    var customerId: String
    var contactIdentifier: String
    var registeredName: String
    var normalizedPhone: String
}

struct ContactCleanupPreview: Equatable {
    var groupName: String
    var deletableGroupIdentifiers: [String]
    var eligibleContacts: [ContactCleanupCandidate]
    var protectedExistingCount: Int
    var missingCount: Int
    var modifiedCount: Int
    var otherGroupCount: Int
    var unownedGroupMemberCount: Int
    var legacyCandidateCount: Int

    var groupCount: Int { deletableGroupIdentifiers.count }
}

struct ContactCleanupSummary: Equatable {
    var deletedContactIdentifiers: [String]
    var deletedGroupIdentifiers: [String]
    var skippedCount: Int
}

enum ContactCleanupError: LocalizedError {
    case permissionDenied
    case nothingToDelete

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "연락처 접근 권한이 필요합니다."
        case .nothingToDelete:
            return "안전하게 삭제할 연락처나 그룹이 없습니다."
        }
    }
}

@MainActor
final class ContactCleanupService {
    private let store = CNContactStore()

    func preview(
        customerListId: String,
        groupName: String,
        customers: [Customer],
        batches: [ContactExportBatch]
    ) async throws -> ContactCleanupPreview {
        try await requestAccessIfNeeded()

        let installationIdentifier = ContactExportService.installationIdentifier
        let localBatches = batches.filter {
            $0.customerListId == customerListId && $0.installationIdentifier == installationIdentifier
        }
        let deletedIdentifiers = Set(localBatches.flatMap(\.deletedContactIdentifiers))

        var ownedByIdentifier: [String: ContactCleanupCandidate] = [:]
        var protectedIdentifiers = Set<String>()
        for batch in localBatches {
            for record in batch.records where !deletedIdentifiers.contains(record.contactIdentifier) {
                switch record.ownership {
                case .createdByApp:
                    ownedByIdentifier[record.contactIdentifier] = ContactCleanupCandidate(
                        customerId: record.customerId,
                        contactIdentifier: record.contactIdentifier,
                        registeredName: record.registeredName,
                        normalizedPhone: record.normalizedPhone
                    )
                case .updatedExisting, .linkedExisting, .unknown:
                    protectedIdentifiers.insert(record.contactIdentifier)
                }
            }
        }

        var legacyCandidateCount = 0
        for customer in customers where customer.customerListId == customerListId {
            guard let identifier = customer.contactIdentifier, !identifier.isEmpty else { continue }
            if customer.contactRegistrationOwnership == .updatedExisting ||
                customer.contactRegistrationOwnership == .linkedExisting ||
                customer.contactRegistrationStatus == .updated ||
                customer.contactRegistrationStatus == .skippedDuplicate {
                protectedIdentifiers.insert(identifier)
                continue
            }

            let isOwned = customer.contactRegistrationOwnership == .createdByApp ||
                (customer.contactRegistrationOwnership == nil && customer.contactRegistrationStatus == .registered)
            guard isOwned, !deletedIdentifiers.contains(identifier) else { continue }
            if ownedByIdentifier[identifier] == nil {
                legacyCandidateCount += 1
                ownedByIdentifier[identifier] = ContactCleanupCandidate(
                    customerId: customer.id,
                    contactIdentifier: identifier,
                    registeredName: customer.contactRegisteredName ?? customer.name,
                    normalizedPhone: ContactExportService.normalizedPhone(customer.phoneNumber)
                )
            }
        }

        let ownedIdentifiers = Set(ownedByIdentifier.keys)
        let contacts = try fetchRawContacts(identifiers: ownedIdentifiers)
        let deletableGroupIdentifiers = try deletableGroups(
            from: localBatches,
            legacyGroupName: groupName,
            ownedContactIdentifiers: ownedIdentifiers
        )
        let otherGroupMemberIdentifiers = try groupMemberIdentifiers(excluding: Set(deletableGroupIdentifiers))
        let ownedGroupMemberIdentifiers = try memberIdentifiers(inGroups: Set(deletableGroupIdentifiers))

        var eligibleContacts: [ContactCleanupCandidate] = []
        var missingCount = 0
        var modifiedCount = 0
        var otherGroupCount = 0
        for candidate in ownedByIdentifier.values {
            guard let contact = contacts[candidate.contactIdentifier] else {
                missingCount += 1
                continue
            }
            let contactName = [contact.givenName, contact.familyName]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let phones = Set(contact.phoneNumbers.map { ContactExportService.normalizedPhone($0.value.stringValue) })
            guard contactName == candidate.registeredName,
                  !candidate.normalizedPhone.isEmpty,
                  phones.contains(candidate.normalizedPhone) else {
                modifiedCount += 1
                continue
            }
            guard !otherGroupMemberIdentifiers.contains(candidate.contactIdentifier) else {
                otherGroupCount += 1
                continue
            }
            eligibleContacts.append(candidate)
        }

        eligibleContacts.sort { lhs, rhs in
            lhs.registeredName.localizedStandardCompare(rhs.registeredName) == .orderedAscending
        }
        let unownedGroupMemberCount = ownedGroupMemberIdentifiers.subtracting(ownedIdentifiers).count

        return ContactCleanupPreview(
            groupName: groupName,
            deletableGroupIdentifiers: deletableGroupIdentifiers,
            eligibleContacts: eligibleContacts,
            protectedExistingCount: protectedIdentifiers.count,
            missingCount: missingCount,
            modifiedCount: modifiedCount,
            otherGroupCount: otherGroupCount,
            unownedGroupMemberCount: unownedGroupMemberCount,
            legacyCandidateCount: legacyCandidateCount
        )
    }

    func cleanup(
        mode: ContactCleanupMode,
        customerListId: String,
        groupName: String,
        customers: [Customer],
        batches: [ContactExportBatch]
    ) async throws -> ContactCleanupSummary {
        let current = try await preview(
            customerListId: customerListId,
            groupName: groupName,
            customers: customers,
            batches: batches
        )
        let contactIdentifiers = mode == .appCreatedContactsAndGroup
            ? Set(current.eligibleContacts.map(\.contactIdentifier))
            : []
        let contacts = try fetchRawContacts(identifiers: contactIdentifiers)
        let allGroups = try store.groups(matching: nil)
        let groups = allGroups.filter { current.deletableGroupIdentifiers.contains($0.identifier) }

        guard !contacts.isEmpty || !groups.isEmpty else {
            throw ContactCleanupError.nothingToDelete
        }

        let request = CNSaveRequest()
        for contact in contacts.values {
            request.delete(contact.mutableCopy() as! CNMutableContact)
        }
        for group in groups {
            request.delete(group.mutableCopy() as! CNMutableGroup)
        }
        try store.execute(request)

        return ContactCleanupSummary(
            deletedContactIdentifiers: Array(contacts.keys).sorted(),
            deletedGroupIdentifiers: groups.map(\.identifier).sorted(),
            skippedCount: current.protectedExistingCount + current.missingCount + current.modifiedCount + current.otherGroupCount
        )
    }

    private func requestAccessIfNeeded() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestAccess(for: .contacts) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            guard granted else { throw ContactCleanupError.permissionDenied }
        case .denied, .restricted:
            throw ContactCleanupError.permissionDenied
        @unknown default:
            throw ContactCleanupError.permissionDenied
        }
    }

    private func fetchRawContacts(identifiers: Set<String>) throws -> [String: CNContact] {
        guard !identifiers.isEmpty else { return [:] }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContacts(withIdentifiers: Array(identifiers))
        request.unifyResults = false
        var contacts: [String: CNContact] = [:]
        try store.enumerateContacts(with: request) { contact, _ in
            contacts[contact.identifier] = contact
        }
        return contacts
    }

    private func deletableGroups(
        from batches: [ContactExportBatch],
        legacyGroupName: String,
        ownedContactIdentifiers: Set<String>
    ) throws -> [String] {
        var identifiers = Set(batches.compactMap { batch -> String? in
            guard batch.groupCreatedByApp, batch.groupDeletedAt == nil else { return nil }
            return batch.groupIdentifier
        })
        let existing = try store.groups(matching: nil)
        for group in existing where group.name == legacyGroupName && !identifiers.contains(group.identifier) {
            let members = try memberIdentifiers(inGroups: [group.identifier])
            if !members.isDisjoint(with: ownedContactIdentifiers) {
                identifiers.insert(group.identifier)
            }
        }
        return existing.map(\.identifier).filter { identifiers.contains($0) }.sorted()
    }

    private func groupMemberIdentifiers(excluding excludedGroupIdentifiers: Set<String>) throws -> Set<String> {
        let groups = try store.groups(matching: nil).filter { !excludedGroupIdentifiers.contains($0.identifier) }
        return try memberIdentifiers(inGroups: Set(groups.map(\.identifier)))
    }

    private func memberIdentifiers(inGroups identifiers: Set<String>) throws -> Set<String> {
        guard !identifiers.isEmpty else { return [] }
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        var memberIdentifiers = Set<String>()
        for groupIdentifier in identifiers {
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.predicate = CNContact.predicateForContactsInGroup(withIdentifier: groupIdentifier)
            request.unifyResults = false
            try store.enumerateContacts(with: request) { contact, _ in
                memberIdentifiers.insert(contact.identifier)
            }
        }
        return memberIdentifiers
    }
}
