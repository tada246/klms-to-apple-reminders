import Foundation

struct Assignment: Identifiable, Codable {
    let id: String
    let title: String
    let courseName: String
    let dueAt: Date?
    let url: URL?
    let submitted: Bool
}
