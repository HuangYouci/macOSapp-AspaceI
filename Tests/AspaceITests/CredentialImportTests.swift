import Foundation
import Testing
@testable import AspaceI

struct CredentialImportTests {
    @Test
    func wrapsPlainTokensForEveryPlatform() throws {
        for platform in PlatformKind.allCases {
            let imported = try CredentialImportService.shared.importText(
                "example-token",
                platform: platform,
                displayName: "測試"
            )
            let data = try #require(imported.data)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
            #expect(object.values.contains("example-token"))
        }
    }

    @Test
    func keepsJSONCredentialsIntact() throws {
        let source = #"{"access_token":"example-token"}"#
        let imported = try CredentialImportService.shared.importText(
            source,
            platform: .githubCopilot,
            displayName: "測試"
        )
        #expect(imported.data == Data(source.utf8))
    }
}
