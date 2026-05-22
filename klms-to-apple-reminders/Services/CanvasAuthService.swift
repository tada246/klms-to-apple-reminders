import Foundation

/// Canvas API の Cookie ベース認証を担当するサービス。
/// - WKWebView でのログイン後に受け取った Cookie を使ってアクセストークンを生成する
/// - トークン期限切れ (401) 時に、保存済み Cookie で自動リフレッシュを試みる
enum CanvasAuthService {
    private static let baseURL = "https://lms.keio.jp/api/v1"

    // MARK: - Public

    /// Cookie ヘッダー文字列から Canvas 個人アクセストークンを生成して返す。
    /// Canvas の JSON API は Content-Type: application/json があれば CSRF トークン不要。
    static func generateToken(cookieHeader: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/users/self/tokens")!)
        request.httpMethod = "POST"
        request.setValue(cookieHeader,       forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = ["token": ["purpose": "klms-to-apple-reminders"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CanvasAuthError.networkError
        }

        #if DEBUG
        print("[CanvasAuth] generateToken status: \(http.statusCode)")
        if let str = String(data: data, encoding: .utf8) {
            print("[CanvasAuth] response: \(str.prefix(400))")
        }
        #endif

        switch http.statusCode {
        case 200, 201:
            break
        case 401:
            throw CanvasAuthError.sessionExpired
        default:
            throw CanvasAuthError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CanvasAuthError.invalidResponse
        }
        // Canvas は "token" または "visible_token" でトークン文字列を返す
        for key in ["token", "visible_token"] {
            if let token = json[key] as? String, !token.isEmpty {
                return token
            }
        }
        throw CanvasAuthError.invalidResponse
    }

    /// 保存済み Cookie を使って API トークンを静かに再生成する。
    /// 成功した場合 Keychain のトークンを更新して true を返す。
    static func silentRefresh() async -> Bool {
        guard let cookieHeader = KeychainHelper.loadCookie(), !cookieHeader.isEmpty else {
            return false
        }
        do {
            let token = try await generateToken(cookieHeader: cookieHeader)
            try KeychainHelper.save(token)
            return true
        } catch {
            #if DEBUG
            print("[CanvasAuth] silentRefresh failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// WKHTTPCookieStore から取り出したクッキー配列を Cookie ヘッダー文字列に変換する。
    static func buildCookieHeader(from cookies: [HTTPCookie]) -> String {
        cookies
            .filter { $0.domain.contains("lms.keio.jp") || $0.domain.hasSuffix(".keio.jp") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    // MARK: - Private

    /// Cookie ヘッダー文字列から _csrf_token を取り出し URL デコードして返す。
    private static func extractCSRFToken(from cookieHeader: String) -> String? {
        for part in cookieHeader.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("_csrf_token=") {
                let raw = String(trimmed.dropFirst("_csrf_token=".count))
                return raw.removingPercentEncoding ?? raw
            }
        }
        return nil
    }
}

// MARK: - Error

enum CanvasAuthError: Error, LocalizedError {
    case sessionExpired
    case networkError
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .sessionExpired:    return "セッションが切れています。再ログインしてください。"
        case .networkError:      return "ネットワークエラーが発生しました。"
        case .httpError(let c):  return "HTTPエラー (\(c)): しばらく待ってから再試行してください。"
        case .invalidResponse:   return "サーバーの応答を解析できませんでした。"
        }
    }
}
