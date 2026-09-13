import Foundation
import Testing
@testable import AspaceI

struct AccountMigrationTests {
    @Test
    func decodesAccountSavedBeforeActiveSelectionExisted() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","platform":"codex","displayName":"Codex"}
        """
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        #expect(account.isActive == false)
    }
}
