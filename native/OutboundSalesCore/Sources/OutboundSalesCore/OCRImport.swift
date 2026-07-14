import CoreGraphics
import CoreImage
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
    let image = try loadCGImage(from: url)
    if rowThreshold != nil || rotateDegrees != 0 {
        return try recognizeCustomerListImage(
            in: rotateImage(image, degrees: rotateDegrees),
            headers: headers,
            headerMode: headerMode,
            languages: languages,
            minConfidence: minConfidence,
            rowThreshold: rowThreshold
        )
    }
    return try recognizeBestCustomerListImage(
        in: image,
        headers: headers,
        headerMode: headerMode,
        languages: languages,
        minConfidence: minConfidence
    )
}

private func loadCGImage(from url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw OCRImportError.imageLoadFailed
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
    let maxPixelSize = max(width, height)
    let transformOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    if maxPixelSize > 0,
       let orientedImage = CGImageSourceCreateThumbnailAtIndex(source, 0, transformOptions as CFDictionary) {
        return orientedImage
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw OCRImportError.imageLoadFailed
    }
    return image
}

private func recognizeBestCustomerListImage(
    in image: CGImage,
    headers: [String],
    headerMode: OCRHeaderMode,
    languages: [String],
    minConfidence: Float
) throws -> OCRImportResult {
    let rotations = [0, 90, 270, 180]
    let preCorrectedImage = perspectiveCorrectedDocumentImage(image)
    let rowThresholds: [Double?] = [0.008, 0.010, 0.012]
    var best: (
        result: OCRImportResult,
        score: Double,
        image: CGImage,
        rotation: Int,
        rowThreshold: Double?,
        rowSlope: Double
    )?

    for rotation in rotations {
        let rotatedOriginal = rotateImage(image, degrees: rotation)
        var imageCandidates: [(image: CGImage, perspectiveCorrected: Bool)] = [(rotatedOriginal, false)]
        if let preCorrectedImage {
            imageCandidates.append((rotateImage(preCorrectedImage, degrees: rotation), true))
        }
        if let correctedImage = perspectiveCorrectedDocumentImage(rotatedOriginal) {
            imageCandidates.append((correctedImage, true))
        }
        for candidate in imageCandidates {
            let boxes = try recognizeText(in: candidate.image, languages: languages, minConfidence: minConfidence)
            for rowSlope in estimateOCRRowSlopes(boxes) {
                let slopedBoxes = deskewOCRTextBoxes(boxes, horizontalSlope: rowSlope)
                let workingBoxes = normalizeRepeatedColumnRows(slopedBoxes)
                for rowThreshold in rowThresholds {
                    let table = buildOCRTable(from: workingBoxes, rowThresholdOverride: rowThreshold)
                    let csv = makeOCRCSV(from: table, headers: headers, headerMode: headerMode)
                    let result = OCRImportResult(boxes: boxes, table: table, csv: csv)
                    let score = scoreOCRTable(table)
                        + (csv.headerDetected ? 3 : 0)
                        - (rotation == 0 ? 0 : 1.5)
                        - (rowThreshold == nil ? 0 : 0.2)
                        - (abs(rowSlope) * 2)
                        - (candidate.perspectiveCorrected ? 0.15 : 0)
                    if best == nil || score > best!.score {
                        best = (result, score, candidate.image, rotation, rowThreshold, rowSlope)
                    }
                }
            }
        }
    }

    guard let best else {
        return try recognizeCustomerListImage(
            in: image,
            headers: headers,
            headerMode: headerMode,
            languages: languages,
            minConfidence: minConfidence,
            rowThreshold: nil
        )
    }
    guard let detectedGrid = detectOCRTableGrid(in: best.image) else { return best.result }
    let leveledBoxes = deskewOCRTextBoxes(best.result.boxes, using: detectedGrid)
    var leveledBest: (result: OCRImportResult, score: Double, rowThreshold: Double?)?
    for rowThreshold in rowThresholds {
        let table = buildOCRTable(from: leveledBoxes, rowThresholdOverride: rowThreshold)
        let csv = makeOCRCSV(from: table, headers: headers, headerMode: headerMode)
        let result = OCRImportResult(boxes: best.result.boxes, table: table, csv: csv)
        let score = scoreOCRTable(table)
            + (csv.headerDetected ? 3 : 0)
            - (best.rotation == 0 ? 0 : 1.5)
            - (rowThreshold == nil ? 0 : 0.2)
        if leveledBest == nil || score > leveledBest!.score {
            leveledBest = (result, score, rowThreshold)
        }
    }
    guard let leveledBest else { return best.result }
    let coordinateCandidate: (result: OCRImportResult, score: Double, rowThreshold: Double?) =
        leveledBest.score >= best.score
        ? leveledBest
        : (result: best.result, score: best.score, rowThreshold: best.rowThreshold)
    guard let gridTable = buildGridAlignedOCRTable(
        from: leveledBoxes,
        detectedGrid: detectedGrid,
        coordinateTable: leveledBest.result.table,
        rowThreshold: leveledBest.rowThreshold
    ) else { return coordinateCandidate.result }
    let gridCSV = makeOCRCSV(from: gridTable, headers: headers, headerMode: headerMode)
    let gridScore = scoreOCRTable(gridTable)
        + (detectedGrid.confidence * 3)
        + (gridCSV.headerDetected ? 3 : 0)
        - (best.rotation == 0 ? 0 : 1.5)
        - (leveledBest.rowThreshold == nil ? 0 : 0.2)
    let gridDropsRecognizedRows = gridTable.rows.count < coordinateCandidate.result.table.rows.count
    let coordinateHasSparsePeripheralRows = coordinateCandidate.result.table.warnings.contains {
        $0.contains("반복되는 열 패턴보다 인식된 값이 적습니다")
    }
    if gridDropsRecognizedRows && !coordinateHasSparsePeripheralRows {
        return coordinateCandidate.result
    }
    if gridScore >= coordinateCandidate.score {
        return OCRImportResult(boxes: best.result.boxes, table: gridTable, csv: gridCSV)
    }
    return coordinateCandidate.result
}

