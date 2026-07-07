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
    var expiresIn: Int?
}

struct GoogleDriveFile: Decodable, Sendable {
    var id: String
    var name: String
    var modifiedTime: String?
}

enum GoogleDriveSyncError: Error {
    case missingClientId
    case missingAuthCode
    case invalidURL
    case tokenRequestFailed
    case profileRequestFailed
    case driveRequestFailed(Int)
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
    private var webAuthSession: ASWebAuthenticationSession?

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
        let token = try await authorize(scopes: Self.profileScopes + Self.appDataScopes + Self.fileScopes, prompt: "consent")
        let profile = try await userProfile(accessToken: token.accessToken)
        return GoogleDriveAccount(
            email: profile.email,
            name: profile.name,
            picture: profile.picture,
            connectedAt: Date()
        )
    }

    func authorize(scopes: [String], prompt: String? = nil) async throws -> GoogleDriveToken {
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
        return try await exchangeCode(code, verifier: verifier)
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

    private func exchangeCode(_ code: String, verifier: String) async throws -> GoogleDriveToken {
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
        try validate(response)
        let token = try decoder.decode(TokenResponse.self, from: data)
        guard let accessToken = token.accessToken else { throw GoogleDriveSyncError.tokenRequestFailed }
        return GoogleDriveToken(accessToken: accessToken, expiresIn: token.expiresIn)
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
}

private struct TokenResponse: Decodable {
    var accessToken: String?
    var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
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
