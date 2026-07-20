import Foundation

public struct ParsedCSV: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String]]
    public var mapping: FieldMapping

    public init(headers: [String], rows: [[String]], mapping: FieldMapping) {
        self.headers = headers
        self.rows = rows
        self.mapping = mapping
    }
}

public enum CSVImportError: Error, Equatable, Sendable {
    case empty
    case unsupportedEncoding
}

public func decodeCSVText(data: Data) throws -> String {
    if let utf8 = String(data: data, encoding: .utf8) {
        return removeByteOrderMark(from: utf8)
    }

    if hasUTF16ByteOrderMark(data) {
        for encoding in [String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: encoding) {
                return removeByteOrderMark(from: text)
            }
        }
    }

    for encoding in [koreanEncoding(.dosKorean), koreanEncoding(.EUC_KR)] {
        if let text = String(data: data, encoding: encoding) {
            return removeByteOrderMark(from: text)
        }
    }

    for encoding in [String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian] {
        if let text = String(data: data, encoding: encoding) {
            return removeByteOrderMark(from: text)
        }
    }

    throw CSVImportError.unsupportedEncoding
}

public func parseCSV(_ text: String, firstRowIsHeader: Bool = true) throws -> ParsedCSV {
    let rows = parseCSVRows(text)
        .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    guard !rows.isEmpty else { throw CSVImportError.empty }
    let columnCount = rows.map(\.count).max() ?? 0
    let headers: [String]
    let dataRows: [[String]]
    if firstRowIsHeader, let firstRow = rows.first {
        headers = firstRow
        dataRows = Array(rows.dropFirst())
    } else {
        headers = (0..<columnCount).map { "열\($0 + 1)" }
        dataRows = rows
    }
    return ParsedCSV(headers: headers, rows: dataRows, mapping: detectMapping(headers: headers))
}

public func customersFromCSV(_ parsed: ParsedCSV, customerListId: String, now: Date = Date(), idGenerator: () -> String = { UUID().uuidString }) -> [Customer] {
    parsed.rows.map { row in
        let ownedAddress = fieldValue(.ownedAddress, row: row, mapping: parsed.mapping)
        let parcelAddress = fieldValue(.parcelAddress, row: row, mapping: parsed.mapping)
        var additionalAddresses: [CustomerAddress] = []
        if !ownedAddress.isEmpty {
            additionalAddresses.append(CustomerAddress(id: idGenerator(), label: "소유지", value: ownedAddress, kind: .ownedProperty))
        }
        if !parcelAddress.isEmpty {
            additionalAddresses.append(CustomerAddress(id: idGenerator(), label: "지번", value: parcelAddress, kind: .parcel))
        }
        return Customer(
            id: idGenerator(),
            customerListId: customerListId,
            name: fieldValue(.name, row: row, mapping: parsed.mapping),
            phoneNumber: fieldValue(.phoneNumber, row: row, mapping: parsed.mapping),
            address: fieldValue(.address, row: row, mapping: parsed.mapping),
            birthDate: parseBirthDate(fieldValue(.birthDate, row: row, mapping: parsed.mapping)),
            notes: fieldValue(.notes, row: row, mapping: parsed.mapping),
            additionalAddresses: additionalAddresses.isEmpty ? nil : additionalAddresses,
            latitude: parseCoordinate(fieldValue(.latitude, row: row, mapping: parsed.mapping), kind: .latitude),
            longitude: parseCoordinate(fieldValue(.longitude, row: row, mapping: parsed.mapping), kind: .longitude),
            coordinateSource: coordinateSource(row: row, mapping: parsed.mapping),
            region: extractRegion(fieldValue(.address, row: row, mapping: parsed.mapping)),
            status: .open,
            createdAt: now,
            updatedAt: now
        )
    }
}

func fieldValue(_ field: FieldKey, row: [String], mapping: FieldMapping) -> String {
    guard let index = mapping[field], index < row.count else { return "" }
    return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
}

func coordinateSource(row: [String], mapping: FieldMapping) -> CoordinateSource? {
    let lat = fieldValue(.latitude, row: row, mapping: mapping)
    let lng = fieldValue(.longitude, row: row, mapping: mapping)
    return lat.isEmpty && lng.isEmpty ? nil : .csv
}

public func parseCSVRows(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var index = text.startIndex

    while index < text.endIndex {
        let character = text[index]
        if character == "\"" {
            let nextIndex = text.index(after: index)
            if inQuotes, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                field.append("\"")
                index = text.index(after: nextIndex)
                continue
            }
            inQuotes.toggle()
        } else if character == "," && !inQuotes {
            row.append(field)
            field = ""
        } else if (character == "\n" || character == "\r") && !inQuotes {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
            let nextIndex = text.index(after: index)
            if character == "\r", nextIndex < text.endIndex, text[nextIndex] == "\n" {
                index = text.index(after: nextIndex)
                continue
            }
        } else {
            field.append(character)
        }
        index = text.index(after: index)
    }

    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }
    return rows
}

public func makeCSV(rows: [[String]]) -> String {
    rows.map { row in row.map(escapeCSVField).joined(separator: ",") }.joined(separator: "\n") + "\n"
}

func escapeCSVField(_ value: String) -> String {
    let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return needsQuotes ? "\"\(escaped)\"" : escaped
}

private func koreanEncoding(_ encoding: CFStringEncodings) -> String.Encoding {
    String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
}

private func hasUTF16ByteOrderMark(_ data: Data) -> Bool {
    data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
}

private func removeByteOrderMark(from text: String) -> String {
    text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
}
