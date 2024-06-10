import XCTest
import DatadogInternal

public class ApplicationLifeCycle {
    #if os(tvOS) || os(iOS)
    let willEnterForegroundNotification = UIApplication.willEnterForegroundNotification
    let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
    let willResignActiveNotification = UIApplication.willResignActiveNotification
    let didEnterBackgroundNotification = UIApplication.didEnterBackgroundNotification
    let willTerminateNotification = UIApplication.willTerminateNotification
    let didFinishLaunchingNotification = UIApplication.didFinishLaunchingNotification
    #elseif os(macOS)
    let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    let willResignActiveNotification = NSApplication.willResignActiveNotification
    let willTerminateNotification = NSApplication.willTerminateNotification
    let didFinishLaunchingNotification = NSApplication.didFinishLaunchingNotification
    #endif

    let notificationCenter: NotificationCenter

    public init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    public func goToForeground() {
        willEnterForeground()
        uiWindowDidBecomeVisible()
        didBecomeActive()
    }

    public func goToBackground() {
        willResignActive()
        didEnterBackground()
    }

    public func terminateApp() {
        willTerminate()
    }

    public func willEnterForeground() {
        #if os(tvOS) || os(iOS)
        post(name: willEnterForegroundNotification)
        #endif
    }

    public func didBecomeActive() {
        #if os(tvOS) || os(iOS) || os(macOS)
        post(name: didBecomeActiveNotification)
        #endif
    }

    public func willResignActive() {
        #if os(tvOS) || os(iOS) || os(macOS)
        post(name: willResignActiveNotification)
        #endif
    }

    public func didEnterBackground() {
        #if os(tvOS) || os(iOS)
        post(name: didEnterBackgroundNotification)
        #endif
    }

    public func willTerminate() {
        #if os(tvOS) || os(iOS) || os(macOS)
        post(name: willTerminateNotification)
        #endif
    }

    public func didFinishLaunching() {
        #if os(tvOS) || os(iOS) || os(macOS)
        post(name: didFinishLaunchingNotification)
        #endif
    }

    public func uiWindowDidBecomeVisible() {
        #if os(tvOS) || os(iOS) || targetEnvironment(macCatalyst)
        post(name: UIWindow.didBecomeVisibleNotification)
        #endif
    }

    private func post(name: Notification.Name) {
        notificationCenter.post(Notification(name: name))
    }
}
