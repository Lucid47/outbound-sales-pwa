import XCTest
@testable import OutboundSalesCore

final class OutboundSalesCoreTests: XCTestCase {
    func testDetectsCsvMappingFromKoreanHeaders() throws {
        let parsed = try parseCSV("""
        성명,핸드폰1,우편물수령지,비고
        홍길동,010-1234-5678,서울 강남구 테헤란로 152,오후 방문
        """)

        XCTAssertEqual(parsed.mapping[.name], 0)
        XCTAssertEqual(parsed.mapping[.phoneNumber], 1)
        XCTAssertEqual(parsed.mapping[.address], 2)
        XCTAssertEqual(parsed.mapping[.notes], 3)
    }

    func testParsesHeaderlessCsvForManualMapping() throws {
        let parsed = try parseCSV("""
        홍길동,010-1234-5678,서울 강남구 테헤란로 152
        """, firstRowIsHeader: false)

        XCTAssertEqual(parsed.headers, ["열1", "열2", "열3"])
        XCTAssertEqual(parsed.rows.count, 1)
        XCTAssertNil(parsed.mapping[.name] ?? nil)
    }

    func testParsesQuotedCsvFields() throws {
        let rows = parseCSVRows("""
        이름,메모
        홍길동,"문자, 전화 필요"
        """)

        XCTAssertEqual(rows[1][1], "문자, 전화 필요")
    }

    func testCreatesCustomersFromParsedCsv() throws {
        let parsed = try parseCSV("""
        이름,전화번호,주소
        홍길동,010-1234-5678,서울 강남구 테헤란로 152
        """)

        let customers = customersFromCSV(parsed, customerListId: "list-1", idGenerator: { "customer-1" })

        XCTAssertEqual(customers.count, 1)
        XCTAssertEqual(customers[0].id, "customer-1")
        XCTAssertEqual(customers[0].name, "홍길동")
        XCTAssertEqual(customers[0].phoneNumber, "010-1234-5678")
        XCTAssertEqual(customers[0].region, "강남구 테헤란로")
    }

    func testNormalizesPhoneAndBirthDate() {
        XCTAssertEqual(cleanPhone("010-1234-5678"), "01012345678")
        XCTAssertTrue(hasDialablePhone("010-1234-5678"))
        XCTAssertEqual(parseBirthDate("800101"), "1980-01-01")
        XCTAssertEqual(parseBirthDate("20250101"), "2025-01-01")
    }

    func testNormalizesMapAddress() {
        XCTAssertEqual(normalizeAddressForMapSearch("서울 강남구 테헤란로 152 3층"), "서울 강남구 테헤란로 152")
        XCTAssertTrue(isSearchableAddress("서울 강남구 테헤란로 152"))
    }

    func testBuildsAppleMapGeocodeCandidates() {
        let candidates = geocodeCandidateQueries("경기도 하남시 미사강변한강로30")

        XCTAssertTrue(candidates.contains("경기도 하남시 미사강변한강로30"))
        XCTAssertTrue(candidates.contains("경기도 하남시 미사강변한강로 30"))
        XCTAssertTrue(candidates.contains("대한민국 경기도 하남시 미사강변한강로 30"))
    }

    func testSavesAndLoadsNativeSnapshot() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("native-data.json")
        let store = NativeAppFileStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let list = CustomerList(
            id: "list-1",
            name: "테스트 리스트",
            companyName: "테스트 고객사",
            sourceFileName: "sample.csv",
            importedAt: now,
            createdAt: now,
            updatedAt: now
        )
        let customer = Customer(
            id: "customer-1",
            customerListId: list.id,
            name: "홍길동",
            phoneNumber: "010-1234-5678",
            address: "서울 강남구 테헤란로 152",
            notes: "메모",
            createdAt: now,
            updatedAt: now
        )
        let snapshot = NativeAppSnapshot(
            customerLists: [list],
            customers: [customer],
            selectedListId: list.id,
            savedAt: now
        )

        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
        try store.delete()
        XCTAssertNil(try store.load())
    }
}
