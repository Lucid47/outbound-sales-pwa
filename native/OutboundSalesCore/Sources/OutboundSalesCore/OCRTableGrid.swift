import CoreGraphics
import Foundation

struct OCRTableGrid: Equatable, Sendable {
    let verticalBoundaries: [Double]
    let horizontalBoundaries: [Double]
    let verticalSlope: Double
    let horizontalSlope: Double
    let confidence: Double

    var columnCount: Int { max(verticalBoundaries.count - 1, 0) }
    var rowCount: Int { max(horizontalBoundaries.count - 1, 0) }
}

private struct GrayscaleBitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[(y * width) + x]
    }
}

private struct GridLineCandidate {
    let position: Double
    let strength: Double
    let slope: Double
}

func detectOCRTableGrid(in image: CGImage, maximumDimension: Int = 1_200) -> OCRTableGrid? {
    guard let bitmap = makeGrayscaleBitmap(from: image, maximumDimension: maximumDimension) else { return nil }
    let threshold = otsuThreshold(for: bitmap.pixels)
    let horizontalCandidates = detectGridLines(in: bitmap, threshold: threshold, axis: .horizontal)
    let verticalCandidates = detectGridLines(in: bitmap, threshold: threshold, axis: .vertical)
    let network = retainIntersectingGridNetwork(
        horizontal: horizontalCandidates,
        vertical: verticalCandidates,
        bitmap: bitmap,
        threshold: threshold
    )
    let horizontalBoundaries = selectGridBoundaries(network.horizontal, minimumCount: 4)
    let verticalBoundaries = selectGridBoundaries(network.vertical, minimumCount: 3)

    guard horizontalBoundaries.count >= 4, verticalBoundaries.count >= 3 else { return nil }
    let horizontalCoverage = (horizontalBoundaries.last ?? 0) - (horizontalBoundaries.first ?? 0)
    let verticalCoverage = (verticalBoundaries.last ?? 0) - (verticalBoundaries.first ?? 0)
    guard horizontalCoverage >= 0.30, verticalCoverage >= 0.30 else { return nil }

    let lineCountScore = min(Double(horizontalBoundaries.count + verticalBoundaries.count) / 20, 1)
    let coverageScore = min((horizontalCoverage + verticalCoverage) / 1.4, 1)
    let confidence = (lineCountScore * 0.55) + (coverageScore * 0.45)
    guard confidence >= 0.45 else { return nil }

    let horizontalSlope = medianSlope(of: network.horizontal)
        * Double(bitmap.width) / Double(bitmap.height)
    let verticalSlope = medianSlope(of: network.vertical)
        * Double(bitmap.height) / Double(bitmap.width)
    return OCRTableGrid(
        verticalBoundaries: verticalBoundaries,
        horizontalBoundaries: horizontalBoundaries,
        verticalSlope: verticalSlope,
        horizontalSlope: horizontalSlope,
        confidence: confidence
    )
}

private func medianSlope(of candidates: [GridLineCandidate]) -> Double {
    guard !candidates.isEmpty else { return 0 }
    let sorted = candidates.map(\.slope).sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle]
}

private enum GridAxis {
    case horizontal
    case vertical
}

