import Foundation

public enum FieldKey: String, CaseIterable, Codable, Sendable {
    case name
    case phoneNumber
    case address
    case ownedAddress
    case parcelAddress
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
    .name: ["고객명", "고객 이름", "이름", "성명", "수령인", "받는분", "받는 사람", "거래처명", "회사명", "name", "customer", "customername"],
    .phoneNumber: ["연락처", "전화번호", "휴대폰", "핸드폰", "휴대전화", "휴대폰번호", "핸드폰번호", "모바일", "mobile", "phone", "tel", "telephone"],
    .address: ["주소", "주소지", "거주지", "자택주소", "우편물주소", "우편물수령지", "우편물 수령지", "우편주소", "우편수령지", "수령지", "배송지", "방문주소", "사업장주소", "고객주소", "도로명주소", "지번주소", "address", "addr", "location"],
    .ownedAddress: ["소유", "소유지", "소유주소", "보유부동산", "보유주소", "물건지", "소재지", "ownedaddress", "propertyaddress"],
    .parcelAddress: ["소유지번", "지번", "필지", "토지지번", "parcel", "parceladdress", "lotnumber"],
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
