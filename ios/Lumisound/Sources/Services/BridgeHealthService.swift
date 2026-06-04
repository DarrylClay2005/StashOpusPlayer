import Foundation
import SwiftUI

// MARK: - BridgeHealthService

@MainActor
final class BridgeHealthService: ObservableObject {
    @Published private(set) var isHealthy: Bool? = nil   // nil = unchecked
    @Published private(set) var isAPIKeyValid: Bool? = nil
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastIsSuccess = false

    private var checkTimer: Timer?

    func startPeriodicChecks(streaming: StreamingService) {
        stopPeriodicChecks()
        appLog("startPeriodicChecks: bridge=\(streaming.bridgeURL)", category: "network")
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.check(streaming: streaming)
            }
        }
        Task { await check(streaming: streaming) }  // immediate first check
    }

    func stopPeriodicChecks() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    func check(streaming: StreamingService) async {
        let prevHealthy = isHealthy
        let healthy = await streaming.checkHealth()
        isHealthy = healthy

        if healthy && !streaming.apiKey.isEmpty {
            do {
                isAPIKeyValid = try await checkAPIKey(streaming: streaming)
                if isAPIKeyValid == false {
                    appWarn("checkAPIKey: key rejected by server", category: "network")
                }
            } catch {
                appWarn("checkAPIKey: error \(error.localizedDescription)", category: "network")
                isAPIKeyValid = false
            }
        } else if healthy {
            isAPIKeyValid = nil  // No key configured — open access
        }

        // Log status changes (not every routine check)
        if prevHealthy != healthy {
            if healthy {
                appLog("Bridge server connected (\(streaming.bridgeURL))", category: "network")
            } else {
                appWarn("Bridge server offline (\(streaming.bridgeURL))", category: "network")
            }
        }

        // Show toast on status change
        if prevHealthy != nil && prevHealthy != healthy {
            toastMessage = healthy ? "✓ Bridge server connected" : "⚠ Bridge server offline"
            toastIsSuccess = healthy
            showToast = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showToast = false
        }
    }

    private func checkAPIKey(streaming: StreamingService) async throws -> Bool {
        // Simple check: hit /health with the API key header already applied by makePublicRequest
        guard let req = streaming.makePublicRequest("/health") else { return false }
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}

// MARK: - ToastView

struct ToastView: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? AppTheme.success : AppTheme.warning)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
