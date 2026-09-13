import AppKit
import Foundation
import Observation

@MainActor
@Observable
/// 登入流程要跨越 popup 關閉（切到瀏覽器時 popup 會收起），因此由 App 持有而不是畫面。
final class AccountLoginManager {
    enum Phase: Equatable {
        case idle
        case waitingForBrowser
        case awaitingCode
        case deviceCode(userCode: String, verificationURL: URL)
        case exchanging
        case succeeded(PlatformKind)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var platform: PlatformKind?
    var pastedCode = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var authorization: OAuthAuthorization?
    @ObservationIgnored private var callbackServer: OAuthCallbackServer?
    private let service = OAuthService.shared
    @ObservationIgnored private let onCredential: @MainActor (OAuthCredential) async -> Void

    init(onCredential: @escaping @MainActor (OAuthCredential) async -> Void) {
        self.onCredential = onCredential
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .failed, .succeeded: false
        default: true
        }
    }

    func start(platform: PlatformKind) {
        cancel()
        pastedCode = ""
        self.platform = platform
        if platform == .githubCopilot {
            startDeviceFlow()
            return
        }
        guard let authorization = OAuthService.authorization(for: platform) else {
            phase = .failed(OAuthError.invalidResponse.localizedDescription)
            return
        }
        self.authorization = authorization
        guard let port = authorization.callbackPort, let path = authorization.callbackPath else {
            phase = .awaitingCode
            NSWorkspace.shared.open(authorization.url)
            return
        }
        phase = .waitingForBrowser
        let server = OAuthCallbackServer()
        callbackServer = server
        task = Task { [weak self, service] in
            do {
                async let callback = server.waitForCallback(port: port, path: path)
                NSWorkspace.shared.open(authorization.url)
                let query = try await callback
                if query["error"] != nil { throw OAuthError.denied }
                guard query["state"] == authorization.state, let code = query["code"], !code.isEmpty else { throw OAuthError.rejected }
                self?.phase = .exchanging
                let credential = try await service.exchange(authorization, code: code)
                try Task.checkCancellation()
                await self?.onCredential(credential)
                self?.phase = .succeeded(credential.platform)
            } catch is CancellationError {
                return
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func submitCode() {
        guard let authorization else { return }
        let parsed = OAuthService.parseClaudeCode(pastedCode)
        guard !parsed.code.isEmpty else { return }
        if let state = parsed.state, state != authorization.state {
            phase = .failed(OAuthError.rejected.localizedDescription)
            return
        }
        phase = .exchanging
        task = Task { [weak self, service] in
            do {
                let credential = try await service.exchange(authorization, code: parsed.code)
                try Task.checkCancellation()
                await self?.onCredential(credential)
                self?.phase = .succeeded(credential.platform)
            } catch is CancellationError {
                return
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func openVerificationPage() {
        guard case .deviceCode(let userCode, let url) = phase else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        NSWorkspace.shared.open(url)
    }

    func cancel() {
        task?.cancel()
        task = nil
        callbackServer = nil
        authorization = nil
        platform = nil
        phase = .idle
    }

    private func startDeviceFlow() {
        phase = .exchanging
        task = Task { [weak self, service] in
            do {
                let device = try await service.requestGitHubDeviceCode()
                self?.phase = .deviceCode(userCode: device.userCode, verificationURL: device.verificationURL)
                self?.openVerificationPage()
                let credential = try await service.pollGitHubToken(device)
                self?.phase = .exchanging
                await self?.onCredential(credential)
                self?.phase = .succeeded(credential.platform)
            } catch is CancellationError {
                return
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }
}
