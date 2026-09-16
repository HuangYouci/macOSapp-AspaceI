import CryptoKit
import Foundation

struct PKCE: Sendable {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        let verifier = Data(bytes).base64URLEncoded
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

/// 一次 OAuth 授權的起始資料；loopback 類型需要先開好本機埠再開瀏覽器。
struct OAuthAuthorization: Sendable {
    let platform: PlatformKind
    let url: URL
    let pkce: PKCE
    let state: String
    let redirectURI: String
    let callbackPort: UInt16?
    let callbackPath: String?
}

struct OAuthCredential: Sendable {
    let platform: PlatformKind
    let data: Data
    let email: String?
}

struct GitHubDeviceCode: Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let interval: Int
    let expiresAt: Date
}

/// 各平台官方客戶端隨 App 散佈的公開 OAuth client（installed-app，不視為機密）。
enum OAuthClient {
    static let codexID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let codexAuthorize = "https://auth.openai.com/oauth/authorize"
    static let codexToken = "https://auth.openai.com/oauth/token"
    static let codexPort: UInt16 = 1455

    static let claudeID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let claudeAuthorize = "https://claude.com/cai/oauth/authorize"
    static let claudeToken = "https://platform.claude.com/v1/oauth/token"
    static let claudeRedirect = "https://platform.claude.com/oauth/code/callback"
    static let claudeScopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

    static let antigravityID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    static let antigravitySecret = "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"
    static let antigravityPort: UInt16 = 51121
    static let antigravityScopes = [
        // openid 才拿得到 id_token，官方 token 檔靠它標示目前的登入身分。
        "openid",
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs"
    ].joined(separator: " ")

    static let githubID = "Iv1.b507a08c87ecfe98"
}

final class OAuthService: Sendable {
    static let shared = OAuthService()
    private init() {}

    // MARK: 授權網址

    static func authorization(for platform: PlatformKind, pkce: PKCE = .generate(), state: String = UUID().uuidString) -> OAuthAuthorization? {
        switch platform {
        case .codex:
            let redirect = "http://localhost:\(OAuthClient.codexPort)/auth/callback"
            let url = makeURL(OAuthClient.codexAuthorize, [
                "response_type": "code",
                "client_id": OAuthClient.codexID,
                "redirect_uri": redirect,
                "scope": "openid profile email offline_access",
                "code_challenge": pkce.challenge,
                "code_challenge_method": "S256",
                "id_token_add_organizations": "true",
                "codex_cli_simplified_flow": "true",
                "state": state
            ])
            return url.map { OAuthAuthorization(platform: platform, url: $0, pkce: pkce, state: state, redirectURI: redirect, callbackPort: OAuthClient.codexPort, callbackPath: "/auth/callback") }
        case .claude:
            let url = makeURL(OAuthClient.claudeAuthorize, [
                "code": "true",
                "client_id": OAuthClient.claudeID,
                "response_type": "code",
                "redirect_uri": OAuthClient.claudeRedirect,
                "scope": OAuthClient.claudeScopes,
                "code_challenge": pkce.challenge,
                "code_challenge_method": "S256",
                "state": state
            ])
            return url.map { OAuthAuthorization(platform: platform, url: $0, pkce: pkce, state: state, redirectURI: OAuthClient.claudeRedirect, callbackPort: nil, callbackPath: nil) }
        case .antigravity:
            let redirect = "http://localhost:\(OAuthClient.antigravityPort)/oauth-callback"
            let url = makeURL("https://accounts.google.com/o/oauth2/v2/auth", [
                "client_id": OAuthClient.antigravityID,
                "redirect_uri": redirect,
                "response_type": "code",
                "scope": OAuthClient.antigravityScopes,
                "access_type": "offline",
                "prompt": "consent",
                "code_challenge": pkce.challenge,
                "code_challenge_method": "S256",
                "state": state
            ])
            return url.map { OAuthAuthorization(platform: platform, url: $0, pkce: pkce, state: state, redirectURI: redirect, callbackPort: OAuthClient.antigravityPort, callbackPath: "/oauth-callback") }
        case .githubCopilot:
            return nil
        }
    }

