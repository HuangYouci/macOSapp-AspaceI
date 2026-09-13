import SwiftUI
import UniformTypeIdentifiers

struct AccountEditorView: View {
    @Environment(AccountManager.self) private var accountManager
    let onDone: () -> Void
    @State private var platform = PlatformKind.codex
    @Environment(AccountLoginManager.self) private var login
    @State private var pastedText = ""
    @State private var showsImporter = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("加入帳號")
                    .font(.scaled(.headline))
                Spacer()
                Button("關閉", systemImage: "xmark") {
                    login.cancel()
                    onDone()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }

            platformPicker

            methodCard(symbol: "safari", title: "瀏覽器登入") {
                Button {
                    login.start(platform: platform)
                } label: {
                    Text("以瀏覽器登入 \(platform.displayName)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(login.isBusy)
                loginStatus
            }

            methodCard(symbol: "desktopcomputer", title: "讀取這台 Mac") {
                localSource
            }

            methodCard(symbol: "doc.on.clipboard", title: "貼上或拖入") {
                pasteArea
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json, .data, .yaml, .plainText], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            load(url)
        }
        .onAppear {
            if let active = login.platform { platform = active }
        }
    }

    // MARK: 平台

    private var platformPicker: some View {
        HStack(spacing: 8) {
            ForEach(PlatformKind.allCases) { kind in
                Button {
                    login.cancel()
                    platform = kind
                } label: {
                    VStack(spacing: 6) {
                        PlatformBadge(platform: kind, size: 30)
                        Text(kind.displayName)
                            .font(.scaled(.caption, weight: platform == kind ? .semibold : .regular))
                            .foregroundStyle(platform == kind ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .cardStyle()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .opacity(platform == kind ? 1 : 0)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(login.isBusy)
            }
        }
    }

    // MARK: 方式一

    @ViewBuilder
    private var loginStatus: some View {
        switch login.phase {
        case .idle, .succeeded:
            EmptyView()
        case .waitingForBrowser:
            statusRow("等待瀏覽器授權")
        case .exchanging:
            statusRow("登入中")
        case .awaitingCode:
            HStack(spacing: 6) {
                TextField("貼上授權碼", text: Bindable(login).pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitCode)
                Button("完成", action: submitCode)
                    .disabled(login.pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        case .deviceCode(let userCode, _):
            HStack {
                Text(userCode)
                    .font(.scaled(.title3, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("複製並開啟 GitHub") { login.openVerificationPage() }
                Button("取消") { login.cancel() }
            }
        case .failed(let message):
            Text(message)
                .font(.scaled(.caption))
                .foregroundStyle(.red)
        }
    }

    private func statusRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Button("取消") { login.cancel() }
        }
    }

    // MARK: 方式二

    private var localSource: some View {
        let paths = CredentialImportService.localFilePaths(for: platform)
        let found = paths.first { FileManager.default.fileExists(atPath: $0.path) }
        return HStack(spacing: 10) {
            Image(systemName: found == nil ? "doc.questionmark" : "doc.text")
                .font(.scaled(.title3))
                .foregroundStyle(found == nil ? .tertiary : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(abbreviated(found ?? paths[0]))
                    .font(.scaled(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(found == nil ? "找不到" : "已找到")
                    .font(.scaled(.caption2))
                    .foregroundStyle(found == nil ? .tertiary : .secondary)
            }
            Spacer()
            Button("讀取") {
                Task {
                    await accountManager.importLocalAccounts(platforms: [platform])
                    onDone()
                }
            }
            .disabled(found == nil && !platform.hasKeychainLocalSource)
        }
    }

    // MARK: 方式三

    private var pasteArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .font(.scaled(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if pastedText.isEmpty {
                    Text(platform.pastePlaceholder)
                        .font(.scaled(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 88)
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.black.opacity(0.08), style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: isDropTargeted ? [] : [4, 3]))
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                load(url)
                return true
            } isTargeted: { isDropTargeted = $0 }

            HStack(spacing: 8) {
                detectionLabel
                Spacer()
                Button("選擇檔案…") { showsImporter = true }
                Button("加入") { submitPaste() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var detectionLabel: some View {
        switch CredentialDetector.detect(pastedText) {
        case .credential(let detected):
            HStack(spacing: 5) {
                PlatformBadge(platform: detected, size: 16)
                Text("\(detected.displayName) 憑證")
                    .font(.scaled(.caption))
                    .foregroundStyle(.secondary)
            }
        case .accountFile(let count):
            Label("帳號備份 \(count) 個", systemImage: "tray.full")
                .font(.scaled(.caption))
                .foregroundStyle(.secondary)
        case .unknown:
            if !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("以 \(platform.displayName) 加入")
                    .font(.scaled(.caption))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 共用

    private func methodCard<Content: View>(symbol: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.scaled(.subheadline, weight: .semibold))
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func load(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "vscdb" {
            Task {
                await accountManager.importFile(at: url, platform: .antigravity)
                onDone()
            }
            return
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 1_000_000, let text = String(data: data, encoding: .utf8) else { throw CredentialImportError.emptyFile }
            pastedText = text
            if case .credential(let detected) = CredentialDetector.detect(text) { platform = detected }
        } catch {
            accountManager.errorMessage = error.localizedDescription
        }
    }

    private func submitPaste() {
        let text = pastedText
        Task {
            switch CredentialDetector.detect(text) {
            case .accountFile:
                await accountManager.importAccounts(data: Data(text.utf8), sourceName: "貼上")
            case .credential(let detected):
                await accountManager.addCredential(platform: detected, displayName: "", value: text)
            case .unknown:
                await accountManager.addCredential(platform: platform, displayName: "", value: text)
            }
            onDone()
        }
    }

    private func submitCode() {
        login.submitCode()
    }
}