func perspectiveCorrectedDocumentImage(_ image: CGImage) -> CGImage? {
    let request = VNDetectDocumentSegmentationRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    guard (try? handler.perform([request])) != nil,
          let rectangle = request.results?.first else { return nil }

    let points = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
    let normalizedArea = abs(zip(points, points.dropFirst() + [points[0]]).reduce(0.0) { result, pair in
        result + (Double(pair.0.x * pair.1.y) - Double(pair.1.x * pair.0.y))
    }) / 2
    guard normalizedArea >= 0.18, normalizedArea <= 0.98 else { return nil }

    let input = CIImage(cgImage: image)
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let filter = CIFilter(name: "CIPerspectiveCorrection")
    filter?.setValue(input, forKey: kCIInputImageKey)
    filter?.setValue(CIVector(x: rectangle.topLeft.x * width, y: rectangle.topLeft.y * height), forKey: "inputTopLeft")
    filter?.setValue(CIVector(x: rectangle.topRight.x * width, y: rectangle.topRight.y * height), forKey: "inputTopRight")
    filter?.setValue(CIVector(x: rectangle.bottomRight.x * width, y: rectangle.bottomRight.y * height), forKey: "inputBottomRight")
    filter?.setValue(CIVector(x: rectangle.bottomLeft.x * width, y: rectangle.bottomLeft.y * height), forKey: "inputBottomLeft")
    guard let output = filter?.outputImage else { return nil }
    return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent)
}

func normalizeRepeatedColumnRows(_ boxes: [RecognizedTextBox]) -> [RecognizedTextBox] {
    guard boxes.count >= 18 else { return boxes }
    let xGroups = cluster(boxes.sorted { $0.x < $1.x }, key: \.x, threshold: 0.025)
    let substantialGroups = xGroups.filter { $0.count >= 6 }
    var countFrequency: [Int: Int] = [:]
    for group in substantialGroups { countFrequency[group.count, default: 0] += 1 }
    guard let repeatedCount = countFrequency
        .filter({ $0.key >= 8 && $0.value >= 3 })
        .max(by: { left, right in
            left.value == right.value ? left.key < right.key : left.value < right.value
        })?.key else { return boxes }

    let repeatedGroups = substantialGroups.filter { $0.count == repeatedCount }
    guard repeatedGroups.count >= 3,
          let anchorGroup = repeatedGroups.min(by: {
              average($0.map(\.x)) < average($1.map(\.x))
          }) else { return boxes }
    let anchorCenters = anchorGroup.sorted { $0.centerY < $1.centerY }.map(\.centerY)
    let anchorGaps = zip(anchorCenters, anchorCenters.dropFirst()).map { $1 - $0 }
    guard !anchorGaps.isEmpty,
          median(anchorGaps) >= 0.012,
          anchorGaps.filter({ $0 <= 0 }).isEmpty else { return boxes }

    var correctedByIdentity: [String: RecognizedTextBox] = [:]
    for group in repeatedGroups {
        for (index, box) in group.sorted(by: { $0.centerY < $1.centerY }).enumerated() {
            let corrected = RecognizedTextBox(
                text: box.text,
                x: box.x,
                y: anchorCenters[index] - (box.height / 2),
                width: box.width,
                height: box.height,
                confidence: box.confidence,
                sourceLevel: box.sourceLevel
            )
            correctedByIdentity[ocrBoxIdentity(box)] = corrected
        }
    }
    return boxes.map { correctedByIdentity[ocrBoxIdentity($0)] ?? $0 }
}

private func ocrBoxIdentity(_ box: RecognizedTextBox) -> String {
    "\(box.text)|\(box.x)|\(box.y)|\(box.width)|\(box.height)"
}

private func estimateOCRRowSlopes(_ boxes: [RecognizedTextBox]) -> [Double] {
    guard boxes.count >= 8 else { return [0] }
    var bins: [Int: Double] = [:]
    for leftIndex in boxes.indices {
        let left = boxes[leftIndex]
        for right in boxes.dropFirst(leftIndex + 1) {
            let deltaX = right.centerX - left.centerX
            let deltaY = right.centerY - left.centerY
            guard abs(deltaX) >= 0.10, abs(deltaY) <= 0.10 else { continue }
            let slope = deltaY / deltaX
            guard abs(slope) <= 0.35 else { continue }
            let bin = Int((slope / 0.01).rounded())
            bins[bin, default: 0] += min(abs(deltaX), 0.45)
        }
    }
    let ranked = bins.sorted { $0.value > $1.value }
    var selected: [Double] = [0]
    for entry in ranked {
        let slope = Double(entry.key) * 0.01
        guard abs(slope) >= 0.015,
              !selected.contains(where: { abs($0 - slope) < 0.025 }) else { continue }
        selected.append(slope)
        if selected.count == 4 { break }
    }
    return selected
}

private func deskewOCRTextBoxes(
    _ boxes: [RecognizedTextBox],
    horizontalSlope: Double
) -> [RecognizedTextBox] {
    guard abs(horizontalSlope) >= 0.003 else { return boxes }
    return boxes.map { box in
        let correctedCenterY = box.centerY - (horizontalSlope * (box.centerX - 0.5))
        return RecognizedTextBox(
            text: box.text,
            x: box.x,
            y: correctedCenterY - (box.height / 2),
            width: box.width,
            height: box.height,
            confidence: box.confidence,
            sourceLevel: box.sourceLevel
        )
    }
}

func deskewOCRTextBoxes(
    _ boxes: [RecognizedTextBox],
    using grid: OCRTableGrid
) -> [RecognizedTextBox] {
    guard abs(grid.horizontalSlope) >= 0.003 || abs(grid.verticalSlope) >= 0.003 else { return boxes }
    return boxes.map { box in
        let correctedCenterX = box.centerX - (grid.verticalSlope * (box.centerY - 0.5))
        let correctedCenterY = box.centerY - (grid.horizontalSlope * (box.centerX - 0.5))
        return RecognizedTextBox(
            text: box.text,
            x: correctedCenterX - (box.width / 2),
            y: correctedCenterY - (box.height / 2),
            width: box.width,
            height: box.height,
            confidence: box.confidence,
            sourceLevel: box.sourceLevel
        )
    }
}

