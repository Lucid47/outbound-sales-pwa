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

    func testDecodesCP949CSVText() throws {
        let data = Data([
            0xc0, 0xcc, 0xb8, 0xa7, 0x2c, 0xc0, 0xfc, 0xc8, 0xad, 0xb9, 0xf8, 0xc8,
            0xa3, 0x2c, 0xc1, 0xd6, 0xbc, 0xd2, 0x0a, 0xc8, 0xab, 0xb1, 0xe6, 0xb5,
            0xbf, 0x2c, 0x30, 0x31, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
            0x38, 0x2c, 0xbc, 0xad, 0xbf, 0xef, 0x0a
        ])

        let parsed = try parseCSV(decodeCSVText(data: data))

        XCTAssertEqual(parsed.headers, ["이름", "전화번호", "주소"])
        XCTAssertEqual(parsed.rows.first, ["홍길동", "01012345678", "서울"])
        XCTAssertEqual(parsed.mapping[.name], 0)
        XCTAssertEqual(parsed.mapping[.phoneNumber], 1)
        XCTAssertEqual(parsed.mapping[.address], 2)
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

    func testBuildsGroupSmsRepeatedTestRecipientsForTwoPhones() throws {
        var id = 0
        let recipients = try GroupSmsBuilder.buildTestRecipients(
            input: GroupSmsTestInput(
                phoneNumbers: ["010-1111-2222", "010-3333-4444"],
                repeatsPerPhone: 2,
                messageTemplate: "테스트 {순번}/{전체}",
                delaySettings: GroupSmsDelaySettings(mode: .off)
            ),
            idGenerator: {
                id += 1
                return "recipient-\(id)"
            }
        )

        XCTAssertEqual(recipients.count, 4)
        XCTAssertEqual(recipients.map(\.phoneNumber), ["01011112222", "01033334444", "01011112222", "01033334444"])
        XCTAssertEqual(recipients.map(\.messageBody), ["테스트 001/4", "테스트 002/4", "테스트 003/4", "테스트 004/4"])
        XCTAssertEqual(recipients.map(\.plannedDelaySeconds), [0, 0, 0, 0])
    }

    func testBuildsGroupSmsRandomAndBatchDelays() throws {
        let recipients = try GroupSmsBuilder.buildTestRecipients(
            input: GroupSmsTestInput(
                phoneNumbers: ["01011112222"],
                repeatsPerPhone: 4,
                messageTemplate: "테스트 {순번}",
                delaySettings: GroupSmsDelaySettings(
                    mode: .random,
                    minDelaySeconds: 1,
                    maxDelaySeconds: 3,
                    batchRestEnabled: true,
                    batchSize: 3,
                    batchMinRestSeconds: 30,
                    batchMaxRestSeconds: 60
                )
            ),
            idGenerator: { "id" },
            randomInt: { range in range.lowerBound }
        )

        XCTAssertEqual(recipients.map(\.plannedDelaySeconds), [0, 1, 1, 30])
    }

    func testBuildsGroupSmsCustomerRecipientsWithPersonalizedFields() throws {
        let now = Date(timeIntervalSince1970: 1)
        let customers = [
            Customer(id: "customer-1", customerListId: "list-1", name: "김소희", phoneNumber: "010-1111-2222", address: "서울 성동구 성수일로 10", notes: "오전 선호", createdAt: now, updatedAt: now),
            Customer(id: "customer-2", customerListId: "list-1", name: "박영은", phoneNumber: "010-3333-4444", address: "서울 송파구", notes: "", createdAt: now, updatedAt: now),
            Customer(id: "customer-3", customerListId: "list-1", name: "중복", phoneNumber: "01033334444", address: "서울 강남구", notes: "", createdAt: now, updatedAt: now)
        ]

        let recipients = try GroupSmsBuilder.buildCustomerRecipients(
            customers: customers,
            messageTemplate: "{고객명}님 {주소} / {순번}/{전체}",
            delaySettings: GroupSmsDelaySettings(mode: .fixed, fixedDelaySeconds: 2),
            removesDuplicatePhones: true,
            idGenerator: { "recipient" }
        )

        XCTAssertEqual(recipients.count, 2)
        XCTAssertEqual(recipients[0].customerId, "customer-1")
        XCTAssertEqual(recipients[0].messageBody, "김소희님 서울 성동구 성수일로 10 / 001/2")
        XCTAssertEqual(recipients[1].messageBody, "박영은님 서울 송파구 / 002/2")
        XCTAssertEqual(recipients.map(\.plannedDelaySeconds), [0, 2])
    }

    func testEncodesGroupSmsPayloadAndShortcutURL() throws {
        let configuration = GroupSmsTransportConfiguration(
            shortcutName: "SoheeGroupSMS",
            shortcutVersion: "0.1",
            callbackScheme: "com.lucid47.outboundsales"
        )
        let recipients = [
            GroupSmsRecipient(
                id: "recipient-1",
                displayName: "테스트 1",
                phoneNumber: "01011112222",
                messageBody: "본문",
                orderIndex: 0,
                plannedDelaySeconds: 0
            )
        ]
        let payload = GroupSmsBuilder.makePayload(
            configuration: configuration,
            campaignId: "campaign-1",
            campaignTitle: "반복 테스트",
            recipients: recipients,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let json = try GroupSmsBuilder.encodePayload(payload)
        XCTAssertTrue(json.contains("\"campaignId\":\"campaign-1\""))
        XCTAssertTrue(json.contains("\"phoneNumber\":\"01011112222\""))

        let url = try XCTUnwrap(GroupSmsBuilder.shortcutsRunURL(configuration: configuration, campaignId: "campaign-1"))
        XCTAssertEqual(url.scheme, "shortcuts")
        XCTAssertTrue(url.absoluteString.contains("SoheeGroupSMS"))
        XCTAssertTrue(url.absoluteString.contains("campaign-1"))

        let openURL = try XCTUnwrap(GroupSmsBuilder.shortcutsOpenURL(configuration: configuration))
        XCTAssertEqual(openURL.absoluteString, "shortcuts://open-shortcut?name=SoheeGroupSMS")
    }

    func testBuildsProductNeutralGroupSmsTargets() throws {
        let targets = [
            GroupMessageTarget(
                sourceRecordId: "contact-1",
                displayName: "김소희",
                phoneNumber: "010-1111-2222",
                mergeFields: ["이름": "김소희", "지역": "성동구"]
            )
        ]

        let recipients = try GroupSmsBuilder.buildRecipients(
            targets: targets,
            messageTemplate: "{이름}님 {{지역}} 안내 {순번}/{전체}",
            delaySettings: GroupSmsDelaySettings(),
            idGenerator: { "recipient-1" }
        )

        XCTAssertEqual(recipients.count, 1)
        XCTAssertEqual(recipients[0].customerId, "contact-1")
        XCTAssertEqual(recipients[0].phoneNumber, "01011112222")
        XCTAssertEqual(recipients[0].messageBody, "김소희님 성동구 안내 001/1")
    }

    func testEncodesMultiplePhotoAndFileAttachments() throws {
        let configuration = GroupSmsTransportConfiguration(
            shortcutName: "SoheeGroupSMS",
            shortcutVersion: "0.1",
            callbackScheme: "com.lucid47.outboundsales"
        )
        let attachments = [
            GroupSmsAttachment(
                id: "photo-1",
                kind: .photo,
                fileName: "photo-1.heic",
                contentType: "image/heic",
                byteCount: 1_024,
                orderIndex: 0,
                localReference: "campaign/photo-1.heic"
            ),
            GroupSmsAttachment(
                id: "photo-2",
                kind: .photo,
                fileName: "photo-2.jpg",
                contentType: "image/jpeg",
                byteCount: 2_048,
                orderIndex: 1,
                localReference: "campaign/photo-2.jpg"
            ),
            GroupSmsAttachment(
                id: "file-1",
                kind: .file,
                fileName: "guide.pdf",
                contentType: "application/pdf",
                byteCount: 4_096,
                orderIndex: 2,
                localReference: "campaign/guide.pdf"
            )
        ]

        let payload = GroupSmsBuilder.makePayload(
            configuration: configuration,
            campaignTitle: "혼합 첨부 시험",
            recipients: [],
            attachments: attachments,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let json = try GroupSmsBuilder.encodePayload(payload)

        XCTAssertEqual(payload.attachments?.count, 3)
        XCTAssertTrue(json.contains("\"fileName\":\"photo-1.heic\""))
        XCTAssertTrue(json.contains("\"fileName\":\"guide.pdf\""))
    }

    func testClassifiesExcludedGroupSmsTargets() {
        let targets = [
            GroupMessageTarget(sourceRecordId: "included", displayName: "포함", phoneNumber: "010-1111-2222"),
            GroupMessageTarget(sourceRecordId: "duplicate", displayName: "중복", phoneNumber: "01011112222"),
            GroupMessageTarget(sourceRecordId: "invalid", displayName: "오류", phoneNumber: "번호없음"),
            GroupMessageTarget(sourceRecordId: "manual", displayName: "사용자 제외", phoneNumber: "01033334444"),
            GroupMessageTarget(sourceRecordId: "recent", displayName: "최근 발송", phoneNumber: "01055556666")
        ]

        let result = GroupSmsTargetSelector.select(
            targets: targets,
            userExcludedSourceRecordIds: ["manual"],
            recentlyMessagedPhoneNumbers: ["010-5555-6666"]
        )

        XCTAssertEqual(result.includedTargets.map(\.sourceRecordId), ["included"])
        XCTAssertEqual(result.excludedCount(for: .duplicatePhone), 1)
        XCTAssertEqual(result.excludedCount(for: .missingOrInvalidPhone), 1)
        XCTAssertEqual(result.excludedCount(for: .userExcluded), 1)
        XCTAssertEqual(result.excludedCount(for: .recentlyMessaged), 1)
    }

    func testBuildsGroupSmsPreflightSummary() {
        let selection = GroupSmsTargetSelector.select(
            targets: [
                GroupMessageTarget(sourceRecordId: "one", displayName: "한명", phoneNumber: "01011112222")
            ]
        )
        let recipients = [
            GroupSmsRecipient(
                id: "recipient-1",
                displayName: "한명",
                phoneNumber: "01011112222",
                messageBody: "안내 문자",
                orderIndex: 0,
                plannedDelaySeconds: 4
            )
        ]
        let attachments = [
            GroupSmsAttachment(
                id: "photo-1",
                kind: .photo,
                fileName: "photo.jpg",
                contentType: "image/jpeg",
                byteCount: 1_024,
                orderIndex: 0,
                localReference: "campaign/photo.jpg"
            )
        ]

        let summary = GroupSmsPreflightEvaluator.evaluate(
            selection: selection,
            recipients: recipients,
            messageTemplate: "안내 문자",
            attachments: attachments,
            automationReadiness: .ready
        )

        XCTAssertTrue(summary.canLaunch)
        XCTAssertEqual(summary.estimatedMessageKind, .mms)
        XCTAssertEqual(summary.estimatedDurationSeconds, 4)
        XCTAssertEqual(summary.totalAttachmentBytes, 1_024)
    }

    func testBlocksPreflightForUnreadyAutomationAndInvalidAttachment() {
        let selection = GroupSmsTargetSelector.select(targets: [])
        let invalidAttachment = GroupSmsAttachment(
            id: "invalid",
            kind: .file,
            fileName: "",
            contentType: "",
            byteCount: 0,
            orderIndex: 0,
            localReference: ""
        )

        let summary = GroupSmsPreflightEvaluator.evaluate(
            selection: selection,
            recipients: [],
            messageTemplate: "",
            attachments: [invalidAttachment],
            automationReadiness: .installedNeedsTest
        )

        XCTAssertFalse(summary.canLaunch)
        XCTAssertTrue(summary.blockingReasons.contains(.noRecipients))
        XCTAssertTrue(summary.blockingReasons.contains(.automationNotReady))
        XCTAssertTrue(summary.blockingReasons.contains(.invalidAttachments))
    }

    func testBuildsDenseOCRRowsWithoutMergingAdjacentCustomers() {
        let boxes = [
            ocrBox("김소현", x: 0.10, y: 0.10),
            ocrBox("01012345678", x: 0.34, y: 0.10),
            ocrBox("서울 송파구", x: 0.58, y: 0.10),
            ocrBox("김태영", x: 0.10, y: 0.12),
            ocrBox("01023456789", x: 0.34, y: 0.12),
            ocrBox("서울 성동구", x: 0.58, y: 0.12),
            ocrBox("신나리", x: 0.10, y: 0.14),
            ocrBox("01034567890", x: 0.34, y: 0.14),
            ocrBox("경기 하남시", x: 0.58, y: 0.14)
        ]

        let table = buildOCRTable(from: boxes)

        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows[0][0].text, "김소현")
        XCTAssertEqual(table.rows[1][0].text, "김태영")
        XCTAssertEqual(table.rows[2][0].text, "신나리")
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
            groupSmsCampaigns: [
                GroupSmsCampaign(
                    id: "campaign-1",
                    title: "테스트 문자",
                    customerListId: list.id,
                    targetDescription: "현재 리스트 · 1명",
                    messageTemplate: "{고객명}님",
                    status: .requested,
                    recipients: [
                        GroupSmsRecipient(
                            id: "recipient-1",
                            customerId: customer.id,
                            displayName: customer.name,
                            phoneNumber: cleanPhone(customer.phoneNumber),
                            messageBody: "홍길동님",
                            orderIndex: 0,
                            plannedDelaySeconds: 0
                        )
                    ],
                    requestedAt: now,
                    completedAt: now,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            selectedListId: list.id,
            savedAt: now
        )

        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
        try store.delete()
        XCTAssertNil(try store.load())
    }

    private func ocrBox(_ text: String, x: Double, y: Double) -> RecognizedTextBox {
        RecognizedTextBox(
            text: text,
            x: x,
            y: y,
            width: 0.08,
            height: 0.010,
            confidence: 0.95,
            sourceLevel: "test"
        )
    }
}
