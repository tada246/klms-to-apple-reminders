import Foundation

enum KLMSError: Error, LocalizedError {
    case invalidToken
    case networkError(Error)
    case decodingError(Error)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "トークンが無効または期限切れです。設定画面から再発行してください。"
        case .networkError:
            return "ネットワークに接続できません。インターネット接続を確認してください。"
        case .decodingError:
            return "K-LMSのデータ形式を読み込めませんでした。時間をおいて再試行してください。"
        case .httpError(let code):
            switch code {
            case 401: return "認証エラー(401): トークンが無効または期限切れです。再発行してください。"
            case 403: return "アクセス拒否(403): このリソースへのアクセス権限がありません。"
            case 404: return "見つかりません(404): K-LMSのAPIエンドポイントが存在しません。"
            case 429: return "リクエスト過多(429): しばらく待ってから再試行してください。"
            case 500...599: return "K-LMSサーバーエラー(\(code)): しばらく待ってから再試行してください。"
            default:  return "通信エラー(\(code)): しばらく待ってから再試行してください。"
            }
        }
    }
}

struct KLMSClient {
    private static let baseURL = "https://lms.keio.jp/api/v1"
    private let token: String

    init(token: String) {
        self.token = token
    }

    func fetchAssignments(daysAhead: Int) async throws -> [Assignment] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var urlComponents = URLComponents(string: "\(Self.baseURL)/planner/items")!
        urlComponents.queryItems = [
            .init(name: "start_date", value: formatter.string(from: now)),
            .init(name: "end_date",   value: formatter.string(from: end)),
            .init(name: "per_page",   value: "100"),
        ]

        var allItems: [PlannerItem] = []
        var nextURL: URL? = urlComponents.url

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw KLMSError.networkError(error)
            }

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 { throw KLMSError.invalidToken }
                if http.statusCode != 200 { throw KLMSError.httpError(http.statusCode) }
                nextURL = parseNextURL(from: http.value(forHTTPHeaderField: "Link"))
            } else {
                nextURL = nil
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let items = try decoder.decode([PlannerItem].self, from: data)
                allItems.append(contentsOf: items)
            } catch {
                throw KLMSError.decodingError(error)
            }
        }

        return allItems.compactMap(\.toAssignment)
    }

    private func parseNextURL(from linkHeader: String?) -> URL? {
        guard let header = linkHeader else { return nil }
        for part in header.split(separator: ",") {
            let segments = part.split(separator: ";")
            guard segments.count == 2,
                  segments[1].contains("rel=\"next\""),
                  let rawURL = segments[0].trimmingCharacters(in: .whitespaces)
                      .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                      .nilIfEmpty
            else { continue }
            return URL(string: rawURL)
        }
        return nil
    }
}

// MARK: - Canvas JSON types

private struct PlannerItem: Decodable {
    let plannableType: String
    let plannableId: Int
    let contextName: String?
    let htmlUrl: String?
    let plannable: Plannable
    let submissions: Submissions?
    let plannableDate: String?

    var toAssignment: Assignment? {
        guard plannableType == "assignment" || plannableType == "quiz" else { return nil }
        let dueString = plannable.dueAt ?? plannableDate
        let dueAt = dueString.flatMap { ISO8601DateFormatter().date(from: $0) }

        var fullURL: URL?
        if let raw = htmlUrl {
            let urlString = raw.hasPrefix("/") ? "https://lms.keio.jp\(raw)" : raw
            fullURL = URL(string: urlString)
        }

        return Assignment(
            id: "\(plannableType)_\(plannableId)",
            title: plannable.title ?? "（タイトル不明）",
            courseName: contextName ?? "",
            dueAt: dueAt,
            url: fullURL,
            submitted: submissions?.submitted ?? false
        )
    }
}

private struct Plannable: Decodable {
    let title: String?
    let dueAt: String?
}

private struct Submissions: Decodable {
    let submitted: Bool?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
    func trimmingCharacters(in set: CharacterSet) -> String {
        (self as NSString).trimmingCharacters(in: set)
    }
}
