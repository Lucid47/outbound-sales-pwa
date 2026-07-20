import AuthenticationServices
import CryptoKit
import Foundation
import OutboundSalesCore
import Security
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct GoogleDriveAccount: Codable, Equatable, Sendable {
    public var email: String
    public var name: String
    public var picture: String?
    public var connectedAt: Date
}

struct GoogleDriveToken: Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scopes: Set<String>

    func isValid(for requiredScopes: Set<String>, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) > 60 && requiredScopes.isSubset(of: scopes)
    }
}

struct GoogleDriveFile: Decodable, Sendable {
    var id: String
    var name: String
    var modifiedTime: String?
}

enum GoogleDriveSyncError: LocalizedError {
    case missingClientId
    case missingAuthCode
    case invalidURL
    case tokenRequestFailed
    case tokenRefreshFailed
    case authorizationRequired
    case missingRefreshToken
    case credentialStoreFailed(Int32)
    case profileRequestFailed
    case driveRequestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingClientId:
            return "Google iOS OAuth Client ID가 앱에 포함되지 않았습니다."
        case .missingAuthCode:
            return "Google 인증 응답에서 승인 코드를 받지 못했습니다."
        case .invalidURL:
            return "Google 인증 또는 Drive 요청 주소를 만들지 못했습니다."
        case .tokenRequestFailed:
            return "Google 인증 토큰을 발급받지 못했습니다."
        case .tokenRefreshFailed:
            return "Google 인증을 자동 갱신하지 못했습니다. 잠시 후 다시 시도하세요."
        case .authorizationRequired:
            return "Google 계정 연결이 만료되었습니다. 계정을 한 번 다시 연결하세요."
        case .missingRefreshToken:
            return "장기 인증 정보를 받지 못했습니다. Google 계정을 다시 연결하세요."
        case let .credentialStoreFailed(status):
            return "Google 인증 정보를 안전하게 저장하지 못했습니다. (Keychain \(status))"
        case .profileRequestFailed:
            return "Google 계정 정보를 확인하지 못했습니다."
        case let .driveRequestFailed(statusCode):
            return "Google 서버 요청에 실패했습니다. (HTTP \(statusCode))"
        }
    }
}

