import XCTest
@testable import OutboundSalesCore

final class OutboundSalesCoreTests: XCTestCase {
    func testDetectsCsvMappingFromKoreanHeaders() throws {
        let parsed = try parseCSV("""
        성명,핸드폰1,우편물주소,비고
        홍길동,010-1234-5678,서울 강남구 테헤란로 152,오후 방문
        """)

        XCTAssertEqual(parsed.mapping[.name], 0)
        XCTAssertEqual(parsed.mapping[.phoneNumber], 1)
        XCTAssertEqual(parsed.mapping[.address], 2)
        XCTAssertEqual(parsed.mapping[.notes], 3)
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
}

