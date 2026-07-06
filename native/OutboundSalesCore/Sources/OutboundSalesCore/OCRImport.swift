import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum OCRHeaderMode: String, Codable, Sendable {
    case auto
    case none
}

public struct RecognizedTextBox: Codable, Equatable, Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let confidence: Double?
    public let sourceLevel: String

    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }
}

public struct OcrCell: Codable, Equatable, Sendable {
    public var text: String
    public var boxes: [RecognizedTextBox]
    public let rowIndex: Int
    public let columnIndex: Int
    public var confidence: Double?
}

public struct OcrTable: Codable, Equatable, Sendable {
    public let rows: [[OcrCell]]
    public let columnCount: Int
    public let warnings: [String]
}

public struct OCRCSVBuildResult: Equatable, Sendable {
    public let csv: String
    public let headers: [String]
    public let dataRows: [[OcrCell]]
    public let headerSource: String
    public let headerDetected: Bool
    public let reason: String
}

public struct OCRImportResult: Equatable, Sendable {
    public let boxes: [RecognizedTextBox]
    public let table: OcrTable
    public let csv: OCRCSVBuildResult
}

public enum OCRImportError: Error, Equatable, Sendable {
    case imageLoadFailed
}

public func recognizeCustomerListImage(
    at url: URL,
    headers: [String] = [],
    headerMode: OCRHeaderMode = .auto,
    languages: [String] = ["ko-KR", "en-US"],
    minConfidence: Float = 0,
    rowThreshold: Double? = nil,
    rotateDegrees: Int = 0
) throws -> OCRImportResult {
    let image = rotateImage(try loadCGImage(from: url), degrees: rotateDegrees)
    let boxes = try recognizeText(in: image, languages: languages, minConfidence: minConfidence)
    let table = buildOCRTable(from: boxes, rowThresholdOverride: rowThreshold)
    let csv = makeOCRCSV(from: table, headers: headers, headerMode: headerMode)
    return OCRImportResult(boxes: boxes, table: table, csv: csv)
}

private func loadCGImage(from url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw OCRImportError.imageLoadFailed
    }
    return image
}

private func rotateImage(_ image: CGImage, degrees: Int) -> CGImage {
    guard degrees != 0 else { return image }

    let width = image.width
    let height = image.height
    let outputWidth = degrees == 90 || degrees == 270 ? height : width
    let outputHeight = degrees == 90 || degrees == 270 ? width : height
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: outputWidth,
        height: outputHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }

    switch degrees {
    case 90:
        context.translateBy(x: CGFloat(outputWidth), y: 0)
        context.rotate(by: .pi / 2)
    case 180:
        context.translateBy(x: CGFloat(outputWidth), y: CGFloat(outputHeight))
        context.rotate(by: .pi)
    case 270:
        context.translateBy(x: 0, y: CGFloat(outputHeight))
        context.rotate(by: -.pi / 2)
    default:
        break
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
}

private func recognizeText(in image: CGImage, languages: [String], minConfidence: Float) throws -> [RecognizedTextBox] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.revision = VNRecognizeTextRequest.currentRevision
    request.recognitionLanguages = languages

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    return (request.results ?? [])
        .compactMap { observation -> RecognizedTextBox? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !text.isEmpty, candidate.confidence >= minConfidence else { return nil }

            let box = observation.boundingBox
            return RecognizedTextBox(
                text: text,
                x: Double(box.minX),
                y: Double(1 - box.maxY),
                width: Double(box.width),
                height: Double(box.height),
                confidence: Double(candidate.confidence),
                sourceLevel: "line"
            )
        }
        .sorted {
            if abs($0.centerY - $1.centerY) > 0.01 {
                return $0.centerY < $1.centerY
            }
            return $0.x < $1.x
        }
}

