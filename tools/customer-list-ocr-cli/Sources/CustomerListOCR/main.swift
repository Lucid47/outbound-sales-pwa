import CoreGraphics
import Foundation
import ImageIO
import Vision

struct CLIOptions {
    var imagePath: String?
    var outputDirectory: String?
    var headers: [String] = []
    var languages: [String] = ["ko-KR", "en-US"]
    var minConfidence: Float = 0
    var showHelp = false
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
    let warnings: [String]
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
      --headers "고객명,연락처,주소"   CSV 헤더. 생략하면 열1, 열2... 사용
      --languages "ko-KR,en-US"     OCR 언어. 기본값: ko-KR,en-US
      --min-confidence <number>     낮은 신뢰도 텍스트 제외 기준. 기본값: 0
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

func buildTable(from boxes: [RecognizedTextBox]) -> OcrTable {
    guard !boxes.isEmpty else {
        return OcrTable(rows: [], columnCount: 0, warnings: ["OCR 텍스트가 없습니다."])
    }

    let medianHeight = median(boxes.map(\.height))
    let rowThreshold = max(medianHeight * 0.75, 0.014)
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

func makeCSV(from table: OcrTable, headers providedHeaders: [String]) -> String {
    let columnCount = max(table.columnCount, providedHeaders.count)
    let headers = (0..<columnCount).map { index in
        index < providedHeaders.count ? providedHeaders[index] : "열\(index + 1)"
    }
    let headerRow = headers.map(escapeCSVField).joined(separator: ",")
    let dataRows = table.rows.map { row in
        (0..<columnCount).map { index in
            let value = index < row.count ? row[index].text : ""
            return escapeCSVField(value)
        }.joined(separator: ",")
    }
    return ([headerRow] + dataRows).joined(separator: "\n") + "\n"
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
    let table = buildTable(from: boxes)
    let csv = makeCSV(from: table, headers: options.headers)

    let boxesURL = outputURL.appendingPathComponent("ocr-boxes.json")
    let tableURL = outputURL.appendingPathComponent("table.json")
    let csvURL = outputURL.appendingPathComponent("result.csv")
    let summaryURL = outputURL.appendingPathComponent("summary.json")

    try writeJSON(boxes, to: boxesURL)
    try writeJSON(table, to: tableURL)
    try csv.write(to: csvURL, atomically: true, encoding: .utf8)
    try writeJSON(
        RunSummary(
            imagePath: imagePath,
            outputDirectory: outputURL.path,
            boxCount: boxes.count,
            rowCount: table.rows.count,
            columnCount: table.columnCount,
            warnings: table.warnings
        ),
        to: summaryURL
    )

    print("OCR 완료")
    print("출력 폴더: \(outputURL.path)")
    print("텍스트 박스: \(boxes.count)")
    print("행: \(table.rows.count), 열: \(table.columnCount)")
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
