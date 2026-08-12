import AppKit

@MainActor
final class AppLifecycleController: NSObject, NSApplicationDelegate {
    var didBecomeActive: (() -> Void)?

    func applicationDidBecomeActive(_ notification: Notification) {
        didBecomeActive?()
    }
}
