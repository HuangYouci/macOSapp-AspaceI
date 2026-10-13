import SwiftUI

/// 把 `TaskModeManager` 的狀態接到純展示的側欄上，放進側欄面板。
struct TaskSidebarHost: View {
    let manager: TaskModeManager

    var body: some View {
        TaskSidebarView(
            items: manager.sidebarItems,
            selectedID: manager.selectedID,
            thumbnail: { manager.thumbnails[$0]?.image },
            onSelect: { manager.select($0) },
            onExit: { Task { await manager.deactivate() } }
        )
    }
}
