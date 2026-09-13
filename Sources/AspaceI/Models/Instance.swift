import Foundation

struct Instance: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var platform: PlatformKind
    var accountID: UUID?
    var profileDirectory: String
    var executablePath: String
    var arguments: [String]

    init(id: UUID = UUID(), name: String, platform: PlatformKind, accountID: UUID? = nil, profileDirectory: String, executablePath: String, arguments: [String] = []) {
        self.id = id
        self.name = name
        self.platform = platform
        self.accountID = accountID
        self.profileDirectory = profileDirectory
        self.executablePath = executablePath
        self.arguments = arguments
    }
}