private func recognizeCustomerListImage(
    in image: CGImage,
    headers: [String],
    headerMode: OCRHeaderMode,
    languages: [String],
    minConfidence: Float,
    rowThreshold: Double?
) throws -> OCRImportResult {
    let boxes = try recognizeText(in: image, languages: languages, minConfidence: minConfidence)
    let coordinateTable = buildOCRTable(from: boxes, rowThresholdOverride: rowThreshold)
    let gridTable = detectOCRTableGrid(in: image).flatMap {
        buildGridAlignedOCRTable(
            from: boxes,
            detectedGrid: $0,
            coordinateTable: coordinateTable,
            rowThreshold: rowThreshold
        )
    }
    let table: OcrTable
    if let gridTable {
        let coordinateCSV = makeOCRCSV(from: coordinateTable, headers: headers, headerMode: headerMode)
        let gridCSV = makeOCRCSV(from: gridTable, headers: headers, headerMode: headerMode)
        let coordinateScore = scoreOCRTable(coordinateTable) + (coordinateCSV.headerDetected ? 3 : 0)
        let gridScore = scoreOCRTable(gridTable) + (gridCSV.headerDetected ? 3 : 0) + 3
        table = gridScore >= coordinateScore ? gridTable : coordinateTable
    } else {
        table = coordinateTable
    }
    let csv = makeOCRCSV(from: table, headers: headers, headerMode: headerMode)
    return OCRImportResult(boxes: boxes, table: table, csv: csv)
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
    let rowThreshold = rowThresholdOverride ?? defaultRowThreshold(forMedianHeight: medianHeight)
    let rowGroups = cluster(boxes.sorted { $0.centerY < $1.centerY }, key: \.centerY, threshold: rowThreshold)
        .map { $0.sorted { $0.x < $1.x } }
    let columnCenters = inferColumnCenters(from: rowGroups, medianTextHeight: medianHeight)

    var warnings: [String] = []
    if columnCenters.isEmpty {
        warnings.append("열 후보를 찾지 못했습니다.")
    }

    let provisionalRows = rowGroups.enumerated().map { rowIndex, rowBoxes in
        var cellsByColumn: [Int: [RecognizedTextBox]] = [:]
        for box in rowBoxes {
            let columnIndex = nearestIndex(to: box.x, in: columnCenters) ?? 0
            cellsByColumn[columnIndex, default: []].append(box)
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

    let consolidation = consolidateRepeatedBodyRows(provisionalRows, columnCount: columnCenters.count)
    warnings.append(contentsOf: consolidation.warnings)
    let headerSplit = splitLeadingPeerHeaderColumn(consolidation.rows)
    if headerSplit.didSplit {
        warnings.append("첫 헤더 행에서 나란히 배치된 선행 표시 열을 별도 열로 분리했습니다.")
    }

    return normalizeOCRTableReadingDirection(
        OcrTable(rows: headerSplit.rows, columnCount: headerSplit.columnCount, warnings: warnings)
    )
}

func normalizeOCRTableReadingDirection(_ table: OcrTable) -> OcrTable {
    guard table.rows.count >= 5, table.columnCount >= 3 else { return table }
    let columnTexts = (0..<table.columnCount).map { columnIndex in
        table.rows.compactMap { row -> String? in
            guard row.indices.contains(columnIndex) else { return nil }
            let text = row[columnIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
    let dateProfiles = columnTexts.enumerated().map { index, texts in
        (index: index, score: repeatedDateScore(texts))
    }
    let nameProfiles = columnTexts.enumerated().map { index, texts in
        (index: index, score: repeatedNameScore(texts))
    }
    guard let dateProfile = dateProfiles.max(by: { $0.score < $1.score }),
          let nameProfile = nameProfiles.max(by: { $0.score < $1.score }),
          dateProfile.score >= 0.35,
          nameProfile.score >= 0.32,
          dateProfile.index < nameProfile.index else { return table }

    let reversedRows = table.rows.reversed().enumerated().map { rowIndex, row in
        row.reversed().enumerated().map { columnIndex, cell in
            reindexedCell(cell, rowIndex: rowIndex, columnIndex: columnIndex)
        }
    }
    let warning = "날짜와 이름 열의 배치로 180도 역방향 표를 감지해 행과 열 순서를 바로잡았습니다."
    return OcrTable(
        rows: reversedRows,
        columnCount: table.columnCount,
        warnings: table.warnings.contains(warning) ? table.warnings : table.warnings + [warning]
    )
}

private func repeatedDateScore(_ texts: [String]) -> Double {
    guard texts.count >= 5 else { return 0 }
    let matches = texts.filter {
        $0.range(of: #"(?:19|20)[0-9]{2}\s*[.\-/년]\s*[0-9]{1,2}"#, options: .regularExpression) != nil
    }.count
    return Double(matches) / Double(texts.count)
}

private func repeatedNameScore(_ texts: [String]) -> Double {
    guard texts.count >= 5 else { return 0 }
    let candidates = texts.filter { text in
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard (2...12).contains(compact.count) else { return false }
        let hangulCount = compact.unicodeScalars.filter { scalar in
            (0xAC00...0xD7A3).contains(Int(scalar.value))
        }.count
        let digitCount = compact.filter(\.isNumber).count
        return Double(hangulCount) / Double(max(compact.count, 1)) >= 0.70 && digitCount == 0
    }
    guard !candidates.isEmpty else { return 0 }
    let uniqueRatio = Double(Set(candidates).count) / Double(candidates.count)
    let candidateRatio = Double(candidates.count) / Double(texts.count)
    return candidateRatio * uniqueRatio
}

private enum GridBoundaryAxis {
    case horizontal
    case vertical
}

private func buildGridAlignedOCRTable(
    from boxes: [RecognizedTextBox],
    detectedGrid: OCRTableGrid,
    coordinateTable: OcrTable,
    rowThreshold: Double?
) -> OcrTable? {
    guard coordinateTable.rows.count >= 3, coordinateTable.columnCount >= 2 else { return nil }
    let medianHeight = median(boxes.map(\.height))
    let threshold = rowThreshold ?? defaultRowThreshold(forMedianHeight: medianHeight)
    let rawRows = cluster(boxes.sorted { $0.centerY < $1.centerY }, key: \.centerY, threshold: threshold)
        .map { $0.sorted { $0.x < $1.x } }
    let columnCenters = inferColumnCenters(from: rawRows, medianTextHeight: medianHeight)
    let rowCenters = coordinateTable.rows.map { centerY(of: $0) }.filter { $0 > 0 }
    guard columnCenters.count >= 2, rowCenters.count >= 3 else { return nil }

    guard let vertical = snapGridBoundaries(
        detectedGrid.verticalBoundaries,
        around: columnCenters,
        boxes: boxes,
        axis: .vertical
    ), let horizontal = snapGridBoundaries(
        detectedGrid.horizontalBoundaries,
        around: rowCenters,
        boxes: boxes,
        axis: .horizontal
    ) else { return nil }

    var cells = Array(
        repeating: Array(repeating: [RecognizedTextBox](), count: vertical.count - 1),
        count: horizontal.count - 1
    )
    for box in boxes {
        guard let rowIndex = boundaryIntervalIndex(for: box.centerY, boundaries: horizontal),
              let columnIndex = boundaryIntervalIndex(for: box.centerX, boundaries: vertical) else { continue }
        cells[rowIndex][columnIndex].append(box)
    }

    let populatedRows = cells.filter { row in row.contains { !$0.isEmpty } }
    guard populatedRows.count >= 3 else { return nil }
    let tableRows = populatedRows.enumerated().map { rowIndex, row in
        row.enumerated().map { columnIndex, cellBoxes in
            let sortedBoxes = cellBoxes.sorted {
                if abs($0.centerY - $1.centerY) > 0.004 { return $0.centerY < $1.centerY }
                return $0.x < $1.x
            }
            return OcrCell(
                text: sortedBoxes.map(\.text).joined(separator: " "),
                boxes: sortedBoxes,
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                confidence: weightedConfidence(for: sortedBoxes)
            )
        }
    }
    let headerSplit = splitLeadingPeerHeaderColumn(tableRows)
    let maximumRowDifference = max(2, Int(ceil(Double(coordinateTable.rows.count) * 0.15)))
    guard abs(headerSplit.rows.count - coordinateTable.rows.count) <= maximumRowDifference,
          abs(headerSplit.columnCount - coordinateTable.columnCount) <= 2 else { return nil }
    let warnings = coordinateTable.warnings + [
        "표 선을 검출해 실제 셀 경계를 기준으로 행과 열을 보정했습니다."
    ]
    return normalizeOCRTableReadingDirection(
        OcrTable(rows: headerSplit.rows, columnCount: headerSplit.columnCount, warnings: warnings)
    )
}

private func snapGridBoundaries(
    _ candidates: [Double],
    around centers: [Double],
    boxes: [RecognizedTextBox],
    axis: GridBoundaryAxis
) -> [Double]? {
    let sortedCenters = Array(Set(centers)).sorted()
    guard sortedCenters.count >= 2 else { return nil }
    let centerGaps = zip(sortedCenters, sortedCenters.dropFirst()).map { $1 - $0 }
    let typicalGap = median(centerGaps)
    let targets = [max(sortedCenters[0] - (centerGaps[0] / 2), 0)]
        + zip(sortedCenters, sortedCenters.dropFirst()).map { ($0 + $1) / 2 }
        + [min(sortedCenters.last! + ((centerGaps.last ?? typicalGap) / 2), 1)]
    var snapped: [Double] = []
    var matchedCount = 0
    var totalDistance = 0.0

    for target in targets {
        let maximumDistance = max(0.025, min(typicalGap * 0.55, 0.075))
        let eligible = candidates.filter { candidate in
            abs(candidate - target) <= maximumDistance
                && (snapped.last.map { candidate - $0 >= 0.010 } ?? true)
        }
        let selected = eligible.min { left, right in
            boundaryCandidateCost(left, target: target, boxes: boxes, axis: axis)
                < boundaryCandidateCost(right, target: target, boxes: boxes, axis: axis)
        }
        if let selected {
            snapped.append(selected)
            matchedCount += 1
            totalDistance += abs(selected - target)
        } else {
            snapped.append(target)
        }
    }
    guard snapped.count == targets.count,
          zip(snapped, snapped.dropFirst()).allSatisfy({ $1 > $0 }),
          Double(matchedCount) / Double(targets.count) >= 0.65,
          totalDistance / Double(max(matchedCount, 1)) <= 0.035 else { return nil }
    return snapped
}

private func boundaryCandidateCost(
    _ candidate: Double,
    target: Double,
    boxes: [RecognizedTextBox],
    axis: GridBoundaryAxis
) -> Double {
    let crossingCount = boxes.filter { box in
        switch axis {
        case .vertical:
            return box.x + 0.002 < candidate && candidate < box.x + box.width - 0.002
        case .horizontal:
            return box.y + 0.001 < candidate && candidate < box.y + box.height - 0.001
        }
    }.count
    return abs(candidate - target) + (Double(crossingCount) * 0.0015)
}

private func boundaryIntervalIndex(for value: Double, boundaries: [Double]) -> Int? {
    guard boundaries.count >= 2, value >= boundaries[0], value <= boundaries.last! else { return nil }
    if value == boundaries.last { return boundaries.count - 2 }
    return (0..<(boundaries.count - 1)).first {
        boundaries[$0] <= value && value < boundaries[$0 + 1]
    }
}

private func defaultRowThreshold(forMedianHeight medianHeight: Double) -> Double {
    min(max(medianHeight * 0.9, 0.008), 0.018)
}

private struct PositionedTextBox {
    let box: RecognizedTextBox
    let rowIndex: Int

    var x: Double { box.x }
}

private struct ColumnCandidate {
    var boxes: [PositionedTextBox]

    var center: Double { average(boxes.map(\.x)) }
    var rowIndexes: Set<Int> { Set(boxes.map(\.rowIndex)) }
}

private func inferColumnCenters(
    from rowGroups: [[RecognizedTextBox]],
    medianTextHeight: Double
) -> [Double] {
    let positioned = rowGroups.enumerated().flatMap { rowIndex, boxes in
        boxes.map { PositionedTextBox(box: $0, rowIndex: rowIndex) }
    }
    guard !positioned.isEmpty else { return [] }

    // Start with narrow anchors so adjacent compact columns remain separate.
    // Header cells and centered body text can begin at different x positions,
    // so non-cooccurring neighboring anchors are merged afterwards.
    let fineThreshold = min(max(medianTextHeight * 1.25, 0.012), 0.022)
    var candidates = cluster(positioned.sorted { $0.x < $1.x }, key: \.x, threshold: fineThreshold)
        .map { ColumnCandidate(boxes: $0) }
        .sorted { $0.center < $1.center }

    let mergeDistance = min(max(medianTextHeight * 4.8, 0.050), 0.075)
    var didMerge = true
    while didMerge, candidates.count > 1 {
        didMerge = false
        for index in 0..<(candidates.count - 1) {
            let left = candidates[index]
            let right = candidates[index + 1]
            let sharedRows = left.rowIndexes.intersection(right.rowIndexes).count
            guard right.center - left.center <= mergeDistance, sharedRows == 0 else { continue }

            candidates[index].boxes.append(contentsOf: right.boxes)
            candidates.remove(at: index + 1)
            didMerge = true
            break
        }
    }

    let minimumSupport = rowGroups.count >= 8 ? 2 : 1
    let repeatedCandidates = candidates.enumerated().compactMap { index, candidate -> ColumnCandidate? in
        let cooccursWithNeighbor = [index - 1, index + 1].contains { neighborIndex in
            guard candidates.indices.contains(neighborIndex) else { return false }
            return !candidate.rowIndexes.intersection(candidates[neighborIndex].rowIndexes).isEmpty
        }
        return candidate.rowIndexes.count >= minimumSupport || cooccursWithNeighbor ? candidate : nil
    }
    let selected = repeatedCandidates.count >= 2 ? repeatedCandidates : candidates
    return selected.map(\.center).sorted()
}

private struct RowConsolidationResult {
    let rows: [[OcrCell]]
    let warnings: [String]
}

private struct HeaderColumnSplitResult {
    let rows: [[OcrCell]]
    let columnCount: Int
    let didSplit: Bool
}

private func splitLeadingPeerHeaderColumn(_ rows: [[OcrCell]]) -> HeaderColumnSplitResult {
    guard rows.count >= 2, let firstRow = rows.first, let leadingCell = firstRow.first else {
        return HeaderColumnSplitResult(rows: rows, columnCount: rows.first?.count ?? 0, didSplit: false)
    }
    let leadingBodyCount = rows.dropFirst().filter {
        !$0[0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }.count
    guard leadingBodyCount >= 3 else {
        return HeaderColumnSplitResult(rows: rows, columnCount: firstRow.count, didSplit: false)
    }

    let peerGroups = cluster(
        leadingCell.boxes.sorted { $0.centerY < $1.centerY },
        key: \.centerY,
        threshold: 0.008
    )
    guard let peers = peerGroups
        .filter({ $0.count >= 2 })
        .max(by: { $0.count < $1.count })?
        .sorted(by: { $0.x < $1.x }),
        peers.count == 2,
        peers[1].x - (peers[0].x + peers[0].width) >= 0.006 else {
        return HeaderColumnSplitResult(rows: rows, columnCount: firstRow.count, didSplit: false)
    }

    let expandedRows = rows.enumerated().map { rowIndex, row in
        var cells: [OcrCell] = []
        if rowIndex == 0 {
            for peer in peers {
                cells.append(OcrCell(
                    text: peer.text,
                    boxes: [peer],
                    rowIndex: rowIndex,
                    columnIndex: cells.count,
                    confidence: peer.confidence
                ))
            }
        } else {
            cells.append(OcrCell(
                text: "",
                boxes: [],
                rowIndex: rowIndex,
                columnIndex: 0,
                confidence: nil
            ))
            cells.append(reindexedCell(row[0], rowIndex: rowIndex, columnIndex: 1))
        }
        for sourceCell in row.dropFirst() {
            cells.append(reindexedCell(sourceCell, rowIndex: rowIndex, columnIndex: cells.count))
        }
        return cells
    }
    return HeaderColumnSplitResult(rows: expandedRows, columnCount: firstRow.count + 1, didSplit: true)
}

private func consolidateRepeatedBodyRows(
    _ rows: [[OcrCell]],
    columnCount: Int
) -> RowConsolidationResult {
    guard rows.count >= 4, columnCount >= 2 else {
        return RowConsolidationResult(rows: rows, warnings: [])
    }

    let prefixColumnCount = min(max(columnCount / 2, 2), 5)
    let fillCounts = (0..<prefixColumnCount).map { columnIndex in
        rows.filter { !$0[columnIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    let maximumFillCount = fillCounts.max() ?? 0
    let minimumAnchorSupport = max(3, Int(ceil(Double(maximumFillCount) * 0.55)))
    let anchorColumns = fillCounts.enumerated()
        .filter { $0.element >= minimumAnchorSupport }
        .prefix(2)
        .map(\.offset)
    guard !anchorColumns.isEmpty else {
        return RowConsolidationResult(rows: rows, warnings: [])
    }

    let repeatedBodyStart = firstRepeatedBodyRow(in: rows, anchorColumns: Array(anchorColumns))
    let fallbackBodyStart = rows.firstIndex { row in
        filledCellCount(in: row) >= 2 && digitRatio(in: row) >= 0.18
    }
    guard let bodyStart = repeatedBodyStart ?? fallbackBodyStart else {
        return RowConsolidationResult(rows: rows, warnings: [])
    }

    let headerEnd = rows[..<bodyStart].firstIndex { digitRatio(in: $0) >= 0.18 } ?? bodyStart
    let headerRows = Array(rows[..<headerEnd])
    let bodyRows = Array(rows[bodyStart...])
    let anchorIndexes = bodyRows.indices.filter { rowIndex in
        anchorColumns.contains { columnIndex in
            !bodyRows[rowIndex][columnIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    guard !anchorIndexes.isEmpty else {
        return RowConsolidationResult(rows: rows, warnings: [])
    }

    let anchorCenters = anchorIndexes.map { centerY(of: bodyRows[$0]) }
    var groupedRows = Array(repeating: [[OcrCell]](), count: anchorIndexes.count)
    for rowIndex in bodyRows.indices {
        let sourceRow = bodyRows[rowIndex]
        let rowY = centerY(of: sourceRow)
        var groupIndex = anchorCenters.enumerated().min { left, right in
            abs(left.element - rowY) < abs(right.element - rowY)
        }?.offset ?? 0
        if groupIndex > 0,
           rowY < anchorCenters[groupIndex],
           isLikelyContinuationRow(sourceRow) {
            groupIndex -= 1
        }
        if groupIndex > 0,
           !rowContainsAnchorValue(sourceRow, anchorColumns: Array(anchorColumns)),
           groupedRows[groupIndex - 1].reversed().contains(where: {
               isOverlappingCellContinuation(from: $0, to: sourceRow)
           }) {
            groupIndex -= 1
        }
        groupedRows[groupIndex].append(sourceRow)
    }

    var consolidated: [[OcrCell]] = []
    if !headerRows.isEmpty {
        consolidated.append(mergeOCRRows(headerRows, rowIndex: 0, columnCount: columnCount))
    }
    for group in groupedRows where !group.isEmpty {
        consolidated.append(mergeOCRRows(group, rowIndex: consolidated.count, columnCount: columnCount))
    }
    consolidated = moveOverlappingContinuationBoxes(
        in: consolidated,
        bodyStartIndex: headerRows.isEmpty ? 0 : 1,
        anchorColumns: Array(anchorColumns)
    )
    consolidated = mergeOrphanAnchorRows(
        in: consolidated,
        bodyStartIndex: headerRows.isEmpty ? 0 : 1,
        anchorColumns: Array(anchorColumns),
        columnCount: columnCount
    )

    var warnings: [String] = []
    let excludedPreambleCount = max(bodyStart - headerEnd, 0)
    if excludedPreambleCount > 0 {
        warnings.append("반복되는 본문 패턴 이전 \(excludedPreambleCount)개 행을 헤더/요약 영역으로 분리했습니다.")
    }
    let bodyOutputRows = headerRows.isEmpty ? consolidated : Array(consolidated.dropFirst())
    let typicalFilledCount = median(bodyOutputRows.map { Double(filledCellCount(in: $0)) })
    for (index, row) in bodyOutputRows.enumerated() {
        if Double(filledCellCount(in: row)) < max(2, typicalFilledCount * 0.45) {
            warnings.append("본문 \(index + 1)행은 반복되는 열 패턴보다 인식된 값이 적습니다.")
        }
    }
    return RowConsolidationResult(rows: consolidated, warnings: warnings)
}

private func firstRepeatedBodyRow(in rows: [[OcrCell]], anchorColumns: [Int]) -> Int? {
    var firstIndexes: [Int] = []
    for columnIndex in anchorColumns {
        var occurrences: [String: [Int]] = [:]
        for (rowIndex, row) in rows.enumerated() {
            let normalized = row[columnIndex].text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard normalized.count >= 2 else { continue }
            occurrences[normalized, default: []].append(rowIndex)
        }
        for indexes in occurrences.values where indexes.count >= 3 {
            if let first = indexes.first { firstIndexes.append(first) }
        }
    }
    return firstIndexes.min()
}

private func mergeOCRRows(_ rows: [[OcrCell]], rowIndex: Int, columnCount: Int) -> [OcrCell] {
    (0..<columnCount).map { columnIndex in
        let sourceCells = rows.map { $0[columnIndex] }
        let boxes = sourceCells.flatMap(\.boxes).sorted {
            if abs($0.centerY - $1.centerY) > 0.004 { return $0.centerY < $1.centerY }
            return $0.x < $1.x
        }
        return OcrCell(
            text: boxes.map(\.text).joined(separator: " "),
            boxes: boxes,
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            confidence: weightedConfidence(for: boxes)
        )
    }
}

private func reindexedCell(_ cell: OcrCell, rowIndex: Int, columnIndex: Int) -> OcrCell {
    OcrCell(
        text: cell.text,
        boxes: cell.boxes,
        rowIndex: rowIndex,
        columnIndex: columnIndex,
        confidence: cell.confidence
    )
}

private func filledCellCount(in row: [OcrCell]) -> Int {
    row.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
}

private func digitRatio(in row: [OcrCell]) -> Double {
    let text = row.map(\.text).joined()
    guard !text.isEmpty else { return 0 }
    return Double(text.filter(\.isNumber).count) / Double(text.count)
}

private func centerY(of row: [OcrCell]) -> Double {
    let boxes = row.flatMap(\.boxes)
    return boxes.isEmpty ? 0 : average(boxes.map(\.centerY))
}

private func isLikelyContinuationRow(_ row: [OcrCell]) -> Bool {
    row.map(\.text)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .contains { text in
            text.hasPrefix("(") || text.hasPrefix("호(") || text.hasSuffix(")")
        }
}

private func rowContainsAnchorValue(_ row: [OcrCell], anchorColumns: [Int]) -> Bool {
    anchorColumns.contains { columnIndex in
        row.indices.contains(columnIndex)
            && !row[columnIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private func isOverlappingCellContinuation(from previousRow: [OcrCell], to currentRow: [OcrCell]) -> Bool {
    guard filledCellCount(in: currentRow) <= max(3, currentRow.count / 3) else { return false }

    return currentRow.indices.contains { columnIndex in
        let previousBoxes = previousRow[columnIndex].boxes
        let currentBoxes = currentRow[columnIndex].boxes
        guard !previousBoxes.isEmpty, !currentBoxes.isEmpty else { return false }

        let previousBottom = previousBoxes.map { $0.y + $0.height }.max() ?? 0
        let currentTop = currentBoxes.map(\.y).min() ?? 1
        let typicalHeight = median((previousBoxes + currentBoxes).map(\.height))
        let maximumContinuationGap = max(0.003, typicalHeight * 0.15)
        return currentTop - previousBottom <= maximumContinuationGap
    }
}

private func moveOverlappingContinuationBoxes(
    in sourceRows: [[OcrCell]],
    bodyStartIndex: Int,
    anchorColumns: [Int]
) -> [[OcrCell]] {
    guard sourceRows.count > bodyStartIndex + 1 else { return sourceRows }
    var rows = sourceRows

    for rowIndex in (bodyStartIndex + 1)..<rows.count {
        let anchorBoxes = anchorColumns.flatMap { columnIndex in
            rows[rowIndex].indices.contains(columnIndex) ? rows[rowIndex][columnIndex].boxes : []
        }
        guard !anchorBoxes.isEmpty else { continue }
        let anchorCenterY = average(anchorBoxes.map(\.centerY))

        for columnIndex in rows[rowIndex].indices {
            let previousBoxes = rows[rowIndex - 1][columnIndex].boxes
            guard !previousBoxes.isEmpty else { continue }

            let boxesToMove = rows[rowIndex][columnIndex].boxes.filter { box in
                let isAboveCurrentAnchor = box.centerY < anchorCenterY - max(0.004, box.height * 0.2)
                guard isAboveCurrentAnchor else { return false }
                return previousBoxes.contains { previousBox in
                    let gap = box.y - (previousBox.y + previousBox.height)
                    let maximumGap = max(0.003, median([box.height, previousBox.height]) * 0.15)
                    return gap <= maximumGap
                }
            }
            guard !boxesToMove.isEmpty else { continue }

            let movingSet = Set(boxesToMove.map(boxIdentity))
            let remainingBoxes = rows[rowIndex][columnIndex].boxes.filter {
                !movingSet.contains(boxIdentity($0))
            }
            rows[rowIndex - 1][columnIndex] = rebuiltCell(
                rows[rowIndex - 1][columnIndex],
                boxes: previousBoxes + boxesToMove
            )
            rows[rowIndex][columnIndex] = rebuiltCell(rows[rowIndex][columnIndex], boxes: remainingBoxes)
        }
    }
    return rows
}

private func boxIdentity(_ box: RecognizedTextBox) -> String {
    "\(box.x)|\(box.y)|\(box.width)|\(box.height)|\(box.text)"
}

private func rebuiltCell(_ cell: OcrCell, boxes: [RecognizedTextBox]) -> OcrCell {
    let sortedBoxes = boxes.sorted {
        if abs($0.centerY - $1.centerY) > 0.004 { return $0.centerY < $1.centerY }
        return $0.x < $1.x
    }
    return OcrCell(
        text: sortedBoxes.map(\.text).joined(separator: " "),
        boxes: sortedBoxes,
        rowIndex: cell.rowIndex,
        columnIndex: cell.columnIndex,
        confidence: weightedConfidence(for: sortedBoxes)
    )
}

private func mergeOrphanAnchorRows(
    in sourceRows: [[OcrCell]],
    bodyStartIndex: Int,
    anchorColumns: [Int],
    columnCount: Int
) -> [[OcrCell]] {
    var rows = sourceRows
    var rowIndex = bodyStartIndex
    while rowIndex < rows.count {
        let row = rows[rowIndex]
        let filledIndexes = row.indices.filter {
            !row[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let repeatedColumnIndex = filledIndexes.first
        let repeatedValueCount: Int
        if let repeatedColumnIndex {
            let value = row[repeatedColumnIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            repeatedValueCount = rows[bodyStartIndex...].filter {
                $0[repeatedColumnIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == value
            }.count
        } else {
            repeatedValueCount = 0
        }
        let isOrphanAnchor = filledIndexes.count == 1
            && (anchorColumns.contains(filledIndexes[0]) || repeatedValueCount >= 3)
        guard isOrphanAnchor else {
            rowIndex += 1
            continue
        }

        let candidates = [rowIndex - 1, rowIndex + 1].filter { candidateIndex in
            rows.indices.contains(candidateIndex)
                && candidateIndex >= bodyStartIndex
                && rows[candidateIndex][filledIndexes[0]].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && filledCellCount(in: rows[candidateIndex]) >= 2
        }
        guard let targetIndex = candidates.min(by: {
            abs(centerY(of: rows[$0]) - centerY(of: row))
                < abs(centerY(of: rows[$1]) - centerY(of: row))
        }) else {
            rowIndex += 1
            continue
        }

        rows[targetIndex] = mergeOCRRows(
            [rows[targetIndex], row],
            rowIndex: targetIndex,
            columnCount: columnCount
        )
        rows.remove(at: rowIndex)
        if targetIndex > rowIndex { rowIndex = max(bodyStartIndex, rowIndex - 1) }
    }

    return rows.enumerated().map { newRowIndex, row in
        row.enumerated().map { columnIndex, cell in
            reindexedCell(cell, rowIndex: newRowIndex, columnIndex: columnIndex)
        }
    }
}

private func scoreOCRTable(_ table: OcrTable) -> Double {
    guard table.columnCount > 0, !table.rows.isEmpty else { return -100 }
    let cells = table.rows.flatMap { $0 }
    let nonemptyCells = cells.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let nonemptyRows = table.rows.filter { row in
        row.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    guard !nonemptyRows.isEmpty else { return -100 }

    let filledRatio = Double(nonemptyCells.count) / Double(max(cells.count, 1))
    let averageFilledCellsPerRow = Double(nonemptyCells.count) / Double(nonemptyRows.count)
    let filledCounts = nonemptyRows.map { row in row.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    let typicalFilledCount = median(filledCounts.map(Double.init))
    let sparseRowCount = filledCounts.filter { Double($0) < max(typicalFilledCount - 1, 1) }.count
    let longCellRatio = Double(nonemptyCells.filter { $0.text.count >= 34 }.count) / Double(max(nonemptyCells.count, 1))
    let veryLongCellRatio = Double(nonemptyCells.filter { $0.text.count >= 60 }.count) / Double(max(nonemptyCells.count, 1))
    let recordCollisionCount = nonemptyCells.reduce(0) { $0 + recordCollisionCount(in: $1.text) }
    let bodySignalRowCount = nonemptyRows.filter { bodyIdentitySignalCount(in: $0) >= 2 }.count
    let columnScore: Double
    if table.columnCount == 1 {
        columnScore = -35
    } else if table.columnCount <= 16 {
        columnScore = 12
    } else {
        columnScore = 12 - Double(table.columnCount - 16) * 3
    }

    return Double(min(nonemptyRows.count, 80)) * 0.4
        + columnScore
        + Double(min(nonemptyCells.count, 240)) * 0.22
        + filledRatio * 24
        + min(averageFilledCellsPerRow, 5) * 10
        + Double(bodySignalRowCount) * 2
        + sequentialRowDirectionScore(table.rows)
        - Double(sparseRowCount) * 2.5
        - longCellRatio * 70
        - veryLongCellRatio * 120
        - Double(recordCollisionCount)
        - Double(table.warnings.count) * 0.25
}

private func recordCollisionCount(in text: String) -> Int {
    let patterns = [
        #"(?<![0-9])[0-9]{9,11}(?![0-9])"#,
        #"(?:19|20)[0-9]{2}\s*[.\-/년]\s*[0-9]{1,2}\s*[.\-/월]\s*[0-9]{1,2}"#,
        #"(?:[0-9]{1,3},){1,2}[0-9]{3}"#
    ]
    return patterns.reduce(0) { result, pattern in
        let expression = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let count = expression?.numberOfMatches(in: text, range: range) ?? 0
        return result + max(count - 1, 0)
    }
}

private func sequentialRowDirectionScore(_ rows: [[OcrCell]]) -> Double {
    guard let columnCount = rows.map(\.count).max(), columnCount > 0 else { return 0 }
    var bestScore = 0.0
    for columnIndex in 0..<columnCount {
        let values = rows.compactMap { row -> Int? in
            guard row.indices.contains(columnIndex) else { return nil }
            let text = row[columnIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = text.range(of: #"^(?:[^0-9]{0,3})([0-9]{1,3})(?:[^0-9]|$)"#, options: .regularExpression) else {
                return nil
            }
            let matched = String(text[match]).filter(\.isNumber)
            guard let value = Int(matched), value > 0 else { return nil }
            return value
        }
        guard values.count >= 5 else { continue }
        var ascending = 0
        var descending = 0
        for (left, right) in zip(values, values.dropFirst()) {
            if right - left == 1 { ascending += 1 }
            if left - right == 1 { descending += 1 }
        }
        let evidence = ascending + descending
        guard evidence >= 3 else { continue }
        let candidateScore = Double(ascending - descending) * 2.5
        if abs(candidateScore) > abs(bestScore) { bestScore = candidateScore }
    }
    return max(min(bestScore, 20), -20)
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
        if decision.isNoise {
            headers = makeOCRHeaders(columnCount: columnCount, providedHeaders: [])
            dataRows = Array(table.rows.dropFirst())
            headerSource = "discarded-leading-noise"
            headerDetected = false
            reason = decision.reason
        } else if decision.isHeader, let firstRow = table.rows.first {
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

private func detectHeaderRow(in table: OcrTable) -> (isHeader: Bool, isNoise: Bool, reason: String) {
    guard table.rows.count >= 3, table.columnCount > 0 else {
        return (false, false, "행이 부족해 첫 행 헤더를 자동 판정하지 않았습니다.")
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
    let firstRowHasBodySignals = bodyIdentitySignalCount(in: table.rows[0]) >= 2
    let leadingNoise = outlierSignal
        && sequentialRowDirectionScore(Array(table.rows.dropFirst())) >= 7.5
        && (!enoughFilledCells
            || firstProfile.averageLength > restAverage.averageLength * 1.45
            || firstProfile.longCellRatio > restAverage.longCellRatio + 0.35)
    if leadingNoise {
        return (false, true, String(format: "반복 본문 밖의 첫 행을 사진 배경 문자로 제외했습니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
    }
    if firstRowHasBodySignals {
        return (false, false, String(format: "첫 행에서 전화·날짜·금액 등 본문 신호를 확인해 데이터로 유지했습니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
    }
    if enoughFilledCells && (digitSignal || lengthSignal || outlierSignal) {
        return (true, false, String(format: "첫 행의 형태가 나머지 행과 다릅니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
    }
    return (false, false, String(format: "첫 행을 데이터로 유지했습니다. distance=%.3f, rest=%.3f", firstDistance, restDistance))
}

private func bodyIdentitySignalCount(in row: [OcrCell]) -> Int {
    let text = row.map(\.text).joined(separator: " ")
    var signals = 0
    if text.range(of: #"(?:19|20)[0-9]{2}\s*[.\-/년]\s*[0-9]{1,2}"#, options: .regularExpression) != nil {
        signals += 1
    }
    if text.range(of: #"(?:01[016789])[\s-]?[0-9]{3,4}[\s-]?[0-9]{4}"#, options: .regularExpression) != nil {
        signals += 1
    }
    if text.range(of: #"(?:[0-9]{1,3},){1,2}[0-9]{3}"#, options: .regularExpression) != nil {
        signals += 1
    }
    if row.contains(where: { repeatedNameScore([$0.text]) > 0 }) {
        signals += 1
    }
    return signals
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
