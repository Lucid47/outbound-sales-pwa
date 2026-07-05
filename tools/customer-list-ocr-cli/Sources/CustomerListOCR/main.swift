import CoreGraphics
import Foundation
import ImageIO
import Vision

struct CLIOptions {
    var imagePath: String?
    var outputDirectory: String?
    var headers: [String] = []
    var headerMode: HeaderMode = .auto
    var languages: [String] = ["ko-KR", "en-US"]
    var minConfidence: Float = 0
    var rowThreshold: Double?
    var showHelp = false
}

enum HeaderMode: String, Codable {
    case auto
    case none
}

struct RecognizedTextBox: Codable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Double?
    let sourceLevel: String

    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
}

struct OcrCell: Codable {
    var text: String
    var boxes: [RecognizedTextBox]
    let rowIndex: Int
    let columnIndex: Int
    var confidence: Double?
}

struct OcrTable: Codable {
    let rows: [[OcrCell]]
    let columnCount: Int
    let warnings: [String]
}

struct RunSummary: Codable {
    let imagePath: String
    let outputDirectory: String
    let boxCount: Int
    let rowCount: Int
    let columnCount: Int
    let csvHeaderSource: String
    let headerDetected: Bool
    let csvDataRowCount: Int
    let warnings: [String]
}

struct CSVBuildResult {
    let csv: String
    let headers: [String]
    let dataRows: [[OcrCell]]
    let headerSource: String
    let headerDetected: Bool
    let reason: String
}

struct RowProfile {
    let filledRatio: Double
    let digitRatio: Double
    let averageLength: Double
    let longCellRatio: Double
}

enum CLIError: Error, CustomStringConvertible {
    case missingImagePath
    case invalidOption(String)
    case imageLoadFailed(String)

    var description: String {
        switch self {
        case .missingImagePath:
            return "이미지 파일 경로가 필요합니다."
        case .invalidOption(let message):
            return message
        case .imageLoadFailed(let path):
            return "이미지를 열 수 없습니다: \(path)"
        }
    }
}

func printHelp() {
    print("""
    Customer List OCR CLI

    Usage:
      customer-list-ocr <image-path> [options]

    Options:
      --out-dir <path>              출력 폴더. 기본값: ./ocr-output/<image-name>-<timestamp>
      --headers "열A,열B,열C"          CSV 헤더. 생략하면 열1, 열2... 사용
      --header-mode <auto|none>     첫 행 헤더 자동 판정. 기본값: auto
      --languages "ko-KR,en-US"     OCR 언어. 기본값: ko-KR,en-US
      --min-confidence <number>     낮은 신뢰도 텍스트 제외 기준. 기본값: 0
      --row-threshold <number>      행 묶기 기준. 촘촘한 표는 0.01~0.018 권장
      --help                        도움말
    """)
}

func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--help", "-h":
            options.showHelp = true
            index += 1
        case "--out-dir":
            guard index + 1 < arguments.count else {
                throw CLIError.invalidOption("--out-dir 값이 필요합니다.")
            }
            options.outputDirectory = arguments[index + 1]
            index += 2
        case "--headers":
            guard index + 1 < arguments.count else {
                throw CLIError.invalidOption("--headers 값이 필요합니다.")
            }
            options.headers = splitCSVLikeArgument(arguments[index + 1])
            index += 2
        case "--header-mode":
            guard index + 1 < arguments.count else {
                throw CLIError.invalidOption("--header-mode 값이 필요합니다.")
            }
            guard let mode = HeaderMode(rawValue: arguments[index + 1]) else {
                throw CLIError.invalidOption("--header-mode는 auto 또는 none만 사용할 수 있습니다.")
            }
            options.headerMode = mode
            index += 2
        case "--languages":
            guard index + 1 < arguments.count else {
                throw CLIError.invalidOption("--languages 값이 필요합니다.")
            }
            options.languages = splitCSVLikeArgument(arguments[index + 1])
            index += 2
        case "--min-confidence":
            guard index + 1 < arguments.count, let value = Float(arguments[index + 1]) else {
                throw CLIError.invalidOption("--min-confidence 숫자 값이 필요합니다.")
            }
            options.minConfidence = value
            index += 2
        case "--row-threshold":
            guard index + 1 < arguments.count, let value = Double(arguments[index + 1]), value > 0 else {
                throw CLIError.invalidOption("--row-threshold 양수 값이 필요합니다.")
            }
            options.rowThreshold = value
            index += 2
        default:
            if argument.hasPrefix("-") {
                throw CLIError.invalidOption("알 수 없는 옵션입니다: \(argument)")
            }
            if options.imagePath != nil {
                throw CLIError.invalidOption("이미지 파일은 하나만 지정할 수 있습니다.")
            }
            options.imagePath = argument
            index += 1
        }
    }

    return options
}

