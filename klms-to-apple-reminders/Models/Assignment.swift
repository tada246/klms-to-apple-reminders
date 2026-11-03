import Foundation

struct Assignment: Identifiable, Codable, Equatable {
    /// ICS フィードの安定した一意 ID（例: "event-assignment-12345@lms.keio.jp"）。
    /// リマインダーの重複判定はこの uid で行う（.ics には提出済みフラグが無いため）。
    let uid: String
    let id: String
    let title: String
    let courseName: String
    let dueAt: Date?
    /// 締切が「日付のみ」（Canvas の終日課題, DTSTART;VALUE=DATE）かどうか。
    /// true のときリマインダーは時刻なし（0:00 を表示しない）で登録する。
    let isAllDay: Bool
    let url: URL?
}