private func makeGrayscaleBitmap(from image: CGImage, maximumDimension: Int) -> GrayscaleBitmap? {
    let scale = min(1, Double(maximumDimension) / Double(max(image.width, image.height)))
    let width = max(Int((Double(image.width) * scale).rounded()), 1)
    let height = max(Int((Double(image.height) * scale).rounded()), 1)
    var pixels = [UInt8](repeating: 255, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceGray()

    let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let baseAddress = bytes.baseAddress,
              let context = CGContext(
                  data: baseAddress,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return false }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return didDraw ? GrayscaleBitmap(width: width, height: height, pixels: pixels) : nil
}

private func otsuThreshold(for pixels: [UInt8]) -> UInt8 {
    var histogram = [Int](repeating: 0, count: 256)
    for pixel in pixels { histogram[Int(pixel)] += 1 }
    let total = pixels.count
    guard total > 0 else { return 150 }

    let weightedTotal = histogram.enumerated().reduce(0.0) { result, entry in
        result + (Double(entry.offset) * Double(entry.element))
    }
    var backgroundWeight = 0
    var backgroundSum = 0.0
    var bestVariance = -Double.infinity
    var bestThreshold = 150

    for value in 0..<256 {
        backgroundWeight += histogram[value]
        guard backgroundWeight > 0 else { continue }
        let foregroundWeight = total - backgroundWeight
        guard foregroundWeight > 0 else { break }
        backgroundSum += Double(value * histogram[value])
        let backgroundMean = backgroundSum / Double(backgroundWeight)
        let foregroundMean = (weightedTotal - backgroundSum) / Double(foregroundWeight)
        let difference = backgroundMean - foregroundMean
        let variance = Double(backgroundWeight * foregroundWeight) * difference * difference
        if variance > bestVariance {
            bestVariance = variance
            bestThreshold = value
        }
    }
    return UInt8(min(max(bestThreshold, 70), 205))
}

private func detectGridLines(
    in bitmap: GrayscaleBitmap,
    threshold: UInt8,
    axis: GridAxis
) -> [GridLineCandidate] {
    let alongLength = axis == .horizontal ? bitmap.width : bitmap.height
    let acrossLength = axis == .horizontal ? bitmap.height : bitmap.width
    guard alongLength >= 40, acrossLength >= 20 else { return [] }

    let sampleStep = max(alongLength / 700, 1)
    let sampledAlongLength = Double((alongLength + sampleStep - 1) / sampleStep)
    let margin = Int(Double(alongLength) * 0.38) + 2
    func accumulator(for slope: Double) -> (values: [Int], quality: Double) {
        var accumulator = [Int](repeating: 0, count: acrossLength + (margin * 2))
        for across in stride(from: 0, to: acrossLength, by: sampleStep) {
            for along in stride(from: 0, to: alongLength, by: sampleStep) {
                let x = axis == .horizontal ? along : across
                let y = axis == .horizontal ? across : along
                guard bitmap[x, y] <= threshold else { continue }
                let intercept = Int((Double(across) - (slope * Double(along))).rounded()) + margin
                if accumulator.indices.contains(intercept) { accumulator[intercept] += 1 }
            }
        }
        let smoothed = smooth(accumulator)
        let strongest = smoothed.sorted(by: >).prefix(min(40, smoothed.count))
        let quality = strongest.reduce(0.0) { $0 + pow(Double($1) / sampledAlongLength, 2) }
        return (smoothed, quality)
    }

    var bestAccumulator: [Int] = []
    var bestSlope = 0.0
    var bestQuality = -Double.infinity
    let coarseSlopes = stride(from: -0.35, through: 0.3501, by: 0.025).map { $0 }
    for slope in coarseSlopes {
        let result = accumulator(for: slope)
        if result.quality > bestQuality {
            bestQuality = result.quality
            bestAccumulator = result.values
            bestSlope = slope
        }
    }
    let refinementStart = max(bestSlope - 0.03, -0.35)
    let refinementEnd = min(bestSlope + 0.03, 0.35)
    for slope in stride(from: refinementStart, through: refinementEnd + 0.0001, by: 0.005) {
        let result = accumulator(for: slope)
        if result.quality > bestQuality {
            bestQuality = result.quality
            bestAccumulator = result.values
            bestSlope = slope
        }
    }

    guard let maximum = bestAccumulator.max(), maximum > 0 else { return [] }
    let absoluteMinimum = sampledAlongLength * 0.08
    let relativeMinimum = Double(maximum) * 0.12
    let minimumStrength = max(absoluteMinimum, relativeMinimum)
    var candidates: [GridLineCandidate] = []
    for index in 1..<(bestAccumulator.count - 1) {
        let value = bestAccumulator[index]
        guard Double(value) >= minimumStrength,
              value >= bestAccumulator[index - 1],
              value >= bestAccumulator[index + 1] else { continue }
        let intercept = Double(index - margin)
        let centerPosition = intercept + (bestSlope * Double(alongLength - 1) / 2)
        let normalized = centerPosition / Double(acrossLength)
        guard normalized >= 0, normalized <= 1 else { continue }
        candidates.append(GridLineCandidate(
            position: normalized,
            strength: Double(value) / sampledAlongLength,
            slope: bestSlope
        ))
    }
    return mergeNearbyLineCandidates(candidates)
}

private func smooth(_ values: [Int]) -> [Int] {
    guard values.count >= 3 else { return values }
    return values.indices.map { index in
        let lower = max(index - 1, 0)
        let upper = min(index + 1, values.count - 1)
        return values[lower...upper].reduce(0, +)
    }
}

private func mergeNearbyLineCandidates(_ candidates: [GridLineCandidate]) -> [GridLineCandidate] {
    let sorted = candidates.sorted { $0.position < $1.position }
    var groups: [[GridLineCandidate]] = []
    for candidate in sorted {
        if let last = groups.last,
           let strongest = last.max(by: { $0.strength < $1.strength }),
           abs(strongest.position - candidate.position) <= 0.006 {
            groups[groups.count - 1].append(candidate)
        } else {
            groups.append([candidate])
        }
    }
    return groups.compactMap { $0.max(by: { $0.strength < $1.strength }) }
}

private func selectGridBoundaries(_ candidates: [GridLineCandidate], minimumCount: Int) -> [Double] {
    guard candidates.count >= minimumCount else { return [] }
    let sorted = candidates.sorted { $0.position < $1.position }
    let strongest = sorted.map(\.strength).max() ?? 0
    let retained = sorted.filter { $0.strength >= max(strongest * 0.08, 0.08) }
    guard retained.count >= minimumCount else { return [] }

    var result: [GridLineCandidate] = []
    for candidate in retained {
        if let last = result.last, candidate.position - last.position < 0.020 {
            if candidate.strength > last.strength { result[result.count - 1] = candidate }
        } else {
            result.append(candidate)
        }
    }
    return result.map(\.position)
}

private func retainIntersectingGridNetwork(
    horizontal: [GridLineCandidate],
    vertical: [GridLineCandidate],
    bitmap: GrayscaleBitmap,
    threshold: UInt8
) -> (horizontal: [GridLineCandidate], vertical: [GridLineCandidate]) {
    var horizontalLines = horizontal.filter { $0.strength >= 0.20 && $0.position >= 0.005 && $0.position <= 0.995 }
    var verticalLines = vertical.filter { $0.strength >= 0.20 && $0.position >= 0.005 && $0.position <= 0.995 }
    guard horizontalLines.count >= 4, verticalLines.count >= 3 else { return ([], []) }

    for _ in 0..<4 {
        let minimumVerticalSupport = max(3, min(8, Int(ceil(Double(horizontalLines.count) * 0.10))))
        verticalLines = verticalLines.filter { verticalLine in
            horizontalLines.filter {
                linesIntersectDark(
                    horizontal: $0,
                    vertical: verticalLine,
                    bitmap: bitmap,
                    threshold: threshold
                )
            }.count >= minimumVerticalSupport
        }
        let minimumHorizontalSupport = max(3, min(8, Int(ceil(Double(verticalLines.count) * 0.10))))
        horizontalLines = horizontalLines.filter { horizontalLine in
            verticalLines.filter {
                linesIntersectDark(
                    horizontal: horizontalLine,
                    vertical: $0,
                    bitmap: bitmap,
                    threshold: threshold
                )
            }.count >= minimumHorizontalSupport
        }
        if horizontalLines.count < 4 || verticalLines.count < 3 { return ([], []) }
    }
    return (horizontalLines, verticalLines)
}

private func linesIntersectDark(
    horizontal: GridLineCandidate,
    vertical: GridLineCandidate,
    bitmap: GrayscaleBitmap,
    threshold: UInt8
) -> Bool {
    var x = vertical.position * Double(bitmap.width - 1)
    var y = horizontal.position * Double(bitmap.height - 1)
    for _ in 0..<2 {
        x = (vertical.position * Double(bitmap.width - 1))
            + (vertical.slope * (y - (Double(bitmap.height - 1) / 2)))
        y = (horizontal.position * Double(bitmap.height - 1))
            + (horizontal.slope * (x - (Double(bitmap.width - 1) / 2)))
    }
    let centerX = Int(x.rounded())
    let centerY = Int(y.rounded())
    guard centerX >= 0, centerX < bitmap.width, centerY >= 0, centerY < bitmap.height else { return false }
    let radius = max(2, max(bitmap.width, bitmap.height) / 450)
    for pixelY in max(centerY - radius, 0)...min(centerY + radius, bitmap.height - 1) {
        for pixelX in max(centerX - radius, 0)...min(centerX + radius, bitmap.width - 1) {
            if bitmap[pixelX, pixelY] <= threshold { return true }
        }
    }
    return false
}
