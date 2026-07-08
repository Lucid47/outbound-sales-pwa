import Contacts
import Foundation

struct ContactImportCustomer: Identifiable, Equatable {
    var id: String
    var contactIdentifier: String
    var name: String
    var phoneNumber: String
    var address: String
    var notes: String
}

struct ContactImportGroup: Identifiable, Equatable {
    var id: String
    var name: String
    var containerName: String
    var count: Int
}

enum ContactImportError: LocalizedError {
    case permissionDenied
    case noContacts

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "연락처 접근 권한이 필요합니다."
        case .noContacts:
            return "가져올 연락처가 없습니다."
        }
    }
}

@MainActor
final class ContactImportService {
    private let store = CNContactStore()

    func groups() async throws -> [ContactImportGroup] {
        try await requestAccessIfNeeded()
        let containers = try store.containers(matching: nil)
        let containerNames = Dictionary(uniqueKeysWithValues: containers.map { ($0.identifier, $0.name) })
        return try store.groups(matching: nil)
            .map { group in
                ContactImportGroup(
                    id: group.identifier,
                    name: group.name,
                    containerName: containerNames[group.identifier] ?? "",
                    count: (try? contactCount(in: group)) ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.containerName == rhs.containerName {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.containerName.localizedStandardCompare(rhs.containerName) == .orderedAscending
            }
    }

    func customers(in groupIds: Set<String>) async throws -> [ContactImportCustomer] {
        try await requestAccessIfNeeded()
        guard !groupIds.isEmpty else { return [] }

        let keys = Self.contactKeys
        var contactsById: [String: CNContact] = [:]
        let groups = try store.groups(matching: nil).filter { groupIds.contains($0.identifier) }

        for group in groups {
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
            try store.enumerateContacts(with: request) { contact, _ in
                contactsById[contact.identifier] = contact
            }
        }

        let imported = contactsById.values
            .map(Self.importCustomer(from:))
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !imported.isEmpty else { throw ContactImportError.noContacts }
        return imported
    }

    nonisolated static func importCustomers(from contacts: [CNContact]) -> [ContactImportCustomer] {
        contacts
            .map(importCustomer(from:))
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func contactCount(in group: CNGroup) throws -> Int {
        let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        request.predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
        var count = 0
        try store.enumerateContacts(with: request) { _, _ in
            count += 1
        }
        return count
    }

    private func requestAccessIfNeeded() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
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
            guard granted else { throw ContactImportError.permissionDenied }
        case .denied, .restricted:
            throw ContactImportError.permissionDenied
        @unknown default:
            throw ContactImportError.permissionDenied
        }
    }

    private static let contactKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactDepartmentNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor
    ]

    nonisolated private static func importCustomer(from contact: CNContact) -> ContactImportCustomer {
        let name = [contact.familyName, contact.middleName, contact.givenName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "")
        let resolvedName = name.isEmpty ? (contact.nickname.isEmpty ? contact.organizationName : contact.nickname) : name
        let phone = preferredPhone(from: contact)
        let address = preferredAddress(from: contact)
        let notes = [contact.organizationName, contact.departmentName, contact.jobTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return ContactImportCustomer(
            id: contact.identifier,
            contactIdentifier: contact.identifier,
            name: resolvedName,
            phoneNumber: phone,
            address: address,
            notes: notes
        )
    }

    nonisolated private static func preferredPhone(from contact: CNContact) -> String {
        if let mobile = contact.phoneNumbers.first(where: { $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone }) {
            return mobile.value.stringValue
        }
        return contact.phoneNumbers.first?.value.stringValue ?? ""
    }

    nonisolated private static func preferredAddress(from contact: CNContact) -> String {
        guard let postal = contact.postalAddresses.first?.value else { return "" }
        return [
            postal.state,
            postal.city,
            postal.subLocality,
            postal.street,
            postal.postalCode
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
}
