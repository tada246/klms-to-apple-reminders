import Foundation

// Canvas カレンダーフィード（.ics）の典型的な VEVENT サンプル（Instructure Canvas 標準フォーマットに基づく代表例）。
// 実際のフィード全体は VCALENDAR/VEVENT が複数個並ぶが、パーサが前提とする1件の構造は以下の通り。
//
//   BEGIN:VEVENT
//   DTSTAMP:20260710T030201Z
//   DTSTART:20260715T145900Z
//   DTEND:20260715T145900Z
//   UID:event-assignment-123456@lms.keio.jp
//   SUMMARY:レポート課題1 [情報基礎論]
//   DESCRIPTION:第1回レポート課題です。\n提出期限厳守。
//   URL:https://lms.keio.jp/courses/1000/assignments/123456
//   END:VEVENT
//
// 終日課題（VALUE=DATE）や TZID 付きローカル時刻での DTSTART も存在しうる：
//   DTSTART;VALUE=DATE:20260715
//   DTSTART;TZID=Asia/Tokyo:20260715T235900
//
// フォーマットが将来変わった場合は、このコメントのサンプルと実際のフィード出力を diff して
// パーサ（parseVEvents / parseDate 等）を調整すること。

enum ICSFeedError: Error, LocalizedError {
    case notConfigured
    case networkError(Error)
    case httpError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "カレンダーフィード URL が設定されていません。設定画面から貼り付けてください。"
        case .networkError:
            return "ネットワークに接続できません。インターネット接続を確認してください。"
        case .httpError(let code):
            return "フィードの取得に失敗しました (HTTP \(code))。URL を確認してください。"
        case .parseError:
            return "カレンダーフィードの形式を読み込めませんでした。"
        }
    }
}

/// Canvas のカレンダーフィード（.ics）を取得し、課題を Assignment に変換するクライアント。
/// Bearer トークン不要。URL に内包された秘密トークンで認証される。
struct ICSFeedClient {
    private let feedURL: URL

    init(feedURL: URL) {
        self.feedURL = feedURL
    }

    /// フィードを取得し、`daysAhead` 日以内が締切の課題を返す。
    func fetchAssignments(daysAhead: Int) async throws -> [Assignment] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: feedURL)
        } catch {
            throw ICSFeedError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ICSFeedError.parseError
        }
        guard httpResponse.statusCode == 200 else {
            throw ICSFeedError.httpError(httpResponse.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw ICSFeedError.parseError
        }

        let events = ICSParser.parseVEvents(from: text)

        let now = Date()
        let calendar = Calendar.current
        guard let lowerBound = calendar.date(byAdding: .day, value: -1, to: now),
              let upperBound = calendar.date(byAdding: .day, value: daysAhead, to: now) else {
            throw ICSFeedError.parseError
        }

        var assignments: [Assignment] = []
        for event in events {
            // 課題（クイズ含む）は UID が "event-assignment-" で始まる。
            // それ以外（カレンダーイベント等）は同期対象外なので無視する。
            guard event.uid.hasPrefix("event-assignment-") else { continue }

            guard let dueAt = event.dtStart else { continue }

            // 過去1日〜未来 daysAhead 日の範囲でフィルタ。
            // 過去1日を含めるのは、締切直後で未提出の課題を取りこぼさないため。
            guard dueAt >= lowerBound && dueAt <= upperBound else { continue }

            let (title, courseName) = ICSParser.splitTitleAndCourse(from: event.summary ?? "")

            let url = ICSParser.assignmentPageURL(rawURL: event.url, uid: event.uid)

            assignments.append(
                Assignment(
                    uid: event.uid,
                    id: event.uid,
                    title: title,
                    courseName: courseName,
                    dueAt: dueAt,
                    isAllDay: event.isAllDay,
                    url: url
                )
            )
        }

        return assignments
    }
}

/// 最小限の ICS (RFC5545) パーサ。Canvas が出力するカレンダーフィードのパースに必要な範囲のみ対応する。
private enum ICSParser {
    struct VEventRaw {
        let uid: String
        let summary: String?
        let dtStart: Date?
        /// DTSTART が VALUE=DATE（終日）だったか。時刻を持たない締切を表す。
        let isAllDay: Bool
        let url: String?
    }

