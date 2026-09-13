import Foundation

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let windows: [QuotaWindow]
    let fetchedAt: Date
}

struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let remainingPercentage: Int
    let resetsAt: Date?

    init(id: String, title: String, remainingPercentage: Int, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.remainingPercentage = min(max(remainingPercentage, 0), 100)
        self.resetsAt = resetsAt
    }
}
