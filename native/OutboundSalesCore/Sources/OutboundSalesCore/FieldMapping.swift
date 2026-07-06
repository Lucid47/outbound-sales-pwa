import Foundation

public enum FieldKey: String, CaseIterable, Codable, Sendable {
    case name
    case phoneNumber
    case address
    case birthDate
    case notes
    case latitude
    case longitude
}

public struct FieldMapping: Equatable, Sendable {
    public var values: [FieldKey: Int?]

    public init(values: [FieldKey: Int?] = [:]) {
        var initial: [FieldKey: Int?] = [:]
        for key in FieldKey.allCases {
            initial[key] = values[key] ?? nil
        }
        self.values = initial
    }

    public subscript(key: FieldKey) -> Int? {
        get { values[key] ?? nil }
        set { values[key] = newValue }
    }
}

public let fieldAliases: [FieldKey: [String]] = [
    .name: ["고객명", "고객 이름", "이름", "성명", "거래처명", "회사명", "name", "customer", "customername"],
    .phoneNumber: ["연락처", "전화번호", "휴대폰", "핸드폰", "휴대전화", "mobile", "phone", "tel", "telephone"],
    .address: ["주소", "우편물주소", "우편주소", "방문주소", "사업장주소", "고객주소", "address", "addr", "location"],
    .birthDate: ["생년월일", "생일", "출생일", "출생년도", "생년", "birth", "birthday", "birthdate", "dateofbirth", "dob"],
    .notes: ["메모", "비고", "기타", "기타사항", "담당자메모", "notes", "note", "memo", "remark"],
    .latitude: ["위도", "lat", "latitude", "y", "goaly"],
    .longitude: ["경도", "lng", "lon", "long", "longitude", "x", "goalx"]
]

public func normalizeHeader(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
}

public func detectMapping(headers: [String]) -> FieldMapping {
    var mapping = FieldMapping()
    for (index, header) in headers.enumerated() {
        let normalized = normalizeHeader(header)
        for field in FieldKey.allCases where mapping[field] == nil {
            let aliases = fieldAliases[field, default: []].map(normalizeHeader)
            if aliases.contains(normalized) {
                mapping[field] = index
            }
        }
    }
    return mapping
}

