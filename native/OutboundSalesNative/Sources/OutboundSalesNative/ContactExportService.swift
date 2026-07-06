import Contacts
import Foundation
import OutboundSalesCore

enum ContactDuplicateHandling: String, CaseIterable, Identifiable {
    case skip
    case update
    case addNew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skip: return "건너뛰기"
        case .update: return "기존 연락처 업데이트"
        case .addNew: return "새 연락처로 추가"
        }
    }
}

struct ContactExportOptions: Equatable {
    var groupName: String
    var usePrefix: Bool
    var prefix: String
    var suffix: String
    var duplicateHandling: ContactDuplicateHandling

    func registeredName(for customer: Customer) -> String {
        let baseName = customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = baseName.isEmpty ? "이름 없음" : baseName
        let appliedPrefix = usePrefix ? prefix : ""
        return "\(appliedPrefix)\(resolvedName)\(suffix)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ContactExportPreview: Equatable {
    var totalCount: Int
    var phoneCount: Int
    var noPhoneCount: Int
    var duplicateCandidateCount: Int
}

struct ContactExportFailure: Identifiable, Equatable {
    var id = UUID()
    var customerName: String
    var phoneNumber: String
    var reason: String
}

struct ContactExportCustomerResult: Equatable {
    var customerId: String
    var status: ContactRegistrationStatus
    var contactIdentifier: String?
    var registeredName: String?
}

struct ContactExportSummary: Equatable {
    var createdCount = 0
    var updatedCount = 0
    var skippedDuplicateCount = 0
    var skippedNoPhoneCount = 0
    var failedCount = 0
    var failures: [ContactExportFailure] = []
    var customerResults: [ContactExportCustomerResult] = []
}

enum ContactExportError: LocalizedError {
    case permissionDenied
    case groupCreationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "연락처 접근 권한이 필요합니다."
        case .groupCreationFailed:
            return "연락처 그룹을 만들지 못했습니다."
        }
    }
}

@MainActor
final class ContactExportService {
    private let store = CNContactStore()

    func preview(customers: [Customer]) async throws -> ContactExportPreview {
        try await requestAccessIfNeeded()
        let phoneKeys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let existingPhones = try fetchExistingPhones(keys: phoneKeys)
        let normalizedPhones = customers.map { Self.normalizedPhone($0.phoneNumber) }
        let phoneCount = normalizedPhones.filter { !$0.isEmpty }.count
        let duplicateCount = normalizedPhones.filter { !$0.isEmpty && existingPhones[$0] != nil }.count

        return ContactExportPreview(
            totalCount: customers.count,
            phoneCount: phoneCount,
            noPhoneCount: customers.count - phoneCount,
            duplicateCandidateCount: duplicateCount
        )
    }

    func export(customers: [Customer], options: ContactExportOptions) async throws -> ContactExportSummary {
        try await requestAccessIfNeeded()
        let group = try ensureGroup(named: options.groupName)
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor
        ]
        let existingContactsByPhone = try fetchExistingContactsByPhone(keys: keys)
        let groupMemberIds = try fetchGroupMemberIdentifiers(group: group)

        var summary = ContactExportSummary()

        for customer in customers {
            let normalizedPhone = Self.normalizedPhone(customer.phoneNumber)
            let registeredName = options.registeredName(for: customer)
            guard !normalizedPhone.isEmpty else {
                summary.skippedNoPhoneCount += 1
                summary.customerResults.append(
                    ContactExportCustomerResult(
                        customerId: customer.id,
                        status: .failed,
                        contactIdentifier: nil,
                        registeredName: registeredName
                    )
                )
                continue
            }

            if let existing = existingContactsByPhone[normalizedPhone]?.first {
                switch options.duplicateHandling {
                case .skip:
                    summary.skippedDuplicateCount += 1
                    summary.customerResults.append(
                        ContactExportCustomerResult(
                            customerId: customer.id,
                            status: .skippedDuplicate,
                            contactIdentifier: existing.identifier,
                            registeredName: registeredName
                        )
                    )
                case .update:
                    do {
                        let updated = existing.mutableCopy() as! CNMutableContact
                        apply(customer: customer, to: updated, registeredName: registeredName)
                        let request = CNSaveRequest()
                        request.update(updated)
                        if !groupMemberIds.contains(existing.identifier) {
                            request.addMember(updated, to: group)
                        }
                        try store.execute(request)
                        summary.updatedCount += 1
                        summary.customerResults.append(
                            ContactExportCustomerResult(
                                customerId: customer.id,
                                status: .updated,
                                contactIdentifier: updated.identifier,
                                registeredName: registeredName
                            )
                        )
                    } catch {
                        appendFailure(customer: customer, reason: error.localizedDescription, to: &summary)
                    }
                case .addNew:
                    addNewContact(customer: customer, group: group, registeredName: registeredName, summary: &summary)
                }
            } else {
                addNewContact(customer: customer, group: group, registeredName: registeredName, summary: &summary)
            }
        }

