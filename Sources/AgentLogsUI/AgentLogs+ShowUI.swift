#if canImport(UIKit) && canImport(SwiftUI) && os(iOS)
import UIKit
import SwiftUI
import AgentLogsSDK

extension AgentLogs {
    /// Present the AgentLogs viewer from anywhere in the app.
    ///
    /// Finds the active window and presents a full-screen log viewer.
    /// Call from a shake handler, debug menu button, or anywhere else:
    /// ```swift
    /// AgentLogs.showUI()
    /// ```
    @MainActor
    public static func showUI() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        // Walk to the topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let host = UIHostingController(rootView: AgentLogsView())
        host.modalPresentationStyle = .fullScreen
        topVC.present(host, animated: true)
    }
}
#endif
