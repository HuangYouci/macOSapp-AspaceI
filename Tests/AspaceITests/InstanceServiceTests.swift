import Foundation
import Testing
@testable import AspaceI

struct InstanceServiceTests {
    @Test
    func refusesToTrashProfileOutsideManagedRoot() {
        let instance = Instance(
            name: "Unsafe",
            platform: .codex,
            profileDirectory: "/tmp/not-managed-by-aspacei",
            executablePath: "/usr/bin/true"
        )

        #expect(throws: InstanceError.self) {
            try InstanceService.shared.trashProfile(for: instance)
        }
    }
}
