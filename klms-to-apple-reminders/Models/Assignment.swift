import Foundation

struct Assignment: Identifiable, Codable {
    /// ICS フィードの安定した一意 ID（例: "event-assignment-12345@lms.keio.jp"）。
    /// リマインダーの重複判定はこの uid で行う（.ics には提出済みフラグが無いため）。
    let uid: String
    let id: String
    let title: String
    let courseName: String
    let dueAt: Date?
    let url: URL?
}