        return summary
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
            guard granted else { throw ContactExportError.permissionDenied }
        case .denied, .restricted:
            throw ContactExportError.permissionDenied
        @unknown default:
            throw ContactExportError.permissionDenied
        }
    }

    private func ensureGroup(named rawName: String) throws -> CNGroup {
        let groupName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "고객리스트" : rawName
        let containerId = store.defaultContainerIdentifier()
        let groups = try store.groups(matching: nil)
        if let existing = groups.first(where: { $0.name == groupName }) {
            return existing
        }

        let group = CNMutableGroup()
        group.name = groupName
        let request = CNSaveRequest()
        request.add(group, toContainerWithIdentifier: containerId)
        try store.execute(request)

        guard let created = try store.groups(matching: nil).first(where: { $0.name == groupName }) else {
            throw ContactExportError.groupCreationFailed
        }
        return created
    }

    private func fetchExistingPhones(keys: [CNKeyDescriptor]) throws -> [String: Bool] {
        var phones: [String: Bool] = [:]
        let request = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                let normalized = Self.normalizedPhone(phone.value.stringValue)
                if !normalized.isEmpty {
                    phones[normalized] = true
                }
            }
        }
        return phones
    }

    private func fetchExistingContactsByPhone(keys: [CNKeyDescriptor]) throws -> [String: [CNContact]] {
        var contactsByPhone: [String: [CNContact]] = [:]
        let request = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                let normalized = Self.normalizedPhone(phone.value.stringValue)
                if !normalized.isEmpty {
                    contactsByPhone[normalized, default: []].append(contact)
                }
            }
        }
        return contactsByPhone
    }

    private func fetchGroupMemberIdentifiers(group: CNGroup) throws -> Set<String> {
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
        var identifiers = Set<String>()
        try store.enumerateContacts(with: request) { contact, _ in
            identifiers.insert(contact.identifier)
        }
        return identifiers
    }

    private func addNewContact(
        customer: Customer,
        group: CNGroup,
        registeredName: String,
        summary: inout ContactExportSummary
    ) {
        do {
            let contact = CNMutableContact()
            apply(customer: customer, to: contact, registeredName: registeredName)
            let request = CNSaveRequest()
            request.add(contact, toContainerWithIdentifier: store.defaultContainerIdentifier())
            request.addMember(contact, to: group)
            try store.execute(request)
            summary.createdCount += 1
            summary.customerResults.append(
                ContactExportCustomerResult(
                    customerId: customer.id,
                    status: .registered,
                    contactIdentifier: contact.identifier,
                    registeredName: registeredName
                )
            )
        } catch {
            appendFailure(customer: customer, reason: error.localizedDescription, to: &summary)
        }
    }

    private func apply(customer: Customer, to contact: CNMutableContact, registeredName: String) {
        contact.givenName = registeredName
        contact.familyName = ""
        contact.phoneNumbers = [
            CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: customer.phoneNumber)
            )
        ]
        if !customer.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let postal = CNMutablePostalAddress()
            postal.street = customer.address
            contact.postalAddresses = [
                CNLabeledValue(label: CNLabelHome, value: postal)
            ]
        }
    }

    private func appendFailure(customer: Customer, reason: String, to summary: inout ContactExportSummary) {
        summary.failedCount += 1
        summary.failures.append(
            ContactExportFailure(
                customerName: customer.name,
                phoneNumber: customer.phoneNumber,
                reason: reason
            )
        )
        summary.customerResults.append(
            ContactExportCustomerResult(
                customerId: customer.id,
                status: .failed,
                contactIdentifier: nil,
                registeredName: nil
            )
        )
    }

    static func normalizedPhone(_ value: String) -> String {
        value.filter(\.isNumber)
    }
}