public func buildOCRTable(from boxes: [RecognizedTextBox], rowThresholdOverride: Double? = nil) -> OcrTable {
    guard !boxes.isEmpty else {
        return OcrTable(rows: [], columnCount: 0, warnings: ["OCR 텍스트가 없습니다."])
    }

    let medianHeight = median(boxes.map(\.height))
    let rowThreshold = rowThresholdOverride ?? max(medianHeight * 1.7, 0.035)
    let columnThreshold = max(median(boxes.map(\.width)) * 0.8, 0.045)
    let rowGroups = cluster(boxes.sorted { $0.centerY < $1.centerY }, key: \.centerY, threshold: rowThreshold)
        .map { $0.sorted { $0.x < $1.x } }
    let columnCenters = cluster(boxes.sorted { $0.x < $1.x }, key: \.x, threshold: columnThreshold)
        .map { group in average(group.map(\.x)) }
        .sorted()

    var warnings: [String] = []
    if columnCenters.isEmpty {
        warnings.append("열 후보를 찾지 못했습니다.")
    }

    let tableRows = rowGroups.enumerated().map { rowIndex, rowBoxes in
        var cellsByColumn: [Int: [RecognizedTextBox]] = [:]
        for box in rowBoxes {
            let columnIndex = nearestIndex(to: box.x, in: columnCenters) ?? 0
            cellsByColumn[columnIndex, default: []].append(box)
        }
        if cellsByColumn.count != columnCenters.count {
            warnings.append("\(rowIndex + 1)행의 인식된 셀 수가 추정 열 수와 다릅니다.")
        }
        return (0..<columnCenters.count).map { columnIndex in
            let cellBoxes = (cellsByColumn[columnIndex] ?? []).sorted { $0.x < $1.x }
            return OcrCell(
                text: cellBoxes.map(\.text).joined(separator: " "),
                boxes: cellBoxes,
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                confidence: weightedConfidence(for: cellBoxes)
            )
        }
    }

    return OcrTable(rows: tableRows, columnCount: columnCenters.count, warnings: warnings)
}

public func makeOCRCSV(from table: OcrTable, headers providedHeaders: [String], headerMode: OCRHeaderMode) -> OCRCSVBuildResult {
    let columnCount = max(table.columnCount, providedHeaders.count)
    let headers: [String]
    let dataRows: [[OcrCell]]
    let headerSource: String
    let headerDetected: Bool
    let reason: String

    if !providedHeaders.isEmpty {
        headers = makeOCRHeaders(columnCount: columnCount, providedHeaders: providedHeaders)
        dataRows = table.rows
        headerSource = "manual"
        headerDetected = false
        reason = "사용자 지정 헤더를 사용했습니다."
    } else if headerMode == .auto {
        let decision = detectHeaderRow(in: table)
        if decision.isHeader, let firstRow = table.rows.first {
            headers = makeOCRHeaders(columnCount: columnCount, providedHeaders: firstRow.map(\.text))
            dataRows = Array(table.rows.dropFirst())
            headerSource = "detected-first-row"
            headerDetected = true
            reason = decision.reason
        } else {
            headers = makeOCRHeaders(columnCount: columnCount, providedHeaders: [])
            dataRows = table.rows
            headerSource = "generated"
            headerDetected = false
            reason = decision.reason
        }
    } else {
        headers = makeOCRHeaders(columnCount: columnCount, providedHeaders: [])
        dataRows = table.rows
        headerSource = "generated"
        headerDetected = false
        reason = "첫 행 헤더 판정을 하지 않았습니다."
    }

    let headerRow = headers.map(escapeCSVField).joined(separator: ",")
    let csvRows = dataRows.map { row in
        (0..<columnCount).map { index in
            escapeCSVField(index < row.count ? row[index].text : "")
        }.joined(separator: ",")
    }

    return OCRCSVBuildResult(
        csv: ([headerRow] + csvRows).joined(separator: "\n") + "\n",
        headers: headers,
        dataRows: dataRows,
        headerSource: headerSource,
        headerDetected: headerDetected,
        reason: reason
    )
}

private struct RowProfile {
    let filledRatio: Double
    let digitRatio: Double
    let averageLength: Double
    let longCellRatio: Double
}