func splitCSVLikeArgument(_ value: String) -> [String] {
    value
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func loadCGImage(from path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CLIError.imageLoadFailed(path)
    }
    return image
}

func recognizeText(in image: CGImage, languages: [String], minConfidence: Float) throws -> [RecognizedTextBox] {
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
            guard !text.isEmpty else { return nil }
            guard candidate.confidence >= minConfidence else { return nil }

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

func buildTable(from boxes: [RecognizedTextBox], rowThresholdOverride: Double? = nil) -> OcrTable {
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

    var tableRows: [[OcrCell]] = []

    for (rowIndex, rowBoxes) in rowGroups.enumerated() {
        var cellsByColumn: [Int: [RecognizedTextBox]] = [:]

        for box in rowBoxes {
            let columnIndex = nearestIndex(to: box.x, in: columnCenters) ?? 0
            cellsByColumn[columnIndex, default: []].append(box)
        }

        if cellsByColumn.count != columnCenters.count {
            warnings.append("\(rowIndex + 1)행의 인식된 셀 수가 추정 열 수와 다릅니다.")
        }

        let row = (0..<columnCenters.count).map { columnIndex in
            let cellBoxes = (cellsByColumn[columnIndex] ?? []).sorted { $0.x < $1.x }
            let text = cellBoxes.map(\.text).joined(separator: " ")
            return OcrCell(
                text: text,
                boxes: cellBoxes,
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                confidence: weightedConfidence(for: cellBoxes)
            )
        }
        tableRows.append(row)
    }

    return OcrTable(rows: tableRows, columnCount: columnCenters.count, warnings: warnings)
}

func cluster<T>(_ values: [T], key: KeyPath<T, Double>, threshold: Double) -> [[T]] {
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

    if !current.isEmpty {
        groups.append(current)
    }
    return groups
}

func nearestIndex(to value: Double, in values: [Double]) -> Int? {
    values.enumerated().min { left, right in
        abs(left.element - value) < abs(right.element - value)
    }?.offset
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

func weightedConfidence(for boxes: [RecognizedTextBox]) -> Double? {
    let weighted = boxes.compactMap { box -> (Double, Double)? in
        guard let confidence = box.confidence else { return nil }
        return (confidence, Double(max(box.text.count, 1)))
    }
    guard !weighted.isEmpty else { return nil }
    let totalWeight = weighted.reduce(0) { $0 + $1.1 }
    return weighted.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
}

func makeCSV(from table: OcrTable, headers providedHeaders: [String], headerMode: HeaderMode) -> CSVBuildResult {
    let columnCount = max(table.columnCount, providedHeaders.count)

    let headers: [String]
    let dataRows: [[OcrCell]]
    let headerSource: String
    let headerDetected: Bool
    let reason: String

    if !providedHeaders.isEmpty {
        headers = makeHeaders(columnCount: columnCount, providedHeaders: providedHeaders)
        dataRows = table.rows
        headerSource = "manual"
        headerDetected = false
        reason = "--headers 옵션을 사용했습니다."
    } else if headerMode == .auto {
        let decision = detectHeaderRow(in: table)
        if decision.isHeader, let firstRow = table.rows.first {
            headers = makeHeaders(columnCount: columnCount, providedHeaders: firstRow.map(\.text))
            dataRows = Array(table.rows.dropFirst())
            headerSource = "detected-first-row"
            headerDetected = true
            reason = decision.reason
        } else {
            headers = makeHeaders(columnCount: columnCount, providedHeaders: [])
            dataRows = table.rows
            headerSource = "generated"
            headerDetected = false
            reason = decision.reason
        }
    } else {
        headers = makeHeaders(columnCount: columnCount, providedHeaders: [])
        dataRows = table.rows
        headerSource = "generated"
        headerDetected = false
        reason = "--header-mode none을 사용했습니다."
    }

    let headerRow = headers.map(escapeCSVField).joined(separator: ",")
    let csvDataRows = dataRows.map { row in
        (0..<columnCount).map { index in
            let value = index < row.count ? row[index].text : ""
            return escapeCSVField(value)
        }.joined(separator: ",")
    }

    return CSVBuildResult(
        csv: ([headerRow] + csvDataRows).joined(separator: "\n") + "\n",
        headers: headers,
        dataRows: dataRows,
        headerSource: headerSource,
        headerDetected: headerDetected,
        reason: reason
    )
}

func makeHeaders(columnCount: Int, providedHeaders: [String]) -> [String] {
    (0..<columnCount).map { index in
        let header = index < providedHeaders.count
            ? providedHeaders[index].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return header.isEmpty ? "열\(index + 1)" : header
    }
}

func detectHeaderRow(in table: OcrTable) -> (isHeader: Bool, reason: String) {
    guard table.rows.count >= 3, table.columnCount > 0 else {
        return (false, "행이 부족해 첫 행 헤더를 자동 판정하지 않았습니다.")
    }

    let firstProfile = profile(for: table.rows[0], columnCount: table.columnCount)
    let restProfiles = table.rows.dropFirst().map { profile(for: $0, columnCount: table.columnCount) }
    let restAverage = averageProfile(restProfiles)
    let restDistances = restProfiles.map { profileDistance($0, restAverage) }
    let firstDistance = profileDistance(firstProfile, restAverage)
    let restDistance = average(restDistances)

    let digitSignal = firstProfile.digitRatio < 0.18 && restAverage.digitRatio - firstProfile.digitRatio > 0.18
    let lengthSignal = firstProfile.averageLength < restAverage.averageLength * 0.65 && restAverage.longCellRatio > firstProfile.longCellRatio + 0.15
    let outlierSignal = firstDistance > max(0.34, restDistance * 2.2)
    let enoughFilledCells = firstProfile.filledRatio >= min(0.6, max(0.25, restAverage.filledRatio * 0.55))

    if enoughFilledCells && (digitSignal || lengthSignal || outlierSignal) {
        return (true, String(format: "첫 행의 형태가 나머지 행과 다릅니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
    }
    return (false, String(format: "첫 행을 데이터로 유지했습니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
}

func profile(for row: [OcrCell], columnCount: Int) -> RowProfile {
    let texts = row.map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let filledTexts = texts.filter { !$0.isEmpty }
    let joined = filledTexts.joined(separator: "")
    let digitCount = joined.filter(\.isNumber).count
    let characterCount = joined.count
    let averageLength = filledTexts.isEmpty ? 0 : Double(filledTexts.map(\.count).reduce(0, +)) / Double(filledTexts.count)
    let longCellCount = filledTexts.filter { $0.count >= 14 }.count

    return RowProfile(
        filledRatio: columnCount == 0 ? 0 : Double(filledTexts.count) / Double(columnCount),
        digitRatio: characterCount == 0 ? 0 : Double(digitCount) / Double(characterCount),
        averageLength: averageLength,
        longCellRatio: filledTexts.isEmpty ? 0 : Double(longCellCount) / Double(filledTexts.count)
    )
}

func averageProfile(_ profiles: [RowProfile]) -> RowProfile {
    guard !profiles.isEmpty else {
        return RowProfile(filledRatio: 0, digitRatio: 0, averageLength: 0, longCellRatio: 0)
    }
    return RowProfile(
        filledRatio: average(profiles.map(\.filledRatio)),
        digitRatio: average(profiles.map(\.digitRatio)),
        averageLength: average(profiles.map(\.averageLength)),
        longCellRatio: average(profiles.map(\.longCellRatio))
    )
}

func profileDistance(_ left: RowProfile, _ right: RowProfile) -> Double {
    let lengthScale = 30.0
    let values = [
        left.filledRatio - right.filledRatio,
        left.digitRatio - right.digitRatio,
        (left.averageLength - right.averageLength) / lengthScale,
        left.longCellRatio - right.longCellRatio
    ]
    return sqrt(values.map { $0 * $0 }.reduce(0, +))
}

func escapeCSVField(_ value: String) -> String {
    let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return needsQuotes ? "\"\(escaped)\"" : escaped
}

func defaultOutputDirectory(for imagePath: String) -> URL {
    let baseName = URL(fileURLWithPath: imagePath).deletingPathExtension().lastPathComponent
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = formatter.string(from: Date())
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("ocr-output", isDirectory: true)
        .appendingPathComponent("\(baseName)-\(timestamp)", isDirectory: true)
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url)
}

func run() throws {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    if options.showHelp {
        printHelp()
        return
    }

    guard let imagePath = options.imagePath else {
        throw CLIError.missingImagePath
    }

    let outputURL = options.outputDirectory.map { URL(fileURLWithPath: $0) } ?? defaultOutputDirectory(for: imagePath)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let image = try loadCGImage(from: imagePath)
    let boxes = try recognizeText(in: image, languages: options.languages, minConfidence: options.minConfidence)
    let table = buildTable(from: boxes, rowThresholdOverride: options.rowThreshold)
    let csvResult = makeCSV(from: table, headers: options.headers, headerMode: options.headerMode)

    let boxesURL = outputURL.appendingPathComponent("ocr-boxes.json")
    let tableURL = outputURL.appendingPathComponent("table.json")
    let csvURL = outputURL.appendingPathComponent("result.csv")
    let summaryURL = outputURL.appendingPathComponent("summary.json")

    try writeJSON(boxes, to: boxesURL)
    try writeJSON(table, to: tableURL)
    try csvResult.csv.write(to: csvURL, atomically: true, encoding: .utf8)
    try writeJSON(
        RunSummary(
            imagePath: imagePath,
            outputDirectory: outputURL.path,
            boxCount: boxes.count,
            rowCount: table.rows.count,
            columnCount: table.columnCount,
            csvHeaderSource: csvResult.headerSource,
            headerDetected: csvResult.headerDetected,
            csvDataRowCount: csvResult.dataRows.count,
            warnings: table.warnings
        ),
        to: summaryURL
    )

    print("OCR 완료")
    print("출력 폴더: \(outputURL.path)")
    print("텍스트 박스: \(boxes.count)")
    print("행: \(table.rows.count), 열: \(table.columnCount)")
    print("CSV 헤더: \(csvResult.headerSource) · \(csvResult.reason)")
    if !table.warnings.isEmpty {
        print("경고:")
        for warning in table.warnings {
            print("- \(warning)")
        }
    }
}

do {
    try run()
} catch let error as CLIError {
    fputs("오류: \(error.description)\n\n", stderr)
    printHelp()
    exit(1)
} catch {
    fputs("오류: \(error.localizedDescription)\n", stderr)
    exit(1)
}
