import Foundation

public func normalizeAddressText(_ address: String) -> String {
    address
        .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
}

public func normalizeAddressWhitespace(_ value: String) -> String {
    value
        .replacingOccurrences(of: "[，、]", with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

public func extractRegion(_ address: String) -> String {
    let normalized = normalizeAddressWhitespace(normalizeAddressText(address))
    let parts = normalized.split(separator: " ").map(String.init)
    guard !parts.isEmpty else { return "주소 없음" }

    var baseIndex = parts.lastIndex { $0.hasSuffix("구") || $0.hasSuffix("군") }
    if baseIndex == nil {
        baseIndex = parts.firstIndex { $0.hasSuffix("시") }
    }
    guard let baseIndex else {
        return parts.first(where: { !isAddressNumber($0) }) ?? "지역 미확인"
    }

    let afterBase = Array(parts.dropFirst(baseIndex + 1))
    let dong = afterBase.first(where: isAdministrativeArea)
    let road = findRoadAddress(afterBase)?.road ?? ""
    let regionParts = [parts[baseIndex], dong, road].compactMap { $0 }.filter { !$0.isEmpty }
    return regionParts.isEmpty ? "지역 미확인" : regionParts.joined(separator: " ")
}

public func normalizeAddressForMapSearch(_ address: String) -> String {
    let normalized = normalizeAddressWhitespace(normalizeAddressText(address))
    let parts = normalized.split(separator: " ").map(String.init)
    guard let roadAddress = findRoadAddress(parts) else { return normalized }
    var base = Array(parts.prefix(roadAddress.index)) + [roadAddress.road]
    if !roadAddress.buildingNumber.isEmpty {
        base.append(roadAddress.buildingNumber)
    }
    return base.joined(separator: " ")
}

public func isSearchableAddress(_ address: String) -> Bool {
    let normalized = normalizeAddressWhitespace(normalizeAddressText(address))
    guard !normalized.isEmpty, !normalized.contains("주소 미확인") else { return false }
    return findRoadAddress(normalized.split(separator: " ").map(String.init)) != nil
}

public func isAddressNumber(_ value: String) -> Bool {
    value.range(of: #"^\d+(?:-\d+)?(?:번지|호)?$"#, options: .regularExpression) != nil
}

public func isAdministrativeArea(_ value: String) -> Bool {
    value.range(of: #"^(?!\d).+(?:동|읍|면|리)$"#, options: .regularExpression) != nil
}

public struct RoadAddress: Equatable, Sendable {
    public let index: Int
    public let road: String
    public let buildingNumber: String
}

public func findRoadAddress(_ parts: [String]) -> RoadAddress? {
    for index in parts.indices {
        guard let parsed = parseRoadAddressToken(parts[index]) else { continue }
        let next = index + 1 < parts.count ? parts[index + 1] : ""
        let nextBranch = next.range(of: #"^(\d+(?:번)?길)(\d+(?:-\d+)?)?(?:번지|호)?$"#, options: .regularExpression)

        if nextBranch != nil, parsed.road.hasSuffix("대로") || parsed.road.hasSuffix("로") {
            let following = index + 2 < parts.count ? parts[index + 2] : ""
            let nextParts = captureGroups(pattern: #"^(\d+(?:번)?길)(\d+(?:-\d+)?)?(?:번지|호)?$"#, value: next)
            let buildingNumber = (nextParts[safe: 1] ?? "").isEmpty && isAddressNumber(following) ? following : (nextParts[safe: 1] ?? "")
            return RoadAddress(index: index, road: "\(parsed.road)\(nextParts.first ?? "")", buildingNumber: buildingNumber)
        }

        if !parsed.buildingNumber.isEmpty {
            return RoadAddress(index: index, road: parsed.road, buildingNumber: parsed.buildingNumber)
        }
        if !next.isEmpty, isAddressNumber(next) {
            return RoadAddress(index: index, road: parsed.road, buildingNumber: next)
        }
        return RoadAddress(index: index, road: parsed.road, buildingNumber: parsed.buildingNumber)
    }
    return nil
}

func parseRoadAddressToken(_ value: String) -> (road: String, buildingNumber: String)? {
    if isAddressNumber(value) { return nil }
    if let groups = optionalCaptureGroups(pattern: #"^(.+(?:대로|로)\d+(?:번)?길)(\d+(?:-\d+)?)?(?:번지|호)?$"#, value: value) {
        return (groups[0], groups[safe: 1] ?? "")
    }
    if let groups = optionalCaptureGroups(pattern: #"^(.+?(?:대로|로|길))(\d+(?:-\d+)?)?(?:번지|호)?$"#, value: value) {
        return (groups[0], groups[safe: 1] ?? "")
    }
    return nil
}

func optionalCaptureGroups(pattern: String, value: String) -> [String]? {
    let groups = captureGroups(pattern: pattern, value: value)
    return groups.isEmpty ? nil : groups
}

func captureGroups(pattern: String, value: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
        return []
    }
    return (1..<match.numberOfRanges).map { index in
        let range = match.range(at: index)
        guard let swiftRange = Range(range, in: value) else { return "" }
        return String(value[swiftRange])
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

