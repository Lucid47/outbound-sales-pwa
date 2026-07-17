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

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(
            queryItems["x-success"],
            "com.lucid47.outboundsales:/group-sms/complete?campaignId=campaign-1"
        )
        XCTAssertEqual(
            queryItems["x-cancel"],
            "com.lucid47.outboundsales:/group-sms/cancel?campaignId=campaign-1"
        )
        XCTAssertEqual(
            queryItems["x-error"],
            "com.lucid47.outboundsales:/group-sms/error?campaignId=campaign-1"
        )

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

    func testBuildsElevenOCRColumnsWithoutLegacyEightColumnBias() {
        let headers = (0..<11).map { columnIndex in
            ocrBox("헤더\(columnIndex + 1)", x: 0.03 + (Double(columnIndex) * 0.085), y: 0.04, width: 0.045)
        }
        let body = (0..<4).flatMap { rowIndex in
            (0..<11).map { columnIndex in
                ocrBox(
                    "값\(rowIndex + 1)-\(columnIndex + 1)",
                    x: 0.03 + (Double(columnIndex) * 0.085),
                    y: 0.12 + (Double(rowIndex) * 0.05),
                    width: 0.045
                )
            }
        }

        let table = buildOCRTable(from: headers + body)

        XCTAssertEqual(table.columnCount, 11)
        XCTAssertEqual(table.rows.count, 5)
        XCTAssertEqual(table.rows[0].map(\.text), (1...11).map { "헤더\($0)" })
        XCTAssertEqual(table.rows[4].last?.text, "값4-11")
    }

    func testKeepsOverlappingMultilineNoteWithPreviousCustomer() {
        let boxes = [
            ocrBox("담당자", x: 0.08, y: 0.03, width: 0.05),
            ocrBox("성명", x: 0.36, y: 0.03, width: 0.05),
            ocrBox("비고", x: 0.72, y: 0.03, width: 0.05),
            ocrBox("박민아", x: 0.08, y: 0.10, width: 0.05),
            ocrBox("박철성", x: 0.36, y: 0.10, width: 0.05),
            ocrBox("투자 목적 / 본인에게 연락하지 말 것", x: 0.72, y: 0.10, width: 0.22, height: 0.035),
            ocrBox("부인 장윤진이 관리", x: 0.72, y: 0.123, width: 0.15, height: 0.024),
            ocrBox("박민아", x: 0.08, y: 0.14, width: 0.05),
            ocrBox("김학재", x: 0.36, y: 0.14, width: 0.05),
            ocrBox("박민아", x: 0.08, y: 0.19, width: 0.05),
            ocrBox("고재준", x: 0.36, y: 0.19, width: 0.05)
        ]

        let table = buildOCRTable(from: boxes)

        XCTAssertEqual(table.rows.count, 4)
        XCTAssertEqual(table.rows[1][2].text, "투자 목적 / 본인에게 연락하지 말 것 부인 장윤진이 관리")
        XCTAssertEqual(table.rows[2][2].text, "")
    }

    func testDetectsSyntheticPrintedTableGrid() throws {
        let width = 600
        let height = 420
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return XCTFail("합성 표 컨텍스트를 만들지 못했습니다.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
        context.setLineWidth(2)
        for x in [40, 150, 280, 430, 560] {
            context.move(to: CGPoint(x: x, y: 35))
            context.addLine(to: CGPoint(x: x, y: 385))
        }
        for y in [35, 105, 175, 245, 315, 385] {
            context.move(to: CGPoint(x: 40, y: y))
            context.addLine(to: CGPoint(x: 560, y: y))
        }
        context.strokePath()
        guard let image = context.makeImage() else {
            return XCTFail("합성 표 이미지를 만들지 못했습니다.")
        }

        let grid = detectOCRTableGrid(in: image, maximumDimension: 600)

        XCTAssertNotNil(grid)
        XCTAssertEqual(grid?.columnCount, 4)
        XCTAssertEqual(grid?.rowCount, 5)
        XCTAssertGreaterThanOrEqual(grid?.confidence ?? 0, 0.45)
    }

    func testNormalizesRepeatedColumnsAcrossPerspectiveWarp() {
        var boxes: [RecognizedTextBox] = []
        for row in 0..<10 {
            let anchorY = 0.10 + (Double(row) * 0.055)
            boxes.append(ocrBox("\(row + 1) 고객", x: 0.10, y: anchorY))
            boxes.append(ocrBox("010000000\(row)", x: 0.32, y: anchorY + (Double(row) * 0.0015)))
            boxes.append(ocrBox("\(row + 1)00,000", x: 0.68, y: anchorY + (Double(row) * 0.003)))
        }

        let normalized = normalizeRepeatedColumnRows(boxes)
        let groups = Dictionary(grouping: normalized) { Int(($0.x * 100).rounded()) }
        let anchorCenters = groups[10]!.sorted { $0.centerY < $1.centerY }.map(\.centerY)
        let amountCenters = groups[68]!.sorted { $0.centerY < $1.centerY }.map(\.centerY)

        XCTAssertEqual(anchorCenters.count, 10)
        XCTAssertEqual(amountCenters.count, 10)
        for (anchor, amount) in zip(anchorCenters, amountCenters) {
            XCTAssertEqual(anchor, amount, accuracy: 0.000_001)
        }
    }

    func testRestoresReverseReadingDirectionFromDateAndNameColumns() {
        let names = ["가나다", "라마바", "사아자", "차카타", "파하가", "나라다", "마바사", "아자차"]
        let logicalRows = (1...8).map { rowIndex in
            [
                names[rowIndex - 1],
                "0100000000\(rowIndex)",
                "상품 이름 \(rowIndex)",
                "정상",
                "2026.7.\(rowIndex)",
                "\(rowIndex * 10),000"
            ]
        }
        let reversedRows = logicalRows.reversed().enumerated().map { rowIndex, texts in
            texts.reversed().enumerated().map { columnIndex, text in
                OcrCell(
                    text: text,
                    boxes: [],
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    confidence: 1
                )
            }
        }
        let table = OcrTable(rows: reversedRows, columnCount: 6, warnings: [])

        let normalized = normalizeOCRTableReadingDirection(table)

        XCTAssertEqual(normalized.rows[0][0].text, "가나다")
        XCTAssertEqual(normalized.rows[7][0].text, "아자차")
        XCTAssertEqual(normalized.rows[0][4].text, "2026.7.1")
        XCTAssertTrue(normalized.warnings.contains { $0.contains("180도 역방향") })
    }

    func testKeepsBodyLikeFirstRowWhenAutomaticHeaderDetectionIsEnabled() {
        let sourceRows = [
            ["첫고객", "01012345678", "긴 상품 설명과 추가 인식 문자열", "정상", "2026.7.1", "1,234,000"],
            ["둘고객", "01023456789", "상품", "완납", "2026.7.2", "234,000"],
            ["셋고객", "01034567890", "상품", "정상", "2026.7.3", "345,000"]
        ]
        let rows = sourceRows.enumerated().map { rowIndex, texts in
            texts.enumerated().map { columnIndex, text in
                OcrCell(
                    text: text,
                    boxes: [],
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    confidence: 1
                )
            }
        }
        let table = OcrTable(rows: rows, columnCount: 6, warnings: [])

        let csv = makeOCRCSV(from: table, headers: [], headerMode: .auto)

        XCTAssertFalse(csv.headerDetected)
        XCTAssertEqual(csv.headerSource, "generated")
        XCTAssertEqual(csv.dataRows.count, 3)
        XCTAssertEqual(csv.dataRows[0][0].text, "첫고객")
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
            contactRegistrationStatus: .registered,
            contactRegistrationOwnership: .createdByApp,
            contactIdentifier: "contact-1",
            contactRegisteredAt: now,
            contactRegisteredName: "#홍길동",
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
                    scheduledAt: now.addingTimeInterval(3_600),
                    scheduleNotificationIdentifier: "group-sms.schedule.campaign-1",
                    scheduleDeviceIdentifier: "device-1",
                    requestedAt: now,
                    completedAt: now,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            contactExportBatches: [
                ContactExportBatch(
                    id: "batch-1",
                    customerListId: list.id,
                    installationIdentifier: "installation-1",
                    groupIdentifier: "group-1",
                    groupName: list.name,
                    groupCreatedByApp: true,
                    records: [
                        ContactExportRecord(
                            customerId: customer.id,
                            contactIdentifier: "contact-1",
                            registeredName: "#홍길동",
                            normalizedPhone: "01012345678",
                            ownership: .createdByApp
                        )
                    ],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            dashboardSettings: DashboardHeatmapSettings(
                paletteFamily: .green,
                showsLegend: false,
                statusCount: 7,
                updatedAt: now
            ),
            managementPeriods: [
                ManagementPeriod(
                    id: "period-1",
                    name: "2026년 하반기",
                    startDate: now,
                    endDate: now.addingTimeInterval(86_400 * 30),
                    customerListIds: [list.id],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            activityEvents: [
                CustomerActivityEvent(
                    id: "activity-1",
                    kind: .customerCreated,
                    occurredAt: now,
                    customerListId: list.id,
                    customerId: customer.id,
                    title: "고객 추가",
                    createdAt: now
                )
            ],
            stageChangeLogs: [
                CustomerStageChangeLog(
                    id: "stage-log-1",
                    customerListId: list.id,
                    customerId: customer.id,
                    previousStageId: nil,
                    nextStageId: "dashboard-status-1",
                    changedAt: now
                )
            ],
            deletionTombstones: [
                DeletedRecordTombstone(kind: .customerList, recordId: "deleted-list", deletedAt: now)
            ],
            selectedListId: list.id,
            savedAt: now
        )

        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testDecodesSnapshotBeforeContactOwnershipTracking() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = NativeAppSnapshot(
            customerLists: [
                CustomerList(
                    id: "list-1",
                    name: "기존 리스트",
                    companyName: "기존 리스트",
                    sourceFileName: "legacy.csv",
                    importedAt: now,
                    createdAt: now,
                    updatedAt: now
                )
            ],
            customers: [
                Customer(
                    id: "customer-1",
                    customerListId: "list-1",
                    name: "홍길동",
                    phoneNumber: "010-1234-5678",
                    address: "서울",
                    notes: "",
                    contactRegistrationStatus: .registered,
                    contactRegistrationOwnership: .createdByApp,
                    contactIdentifier: "contact-1",
                    createdAt: now,
                    updatedAt: now
                )
            ],
            contactExportBatches: [
                ContactExportBatch(
                    id: "batch-1",
                    customerListId: "list-1",
                    installationIdentifier: "installation-1",
                    groupIdentifier: "group-1",
                    groupName: "테스트",
                    groupCreatedByApp: true,
                    records: [],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            selectedListId: nil,
            savedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "contactExportBatches")
        object.removeValue(forKey: "dashboardSettings")
        object.removeValue(forKey: "managementPeriods")
        object.removeValue(forKey: "activityEvents")
        object.removeValue(forKey: "stageChangeLogs")
        object.removeValue(forKey: "deletionTombstones")
        if var lists = object["customerLists"] as? [[String: Any]], !lists.isEmpty {
            lists[0].removeValue(forKey: "archivedAt")
            object["customerLists"] = lists
        }
        if var customers = object["customers"] as? [[String: Any]], !customers.isEmpty {
            customers[0].removeValue(forKey: "contactRegistrationOwnership")
            object["customers"] = customers
        }
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NativeAppSnapshot.self, from: legacyData)

        XCTAssertTrue(decoded.contactExportBatches.isEmpty)
        XCTAssertNil(decoded.customers.first?.contactRegistrationOwnership)
        XCTAssertEqual(decoded.customers.first?.contactRegistrationStatus, .registered)
        XCTAssertEqual(decoded.dashboardSettings.paletteFamily, .blue)
        XCTAssertTrue(decoded.dashboardSettings.showsLegend)
        XCTAssertEqual(decoded.dashboardSettings.statusCount, 5)
        XCTAssertNil(decoded.customerLists.first?.archivedAt)
        XCTAssertTrue(decoded.managementPeriods.isEmpty)
        XCTAssertTrue(decoded.activityEvents.isEmpty)
        XCTAssertTrue(decoded.stageChangeLogs.isEmpty)
        XCTAssertTrue(decoded.deletionTombstones.isEmpty)
    }

    func testManagementPeriodUsesInclusiveDatesAndOptionalCustomerScope() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30)))
        let lastMoment = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 59)))
        let outside = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let period = ManagementPeriod(
            id: "period-1",
            name: "3분기 관리",
            startDate: start,
            endDate: end,
            customerListIds: ["list-1"],
            customerIds: ["customer-1"],
            createdAt: now,
            updatedAt: now
        )
        let includedCustomer = Customer(
            id: "customer-1",
            customerListId: "list-1",
            name: "포함 고객",
            phoneNumber: "",
            address: "",
            notes: "",
            createdAt: now,
            updatedAt: now
        )
        let excludedCustomer = Customer(
            id: "customer-2",
            customerListId: "list-1",
            name: "제외 고객",
            phoneNumber: "",
            address: "",
            notes: "",
            createdAt: now,
            updatedAt: now
        )

        XCTAssertTrue(period.contains(start, calendar: calendar))
        XCTAssertTrue(period.contains(lastMoment, calendar: calendar))
        XCTAssertFalse(period.contains(outside, calendar: calendar))
        XCTAssertTrue(period.includes(customer: includedCustomer))
        XCTAssertFalse(period.includes(customer: excludedCustomer))
    }

    private func ocrBox(
        _ text: String,
        x: Double,
        y: Double,
        width: Double = 0.08,
        height: Double = 0.010
    ) -> RecognizedTextBox {
        RecognizedTextBox(
            text: text,
            x: x,
            y: y,
            width: width,
            height: height,
            confidence: 0.95,
            sourceLevel: "test"
        )
    }
}
