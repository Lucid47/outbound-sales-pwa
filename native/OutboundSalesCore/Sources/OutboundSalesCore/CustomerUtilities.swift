import Foundation

public enum CoordinateKind: Sendable {
    case latitude
    case longitude
}

public func cleanPhone(_ phoneNumber: String) -> String {
    let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.filter(\.isNumber)
    return trimmed.hasPrefix("+") ? "+\(digits)" : String(digits)
}

public func hasDialablePhone(_ phoneNumber: String) -> Bool {
    cleanPhone(phoneNumber).filter(\.isNumber).count >= 7
}

public func smsURLString(for phoneNumber: String) -> String {
    "sms:\(cleanPhone(phoneNumber).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
}

public func parseCoordinate(_ value: String, kind: CoordinateKind) -> Double? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    guard !normalized.isEmpty, let coordinate = Double(normalized), coordinate.isFinite else { return nil }
    switch kind {
    case .latitude:
        return (-90...90).contains(coordinate) ? coordinate : nil
    case .longitude:
        return (-180...180).contains(coordinate) ? coordinate : nil
    }
}

public func parseBirthDate(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let digits = trimmed.filter(\.isNumber)
    let year: String
    let month: String
    let day: String

    if digits.count >= 8 {
        year = String(digits.prefix(4))
        month = String(digits.dropFirst(4).prefix(2))
        day = String(digits.dropFirst(6).prefix(2))
    } else if digits.count == 6 {
        let yy = Int(digits.prefix(2)) ?? 0
        let currentYY = Calendar.current.component(.year, from: Date()) % 100
        year = String(yy > currentYY ? 1900 + yy : 2000 + yy)
        month = String(digits.dropFirst(2).prefix(2))
        day = String(digits.dropFirst(4).prefix(2))
    } else if digits.count == 4 {
        year = String(digits)
        month = "01"
        day = "01"
    } else {
        return nil
    }

    let iso = "\(year)-\(month)-\(day)"
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    guard let date = formatter.date(from: iso), formatter.string(from: date) == iso else { return nil }
    return iso
}

public func calculateAge(birthDate: String, now: Date = Date()) -> Int? {
    let parts = birthDate.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    let nowComponents = Calendar.current.dateComponents([.year, .month, .day], from: now)
    var age = (nowComponents.year ?? 0) - parts[0]
    if (nowComponents.month ?? 0) < parts[1] || ((nowComponents.month ?? 0) == parts[1] && (nowComponents.day ?? 0) < parts[2]) {
        age -= 1
    }
    return age
}
