import Foundation
import OutboundSalesCore

@MainActor
public final class NativeAppState: ObservableObject {
    @Published public private(set) var customerLists: [CustomerList]
    @Published public private(set) var customers: [Customer]
    @Published public private(set) var selectedListId: String?
    @Published public var searchText = ""
    @Published public var importMessage = ""
    @Published public var ocrMessage = "문서 스캔 OCR은 다음 단계에서 VisionKit으로 연결합니다."
    @Published public private(set) var storageMessage = ""

    private let fileStore: NativeAppFileStore

    public init(seedSamples: Bool = false, fileStore: NativeAppFileStore = NativeAppFileStore()) {
        self.fileStore = fileStore

        do {
            if let snapshot = try fileStore.load() {
                self.customerLists = snapshot.customerLists
                self.customers = snapshot.customers
                self.selectedListId = snapshot.selectedListId
                self.storageMessage = "저장된 데이터를 불러왔습니다."
                return
            }
        } catch {
            self.storageMessage = "저장된 데이터를 읽지 못했습니다."
        }

        if seedSamples {
            let seed = Self.sampleData()
            self.customerLists = seed.lists
            self.customers = seed.customers
            self.selectedListId = seed.lists.first?.id
        } else {
            self.customerLists = []
            self.customers = []
            self.selectedListId = nil
        }
    }

    public var selectedList: CustomerList? {
        customerLists.first { $0.id == selectedListId }
    }

    public var visibleCustomers: [Customer] {
        let scoped = selectedListId.map { id in customers.filter { $0.customerListId == id } } ?? customers
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { customer in
            [customer.name, customer.phoneNumber, customer.address]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public var openCustomerCount: Int {
        visibleCustomers.filter { $0.status != .done }.count
    }

    public var doneCustomerCount: Int {
        visibleCustomers.filter { $0.status == .done }.count
    }

    public func selectList(_ list: CustomerList) {
        selectedListId = list.id
        persist()
    }

    public func createEmptyList(companyName: String, listName: String) {
        let now = Date()
        let list = CustomerList(
            id: UUID().uuidString,
            name: listName.isEmpty ? "새 고객리스트" : listName,
            companyName: companyName.isEmpty ? "고객사 미지정" : companyName,
            sourceFileName: "",
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )
        customerLists.insert(list, at: 0)
        selectedListId = list.id
        persist()
    }

    public func importCSV(text: String, companyName: String, listName: String, sourceFileName: String = "import.csv") {
        do {
            let parsed = try parseCSV(text)
            let now = Date()
            let list = CustomerList(
                id: UUID().uuidString,
                name: listName.isEmpty ? sourceFileName : listName,
                companyName: companyName.isEmpty ? "고객사 미지정" : companyName,
                sourceFileName: sourceFileName,
                importedAt: now,
                createdAt: now,
                updatedAt: now
            )
            let importedCustomers = customersFromCSV(parsed, customerListId: list.id, now: now)
            customerLists.insert(list, at: 0)
            customers.append(contentsOf: importedCustomers)
            selectedListId = list.id
            importMessage = "\(importedCustomers.count)명의 고객을 가져왔습니다."
            persist()
        } catch {
            importMessage = "CSV를 읽지 못했습니다."
        }
    }

    public func importFile(url: URL, companyName: String, listName: String) {
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
            let text = try String(contentsOf: url, encoding: .utf8)
            importCSV(text: text, companyName: companyName, listName: listName, sourceFileName: fileName)
        } catch {
            importMessage = "파일을 읽지 못했습니다."
        }
    }

    public func addCustomer(name: String, phoneNumber: String, address: String, notes: String) {
        guard let listId = selectedListId else { return }
        let now = Date()
        customers.insert(
            Customer(
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
            ),
            at: 0
        )
        persist()
    }

    public func toggleDone(_ customer: Customer) {
        guard let index = customers.firstIndex(where: { $0.id == customer.id }) else { return }
        customers[index].status = customers[index].status == .done ? .open : .done
        customers[index].updatedAt = Date()
        persist()
    }

    public func resetLocalData(seedSamples: Bool = false) {
        if seedSamples {
            let seed = Self.sampleData()
            customerLists = seed.lists
            customers = seed.customers
            selectedListId = seed.lists.first?.id
        } else {
            customerLists = []
            customers = []
            selectedListId = nil
        }
        do {
            try fileStore.delete()
            storageMessage = "로컬 데이터를 초기화했습니다."
        } catch {
            storageMessage = "로컬 데이터 초기화에 실패했습니다."
        }
    }

    private func persist() {
        let snapshot = NativeAppSnapshot(
            customerLists: customerLists,
            customers: customers,
            selectedListId: selectedListId
        )

        do {
            try fileStore.save(snapshot)
            storageMessage = "로컬에 저장했습니다."
        } catch {
            storageMessage = "로컬 저장에 실패했습니다."
        }
    }

    static func sampleData() -> (lists: [CustomerList], customers: [Customer]) {
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
                region: "서초구 서초대로",
                status: .done,
                createdAt: now,
                updatedAt: now
            )
        ]
        return ([list], customers)
    }
}
