#if canImport(UIKit) && canImport(SwiftUI) && os(iOS)
import UIKit
import SwiftUI
import AgentLogsSDK

extension AgentLogs {
    /// Present the AgentLogs viewer in its own window above everything.
    ///
    /// ```swift
    /// AgentLogs.showUI()
    /// ```
    @MainActor
    public static func showUI() {
        // Prevent double-show
        guard AgentLogsWindow.shared == nil else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let window = AgentLogsWindow(windowScene: scene)
        window.show()
    }

    /// Dismiss the AgentLogs viewer if it's currently shown.
    @MainActor
    public static func hideUI() {
        AgentLogsWindow.shared?.dismiss()
    }
}

/// A dedicated UIWindow that hosts AgentLogsView above the entire app.
@MainActor
private final class AgentLogsWindow: UIWindow {
    static var shared: AgentLogsWindow?

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .statusBar + 1

        let logsView = AgentLogsView(onDismiss: { [weak self] in
            self?.dismiss()
        })

        let hostVC = UIHostingController(rootView: logsView)
        hostVC.view.backgroundColor = .systemBackground
        rootViewController = hostVC

        AgentLogsWindow.shared = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        isHidden = false
        makeKeyAndVisible()
    }

    func dismiss() {
        isHidden = true
        rootViewController = nil
        AgentLogsWindow.shared = nil
    }
}
#endif