    // MARK: 換發 token

    func exchange(_ authorization: OAuthAuthorization, code: String) async throws -> OAuthCredential {
        switch authorization.platform {
        case .codex:
            let value = try await postForm(OAuthClient.codexToken, [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": authorization.redirectURI,
                "client_id": OAuthClient.codexID,
                "code_verifier": authorization.pkce.verifier
            ])
            return try Self.codexCredential(from: value)
        case .claude:
            let value = try await postJSON(OAuthClient.claudeToken, [
                "grant_type": "authorization_code",
                "client_id": OAuthClient.claudeID,
                "code": code,
                "redirect_uri": authorization.redirectURI,
                "code_verifier": authorization.pkce.verifier,
                "state": authorization.state
            ])
            return try Self.claudeCredential(from: value)
        case .antigravity:
            let value = try await postForm("https://oauth2.googleapis.com/token", [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": authorization.redirectURI,
                "client_id": OAuthClient.antigravityID,
                "client_secret": OAuthClient.antigravitySecret,
                "code_verifier": authorization.pkce.verifier
            ])
            var credential = try Self.antigravityCredential(from: value)
            if let token = value["access_token"] as? String {
                credential = OAuthCredential(platform: .antigravity, data: credential.data, email: await googleEmail(accessToken: token))
            }
            return credential
        case .githubCopilot:
            throw OAuthError.invalidResponse
        }
    }