final class GoogleDriveSyncService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let profileScopes = ["openid", "email", "profile"]
    static let appDataScopes = ["https://www.googleapis.com/auth/drive.appdata"]
    static let fileScopes = ["https://www.googleapis.com/auth/drive.file"]

    private let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!
    private let driveAPIBaseURL = URL(string: "https://www.googleapis.com/drive/v3")!
    private let driveUploadBaseURL = URL(string: "https://www.googleapis.com/upload/drive/v3")!
    private let syncFileName = "soheega-ganda-native-sync.json"

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let credentialStore = GoogleDriveCredentialStore()
    private var webAuthSession: ASWebAuthenticationSession?
    private var cachedToken: GoogleDriveToken?

    override init() {
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        super.init()
    }

    var isConfigured: Bool {
        !clientId.isEmpty
    }

    var hasStoredAuthorization: Bool {
        credentialStore.hasCredential
    }

    static var hasStoredAuthorization: Bool {
        GoogleDriveCredentialStore().hasCredential
    }

    private var clientId: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GoogleDriveOAuthClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self.normalizedInfoPlistValue(value)
    }

    private var redirectScheme: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "GoogleDriveRedirectScheme") as? String,
           !Self.normalizedInfoPlistValue(configured).isEmpty {
            return Self.normalizedInfoPlistValue(configured)
        }
        return Bundle.main.bundleIdentifier ?? "com.lucid47.outboundsales"
    }

    private var redirectURI: String {
        "\(redirectScheme):/oauth2redirect"
    }

    func connect() async throws -> GoogleDriveAccount {
        let requestedScopes = Self.profileScopes + Self.appDataScopes + Self.fileScopes
        let token = try await authorizeInteractively(scopes: requestedScopes, prompt: "consent")
        let profile = try await userProfile(accessToken: token.accessToken)
        guard let refreshToken = token.refreshToken else {
            throw GoogleDriveSyncError.missingRefreshToken
        }
        try credentialStore.save(
            GoogleDriveCredential(
                refreshToken: refreshToken,
                scopes: Array(token.scopes).sorted()
            )
        )
        cachedToken = token
        return GoogleDriveAccount(
            email: profile.email,
            name: profile.name,
            picture: profile.picture,
            connectedAt: Date()
        )
    }

    func accessToken(for scopes: [String]) async throws -> String {
        guard !clientId.isEmpty else { throw GoogleDriveSyncError.missingClientId }
        let requiredScopes = Set(scopes)
        if let cachedToken, cachedToken.isValid(for: requiredScopes) {
            return cachedToken.accessToken
        }

        guard let credential = try credentialStore.load() else {
            throw GoogleDriveSyncError.authorizationRequired
        }
        let grantedScopes = Set(credential.scopes)
        guard requiredScopes.isSubset(of: grantedScopes) else {
            throw GoogleDriveSyncError.authorizationRequired
        }

        let token = try await refreshAccessToken(credential: credential)
        cachedToken = token
        return token.accessToken
    }

    func clearAuthorization() {
        cachedToken = nil
        try? credentialStore.delete()
    }

    private func authorizeInteractively(scopes: [String], prompt: String? = nil) async throws -> GoogleDriveToken {
        guard !clientId.isEmpty else { throw GoogleDriveSyncError.missingClientId }
        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Array(Set(scopes)).joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        if let prompt {
            components?.queryItems?.append(URLQueryItem(name: "prompt", value: prompt))
        }
        guard let url = components?.url else { throw GoogleDriveSyncError.invalidURL }

        let callbackURL = try await callbackURL(for: url)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value else {
            throw GoogleDriveSyncError.missingAuthCode
        }
        return try await exchangeCode(code, verifier: verifier, requestedScopes: Set(scopes))
    }

    func findAppDataSyncFile(accessToken: String) async throws -> GoogleDriveFile? {
        var components = URLComponents(url: driveAPIBaseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime)"),
            URLQueryItem(name: "q", value: "name='\(syncFileName)' and trashed=false")
        ]
        guard let url = components?.url else { throw GoogleDriveSyncError.invalidURL }
        let response: DriveFileListResponse = try await driveJSON(accessToken: accessToken, url: url)
        return response.files.first
    }

    func downloadBackup(accessToken: String, fileId: String) async throws -> NativeFullBackup {
        var components = URLComponents(url: driveAPIBaseURL.appendingPathComponent("files/\(fileId)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "alt", value: "media")]
        guard let url = components?.url else { throw GoogleDriveSyncError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        if let backup = try? decoder.decode(NativeFullBackup.self, from: data) {
            return backup
        }
        let snapshot = try decoder.decode(NativeAppSnapshot.self, from: data)
        return NativeFullBackup(schemaVersion: 1, snapshot: snapshot, photos: [])
    }

    @discardableResult
    func createAppDataSyncFile(accessToken: String, backup: NativeFullBackup) async throws -> GoogleDriveFile {
        try await uploadBackup(
            accessToken: accessToken,
            name: syncFileName,
            backup: backup,
            method: "POST",
            uploadURL: driveUploadBaseURL.appendingPathComponent("files"),
            metadataExtra: ["parents": ["appDataFolder"]]
        )
    }

    @discardableResult
    func updateAppDataSyncFile(accessToken: String, fileId: String, backup: NativeFullBackup) async throws -> GoogleDriveFile {
        try await uploadBackup(
            accessToken: accessToken,
            name: syncFileName,
            backup: backup,
            method: "PATCH",
            uploadURL: driveUploadBaseURL.appendingPathComponent("files/\(fileId)")
        )
    }

    @discardableResult
    func createVisibleBackup(accessToken: String, fileName: String, backup: NativeFullBackup) async throws -> GoogleDriveFile {
        try await uploadBackup(
            accessToken: accessToken,
            name: fileName,
            backup: backup,
            method: "POST",
            uploadURL: driveUploadBaseURL.appendingPathComponent("files")
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }

    private func callbackURL(for url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectScheme) { callbackURL, error in
                self.webAuthSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? GoogleDriveSyncError.missingAuthCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }
    }

    private func exchangeCode(_ code: String, verifier: String, requestedScopes: Set<String>) async throws -> GoogleDriveToken {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            "client_id": clientId,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let token = try? decoder.decode(TokenResponse.self, from: data),
              let accessToken = token.accessToken else {
            throw GoogleDriveSyncError.tokenRequestFailed
        }
        return GoogleDriveToken(
            accessToken: accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Self.expirationDate(expiresIn: token.expiresIn),
            scopes: Self.scopes(from: token.scope, fallback: requestedScopes)
        )
    }

    private func refreshAccessToken(credential: GoogleDriveCredential) async throws -> GoogleDriveToken {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            "client_id": clientId,
            "refresh_token": credential.refreshToken,
            "grant_type": "refresh_token"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveSyncError.tokenRefreshFailed
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let oauthError = try? decoder.decode(OAuthErrorResponse.self, from: data),
               oauthError.error == "invalid_grant" {
                clearAuthorization()
                throw GoogleDriveSyncError.authorizationRequired
            }
            throw GoogleDriveSyncError.tokenRefreshFailed
        }

        guard let responseToken = try? decoder.decode(TokenResponse.self, from: data),
              let accessToken = responseToken.accessToken else {
            throw GoogleDriveSyncError.tokenRefreshFailed
        }

        let scopes = Self.scopes(from: responseToken.scope, fallback: Set(credential.scopes))
        let refreshToken = responseToken.refreshToken ?? credential.refreshToken
        if responseToken.refreshToken != nil || scopes != Set(credential.scopes) {
            try credentialStore.save(
                GoogleDriveCredential(
                    refreshToken: refreshToken,
                    scopes: Array(scopes).sorted()
                )
            )
        }
        return GoogleDriveToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Self.expirationDate(expiresIn: responseToken.expiresIn),
            scopes: scopes
        )
    }

    private func userProfile(accessToken: String) async throws -> UserInfoResponse {
        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let profile = try decoder.decode(UserInfoResponse.self, from: data)
        guard !profile.email.isEmpty else { throw GoogleDriveSyncError.profileRequestFailed }
        return profile
    }

    private func uploadBackup(
        accessToken: String,
        name: String,
        backup: NativeFullBackup,
        method: String,
        uploadURL: URL,
        metadataExtra: [String: Any] = [:]
    ) async throws -> GoogleDriveFile {
        var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id,name,modifiedTime")
        ]
        guard let url = components?.url else { throw GoogleDriveSyncError.invalidURL }
        let payload = try encoder.encode(backup)
        let body = try multipartBody(metadata: ["name": name, "mimeType": "application/json"].merging(metadataExtra) { _, new in new }, payload: payload)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(GoogleDriveFile.self, from: data)
    }

    private func driveJSON<T: Decodable>(accessToken: String, url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleDriveSyncError.driveRequestFailed(httpResponse.statusCode)
        }
    }

    private func multipartBody(metadata: [String: Any], payload: Data) throws -> (data: Data, contentType: String) {
        let boundary = "outbound-sales-\(UUID().uuidString)"
        var data = Data()
        data.appendString("--\(boundary)\r\n")
        data.appendString("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        data.append(try JSONSerialization.data(withJSONObject: metadata))
        data.appendString("\r\n--\(boundary)\r\n")
        data.appendString("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        data.append(payload)
        data.appendString("\r\n--\(boundary)--")
        return (data, "multipart/related; boundary=\(boundary)")
    }

    private func formURLEncoded(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func randomCodeVerifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func normalizedInfoPlistValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") {
            return ""
        }
        return trimmed
    }

    private static func expirationDate(expiresIn: Int?) -> Date {
        Date().addingTimeInterval(TimeInterval(max(expiresIn ?? 3600, 60)))
    }

    private static func scopes(from value: String?, fallback: Set<String>) -> Set<String> {
        guard let value, !value.isEmpty else { return fallback }
        return Set(value.split(whereSeparator: \.isWhitespace).map(String.init))
    }
}

private struct TokenResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Int?
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

private struct OAuthErrorResponse: Decodable {
    var error: String
}

private struct GoogleDriveCredential: Codable {
    var refreshToken: String
    var scopes: [String]
}

private struct GoogleDriveCredentialStore {
    private let service = "com.lucid47.outboundsales.google-drive.oauth"
    private let account = "primary"

    var hasCredential: Bool {
        (try? load()) != nil
    }

    func load() throws -> GoogleDriveCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GoogleDriveSyncError.credentialStoreFailed(status)
        }
        guard let credential = try? JSONDecoder().decode(GoogleDriveCredential.self, from: data) else {
            try delete()
            return nil
        }
        return credential
    }

    func save(_ credential: GoogleDriveCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw GoogleDriveSyncError.credentialStoreFailed(updateStatus)
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GoogleDriveSyncError.credentialStoreFailed(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleDriveSyncError.credentialStoreFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct UserInfoResponse: Decodable {
    var email: String
    var name: String
    var picture: String?
}

private struct DriveFileListResponse: Decodable {
    var files: [GoogleDriveFile]
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