    /// .ics 全文から VEVENT ブロックを抽出し、必要なプロパティのみ取り出す。
    static func parseVEvents(from text: String) -> [VEventRaw] {
        let unfolded = unfold(text)
        let lines = unfolded.components(separatedBy: "\n")

        var events: [VEventRaw] = []
        var currentLines: [String]? = nil

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let upper = line.uppercased()

            if upper == "BEGIN:VEVENT" {
                currentLines = []
                continue
            }
            if upper == "END:VEVENT" {
                if let collected = currentLines {
                    if let event = parseVEvent(lines: collected) {
                        events.append(event)
                    }
                }
                currentLines = nil
                continue
            }
            if currentLines != nil {
                currentLines?.append(line)
            }
        }

        return events
    }

    /// RFC5545 の行アンフォールディング。
    /// 改行（CRLF または LF）の直後がスペースまたはタブの行は、前の行の続きとみなして結合する。
    static func unfold(_ text: String) -> String {
        // まず CRLF を LF に統一してから処理する。
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var result = ""
        result.reserveCapacity(normalized.count)

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let char = normalized[index]
            if char == "\n" {
                let nextIndex = normalized.index(after: index)
                if nextIndex < normalized.endIndex {
                    let nextChar = normalized[nextIndex]
                    if nextChar == " " || nextChar == "\t" {
                        // 折り返し継続行: 改行と直後の空白/タブ1文字を除去して結合。
                        index = normalized.index(after: nextIndex)
                        continue
                    }
                }
            }
            result.append(char)
            index = normalized.index(after: index)
        }

        return result
    }

    /// 1つの VEVENT ブロック（行の配列）から UID / SUMMARY / DTSTART / URL を取り出す。
    static func parseVEvent(lines: [String]) -> VEventRaw? {
        var uid: String? = nil
        var summary: String? = nil
        var dtStart: Date? = nil
        var isAllDay = false
        var url: String? = nil

        for line in lines {
            guard let (name, params, value) = splitProperty(line) else { continue }
            let upperName = name.uppercased()

            switch upperName {
            case "UID":
                uid = unescape(value)
            case "SUMMARY":
                summary = unescape(value)
            case "DTSTART":
                dtStart = parseDate(value: value, params: params)
                isAllDay = params["VALUE"]?.uppercased() == "DATE"
            case "URL":
                url = unescape(value)
            default:
                break
            }
        }

        guard let finalUID = uid else { return nil }

        return VEventRaw(uid: finalUID, summary: summary, dtStart: dtStart, isAllDay: isAllDay, url: url)
    }

    /// "NAME;PARAM1=X;PARAM2=Y:VALUE" 形式の行を (name, params, value) に分解する。
    /// コロンは値の中にも出現しうる（URL 等）ため、最初のコロンで分割する。
    static func splitProperty(_ line: String) -> (name: String, params: [String: String], value: String)? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }

        let nameAndParams = line[line.startIndex..<colonIndex]
        let value = String(line[line.index(after: colonIndex)...])

        let parts = nameAndParams.components(separatedBy: ";")
        guard let name = parts.first, !name.isEmpty else { return nil }

        var params: [String: String] = [:]
        for paramPart in parts.dropFirst() {
            let kv = paramPart.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0]).uppercased()] = String(kv[1])
            }
        }

        return (name, params, value)
    }

    /// ICS エスケープシーケンスを解除する。
    static func unescape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var index = value.startIndex
        while index < value.endIndex {
            let char = value[index]
            if char == "\\" {
                let nextIndex = value.index(after: index)
                if nextIndex < value.endIndex {
                    let nextChar = value[nextIndex]
                    switch nextChar {
                    case "n", "N":
                        result.append("\n")
                    case ",":
                        result.append(",")
                    case ";":
                        result.append(";")
                    case "\\":
                        result.append("\\")
                    default:
                        result.append(nextChar)
                    }
                    index = value.index(after: nextIndex)
                    continue
                }
            }
            result.append(char)
            index = value.index(after: index)
        }
        return result
    }

    /// DTSTART の3形式（UTC / 終日 VALUE=DATE / TZID 付きローカル時刻）に対応した日時パース。
    static func parseDate(value: String, params: [String: String]) -> Date? {
        // a) 終日: DTSTART;VALUE=DATE:20260715 → その日の 00:00 として扱う。
        if params["VALUE"]?.uppercased() == "DATE" {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone.current
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone.current
            formatter.calendar = calendar
            return formatter.date(from: value)
        }

        // b) 末尾 Z の UTC: DTSTART:20260715T145900Z
        if value.hasSuffix("Z") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: value)
        }

        // c) TZID 付きローカル時刻: DTSTART;TZID=Asia/Tokyo:20260715T235900
        // TimeZone(identifier:) で解釈できなければ端末ローカルタイムゾーンにフォールバックする。
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = TimeZone.current
        }
        return formatter.date(from: value)
    }

    /// Canvas の SUMMARY は「課題名 [[時限]教員名　コース名 [キャンパス 教室]]」形式。
    /// コース情報は末尾の「最上位の [...] グループ」に入る（内側にさらに [] が入れ子になる）。
    /// タイトル自体が [] を含む場合（例:「任意課題[慶應義塾史展示館]」）があるため、
    /// 単純な lastIndex(of:"[") ではなく括弧の対応を取って最後の最上位グループを特定する。
    static func splitTitleAndCourse(from summary: String) -> (title: String, courseName: String) {
        let chars = Array(summary)
        var depth = 0
        var groupStart: Int? = nil        // 現在の最上位グループの開き位置
        var lastGroupRange: (Int, Int)? = nil
        for (i, c) in chars.enumerated() {
            if c == "[" {
                if depth == 0 { groupStart = i }
                depth += 1
            } else if c == "]", depth > 0 {
                depth -= 1
                if depth == 0, let s = groupStart {
                    lastGroupRange = (s, i)
                    groupStart = nil
                }
            }
        }

        guard let (start, end) = lastGroupRange else {
            return (summary.trimmingCharacters(in: .whitespaces), "")
        }

        let title = String(chars[0..<start]).trimmingCharacters(in: .whitespaces)
        let inner = String(chars[(start + 1)..<end])   // 最上位グループの中身
        let course = cleanCourse(inner)
        return (title.isEmpty ? summary.trimmingCharacters(in: .whitespaces) : title, course)
    }

    /// 「[時限]教員名　コース名 [キャンパス 教室]」からコース名だけを取り出す。
    /// 先頭の [時限] と、全角スペース区切りの教員名、末尾の " [キャンパス]" を取り除く。
    /// コース名に直接付く "[DS1]" 等（スペースなしの角括弧）は残す。
    static func cleanCourse(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)

        // 先頭の [時限] を除去（時限には入れ子が無いので最初の "]" まで）。
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            s = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }

        // 末尾の " [キャンパス 教室]"（スペース+角括弧）を除去。
        // "統計基礎[DS1]" のようにスペースを挟まない角括弧はコース名の一部として残す。
        if s.hasSuffix("]"), let r = s.range(of: " [", options: .backwards) {
            s = String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // 全角スペースで「教員名　コース名」を分割し、コース名側を採用。
        if let r = s.range(of: "　") {
            s = String(s[r.upperBound...])
        }

        return s.trimmingCharacters(in: .whitespaces)
    }

    /// リマインダーのリンク先として、可能なら課題ページの正規 URL を組み立てる。
    /// 生の URL は "…/calendar?include_contexts=course_136629&…#assignment_1269269" という
    /// カレンダー URL なので、course_ と assignment_ の ID を抜いて直リンクにする。
    /// 抜けない場合は生 URL、それも無ければ UID から assignment ID だけで組む。
    static func assignmentPageURL(rawURL: String?, uid: String) -> URL? {
        if let raw = rawURL,
           let courseID = firstMatch(in: raw, pattern: "course_(\\d+)"),
           let assignmentID = firstMatch(in: raw, pattern: "assignment_(\\d+)") {
            return URL(string: "https://lms.keio.jp/courses/\(courseID)/assignments/\(assignmentID)")
        }
        if let raw = rawURL, let url = URL(string: raw) {
            return url
        }
        if let assignmentID = firstMatch(in: uid, pattern: "assignment[-_](\\d+)") {
            return URL(string: "https://lms.keio.jp/assignments/\(assignmentID)")
        }
        return nil
    }

    /// 正規表現の最初のキャプチャグループを返す。
    static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