private func detectHeaderRow(in table: OcrTable) -> (isHeader: Bool, reason: String) {
    guard table.rows.count >= 3, table.columnCount > 0 else {
        return (false, "행이 부족해 첫 행 헤더를 자동 판정하지 않았습니다.")
    }
    let firstProfile = profile(for: table.rows[0], columnCount: table.columnCount)
    let restProfiles = table.rows.dropFirst().map { profile(for: $0, columnCount: table.columnCount) }
    let restAverage = averageProfile(restProfiles)
    let restDistance = average(restProfiles.map { profileDistance($0, restAverage) })
    let firstDistance = profileDistance(firstProfile, restAverage)
    let digitSignal = firstProfile.digitRatio < 0.18 && restAverage.digitRatio - firstProfile.digitRatio > 0.18
    let lengthSignal = firstProfile.averageLength < restAverage.averageLength * 0.65 && restAverage.longCellRatio > firstProfile.longCellRatio + 0.15
    let outlierSignal = firstDistance > max(0.34, restDistance * 2.2)
    let enoughFilledCells = firstProfile.filledRatio >= min(0.6, max(0.25, restAverage.filledRatio * 0.55))
    if enoughFilledCells && (digitSignal || lengthSignal || outlierSignal) {
        return (true, String(format: "첫 행의 형태가 나머지 행과 다릅니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
    }
    return (false, String(format: "첫 행을 데이터로 유지했습니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
}

private func profile(for row: [OcrCell], columnCount: Int) -> RowProfile {
    let texts = row.map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let filledTexts = texts.filter { !$0.isEmpty }
    let joined = filledTexts.joined()
    let digitCount = joined.filter(\.isNumber).count
    let characterCount = joined.count
    return RowProfile(
        filledRatio: columnCount == 0 ? 0 : Double(filledTexts.count) / Double(columnCount),
        digitRatio: characterCount == 0 ? 0 : Double(digitCount) / Double(characterCount),
        averageLength: filledTexts.isEmpty ? 0 : Double(filledTexts.map(\.count).reduce(0, +)) / Double(filledTexts.count),
        longCellRatio: filledTexts.isEmpty ? 0 : Double(filledTexts.filter { $0.count >= 14 }.count) / Double(filledTexts.count)
    )
}

private func averageProfile(_ profiles: [RowProfile]) -> RowProfile {
    guard !profiles.isEmpty else { return RowProfile(filledRatio: 0, digitRatio: 0, averageLength: 0, longCellRatio: 0) }
    return RowProfile(
        filledRatio: average(profiles.map(\.filledRatio)),
        digitRatio: average(profiles.map(\.digitRatio)),
        averageLength: average(profiles.map(\.averageLength)),
        longCellRatio: average(profiles.map(\.longCellRatio))
    )
}

private func profileDistance(_ left: RowProfile, _ right: RowProfile) -> Double {
    let values = [
        left.filledRatio - right.filledRatio,
        left.digitRatio - right.digitRatio,
        (left.averageLength - right.averageLength) / 30,
        left.longCellRatio - right.longCellRatio
    ]
    return sqrt(values.map { $0 * $0 }.reduce(0, +))
}

private func makeOCRHeaders(columnCount: Int, providedHeaders: [String]) -> [String] {
    (0..<columnCount).map { index in
        let header = index < providedHeaders.count ? providedHeaders[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return header.isEmpty ? "열\(index + 1)" : header
    }
}

private func cluster<T>(_ values: [T], key: KeyPath<T, Double>, threshold: Double) -> [[T]] {
    var groups: [[T]] = []
    var current: [T] = []
    var currentCenter: Double?
    for value in values {
        let number = value[keyPath: key]
        guard let center = currentCenter else {
            current = [value]
            currentCenter = number
            continue
        }
        if abs(number - center) <= threshold {
            current.append(value)
            currentCenter = average(current.map { $0[keyPath: key] })
        } else {
            groups.append(current)
            current = [value]
            currentCenter = number
        }
    }
    if !current.isEmpty { groups.append(current) }
    return groups
}

private func nearestIndex(to value: Double, in values: [Double]) -> Int? {
    values.enumerated().min { abs($0.element - value) < abs($1.element - value) }?.offset
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

private func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

private func weightedConfidence(for boxes: [RecognizedTextBox]) -> Double? {
    let weighted = boxes.compactMap { box -> (Double, Double)? in
        guard let confidence = box.confidence else { return nil }
        return (confidence, Double(max(box.text.count, 1)))
    }
    guard !weighted.isEmpty else { return nil }
    let totalWeight = weighted.reduce(0) { $0 + $1.1 }
    return weighted.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
}