    /// Claude 授權頁顯示的是 `code#state`，貼上時兩種形式都接受。
    static func parseClaudeCode(_ raw: String) -> (code: String, state: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed), let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            return (code, components.queryItems?.first(where: { $0.name == "state" })?.value)
        }
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : nil)
    }

    static func codexCredential(from value: [String: Any]) throws -> OAuthCredential {
        guard let accessToken = value["access_token"] as? String,
              let refreshToken = value["refresh_token"] as? String,
              let idToken = value["id_token"] as? String else { throw OAuthError.invalidResponse }
        let claims = jwtClaims(idToken) ?? [:]
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let tokens: [String: Any] = [
            "id_token": idToken,
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "account_id": auth?["chatgpt_account_id"] as? String ?? NSNull()
        ]
        let object: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "tokens": tokens,
            "last_refresh": ISO8601DateFormatter().string(from: .now)
        ]
        return OAuthCredential(platform: .codex, data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), email: claims["email"] as? String)
    }

    static func claudeCredential(from value: [String: Any], now: Date = .now) throws -> OAuthCredential {
        guard let accessToken = value["access_token"] as? String,
              let refreshToken = value["refresh_token"] as? String else { throw OAuthError.invalidResponse }
        let expiresIn = (value["expires_in"] as? NSNumber)?.doubleValue ?? 28_800
        let scopes = (value["scope"] as? String)?.split(separator: " ").map(String.init) ?? OAuthClient.claudeScopes.split(separator: " ").map(String.init)
        let object: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": refreshToken,
                "expiresAt": Int((now.timeIntervalSince1970 + expiresIn) * 1000),
                "scopes": scopes
            ] as [String: Any]
        ]
        let email = (value["account"] as? [String: Any])?["email_address"] as? String
        return OAuthCredential(platform: .claude, data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), email: email)
    }

    static func antigravityCredential(from value: [String: Any], now: Date = .now) throws -> OAuthCredential {
        guard let accessToken = value["access_token"] as? String,
              let refreshToken = value["refresh_token"] as? String else { throw OAuthError.missingRefreshToken }
        let expiresIn = (value["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
        var object: [String: Any] = [
            "auth_method": "consumer",
            "token": [
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "token_type": "Bearer",
                "expiry": ISO8601DateFormatter().string(from: now.addingTimeInterval(expiresIn))
            ]
        ]
        // id_token 是官方 App 與 AspaceI 判斷這份憑證屬於誰的依據，登入時就留下來。
        let idToken = value["id_token"] as? String
        if let idToken, !idToken.isEmpty { object["id_token"] = idToken }
        let email = idToken.flatMap { jwtClaims($0)?["email"] as? String }
        return OAuthCredential(platform: .antigravity, data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), email: email)
    }

    // MARK: GitHub 裝置流程

    func requestGitHubDeviceCode() async throws -> GitHubDeviceCode {
        let value = try await postForm("https://github.com/login/device/code", [
            "client_id": OAuthClient.githubID,
            "scope": "read:user"
        ])
        guard let deviceCode = value["device_code"] as? String,
              let userCode = value["user_code"] as? String,
              let uri = (value["verification_uri"] as? String).flatMap(URL.init(string:)) else { throw OAuthError.invalidResponse }
        let interval = (value["interval"] as? NSNumber)?.intValue ?? 5
        let expiresIn = (value["expires_in"] as? NSNumber)?.doubleValue ?? 900
        return GitHubDeviceCode(deviceCode: deviceCode, userCode: userCode, verificationURL: uri, interval: interval, expiresAt: .now.addingTimeInterval(expiresIn))
    }

    func pollGitHubToken(_ device: GitHubDeviceCode) async throws -> OAuthCredential {
        var interval = device.interval
        while Date.now < device.expiresAt {
            try await Task.sleep(for: .seconds(interval))
            try Task.checkCancellation()
            let value = try await postForm("https://github.com/login/oauth/access_token", [
                "client_id": OAuthClient.githubID,
                "device_code": device.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ], acceptsErrorBody: true)
            if let token = value["access_token"] as? String, !token.isEmpty {
                let data = try JSONSerialization.data(withJSONObject: ["access_token": token])
                return OAuthCredential(platform: .githubCopilot, data: data, email: nil)
            }
            switch value["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw OAuthError.denied
            case "expired_token": throw OAuthError.timedOut
            default: throw OAuthError.invalidResponse
            }
        }
        throw OAuthError.timedOut
    }

    // MARK: 更新 token

    /// Codex refresh token 會輪替；只能用在 AspaceI 自己登入的帳號，否則會讓官方客戶端登出。
    func refreshCodex(_ data: Data) async throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var tokens = root["tokens"] as? [String: Any],
              let refreshToken = tokens["refresh_token"] as? String else { throw OAuthError.missingRefreshToken }
        let value = try await postJSON(OAuthClient.codexToken, [
            "client_id": OAuthClient.codexID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email"
        ])
        for key in ["id_token", "access_token", "refresh_token"] {
            if let updated = value[key] as? String { tokens[key] = updated }
        }
        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: .now)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    func refreshClaude(_ data: Data) async throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let refreshToken = oauth["refreshToken"] as? String else { throw OAuthError.missingRefreshToken }
        let value = try await postJSON(OAuthClient.claudeToken, [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthClient.claudeID
        ])
        let refreshed = try Self.claudeCredential(from: value)
        guard let refreshedRoot = try JSONSerialization.jsonObject(with: refreshed.data) as? [String: Any],
              var refreshedOAuth = refreshedRoot["claudeAiOauth"] as? [String: Any] else { throw OAuthError.invalidResponse }
        refreshedOAuth.merge(oauth) { current, _ in current }
        root["claudeAiOauth"] = refreshedOAuth
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    /// Antigravity 官方 App 讀的是可用的 access token；切換帳號前用 refresh token 換一份完整的。
    /// Google 的 refresh token 不輪替，換發不會影響其他地方的登入。
    func refreshAntigravity(_ data: Data) async throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OAuthError.invalidResponse }
        let token = root["token"] as? [String: Any] ?? root
        guard let refreshToken = token["refresh_token"] as? String ?? token["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw OAuthError.missingRefreshToken
        }
        let value = try await postForm("https://oauth2.googleapis.com/token", [
            "client_id": OAuthClient.antigravityID,
            "client_secret": OAuthClient.antigravitySecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        return try Self.antigravityRefreshed(from: value, existing: data)
    }

    /// 把 refresh 回應併回原憑證：回應不帶 refresh token，沿用原本的。
    static func antigravityRefreshed(from value: [String: Any], existing: Data, now: Date = .now) throws -> Data {
        guard let root = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else { throw OAuthError.invalidResponse }
        let previous = root["token"] as? [String: Any] ?? root
        guard let accessToken = value["access_token"] as? String, !accessToken.isEmpty else { throw OAuthError.invalidResponse }
        guard let refreshToken = value["refresh_token"] as? String
            ?? previous["refresh_token"] as? String
            ?? previous["refreshToken"] as? String else { throw OAuthError.missingRefreshToken }
        let expiresIn = (value["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
        var object: [String: Any] = [
            "auth_method": root["auth_method"] as? String ?? "consumer",
            "token": [
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "token_type": value["token_type"] as? String ?? "Bearer",
                "expiry": ISO8601DateFormatter().string(from: now.addingTimeInterval(expiresIn))
            ]
        ]
        if let idToken = value["id_token"] as? String ?? root["id_token"] as? String, !idToken.isEmpty {
            object["id_token"] = idToken
        }
        if let project = root["project_id"] as? String ?? previous["project_id"] as? String {
            object["project_id"] = project
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func claudeTokenExpired(_ data: Data, now: Date = .now) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let expiresAt = oauth["expiresAt"] as? NSNumber else { return false }
        return Date(timeIntervalSince1970: expiresAt.doubleValue / 1000) <= now.addingTimeInterval(60)
    }

    /// Codex 官方客戶端約每 8 天換新一次；提早在 7 天換，避免 access token 在兩輪之間過期。
    static func codexNeedsRefresh(_ data: Data, now: Date = .now) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["tokens"] as? [String: Any])?["refresh_token"] is String else { return false }
        guard let lastRefresh = (root["last_refresh"] as? String).flatMap(parseISODate) else { return true }
        return now.timeIntervalSince(lastRefresh) > 7 * 24 * 3600
    }

    static func isoDate(_ value: String) -> Date? { parseISODate(value) }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    // MARK: Helpers

    static func jwtClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func googleEmail(accessToken: String) async -> String? {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return object["email"] as? String
    }

    private static func makeURL(_ base: String, _ query: [String: String]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    private func postForm(_ endpoint: String, _ fields: [String: String], acceptsErrorBody: Bool = false) async throws -> [String: Any] {
        guard let url = URL(string: endpoint) else { throw OAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").utf8)
        return try await send(request, acceptsErrorBody: acceptsErrorBody)
    }

    private func postJSON(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: endpoint) else { throw OAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request, acceptsErrorBody: false)
    }

    private func send(_ request: URLRequest, acceptsErrorBody: Bool) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if (200..<300).contains(status) || acceptsErrorBody, let object { return object }
        if status == 400 || status == 401 { throw OAuthError.rejected }
        throw OAuthError.requestFailed(status)
    }
}

enum OAuthError: LocalizedError, Equatable {
    case callbackUnavailable, callbackPortInUse(UInt16), timedOut, denied, rejected, invalidResponse, missingRefreshToken, requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .callbackUnavailable: "無法建立本機登入回呼"
        case .callbackPortInUse(let port): "登入回呼埠 \(port) 被占用，請先關閉正在登入的官方客戶端"
        case .timedOut: "登入逾時"
        case .denied: "已取消授權"
        case .rejected: "授權碼無效或已過期"
        case .invalidResponse: "登入回應格式無法識別"
        case .missingRefreshToken: "此憑證沒有 refresh token"
        case .requestFailed(let status): "登入服務拒絕請求（\(status)）"
        }
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
