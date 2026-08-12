/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import DatadogInternal

/// Installs AppKit action tracking.
///
/// Contrarily to its UIKit counterpart, the AppKit version of application instrumentation does not use swizzling. Instead,
/// two facilities are used to track actions:
///
/// * `NSEvent` local monitor tracks `.leftMouseDown` dispatched through the main event tracking loop. This excludes
///   nested event tracking loops, like menus and complex interaction with any AppKit control that implements its own event
///   loop. Since those controls usually only enter those loops as the result of a mouse down dispatched on the main loop,
///   this catches the vast majority of clicks, except on menus (both the menu bar, and pop-up menus).
///
/// * A notification observer for `NSMenu.didSendActionNotification` is set up, being triggered every time a menu
///   item is selected and, as a consequence, sends an action to its target.
internal final class DDApplicationInstrumentation {
    /// `userInfo` key carrying the selected `NSMenuItem` in `NSMenu.didSendActionNotification`.
    private static let menuItemUserInfoKey = "MenuItem"

    /// The local event monitor.
    ///
    /// This monitor tracks `.leftMouseDown` events dispatched through the main event tracking loop. This excludes
    /// nested event tracking loops, like menus and complex interaction with any AppKit control that implements its own event
    /// loop. Since those controls usually only enter those loops as the result of a mouse down dispatched on the main loop,
    /// this catches the vast majority of clicks, except on menus (both the menu bar, and pop-up menus).
    private(set) var eventMonitor: Any?

    /// A notification observer for `NSMenu.didSendActionNotification`.
    ///
    /// This observer is triggered every time a menu item is selected and, as a consequence, sends an action to its target.
    /// The instrumentation receives the selected `NSMenuItem` and tracks the action accordingly.
    private(set) var menuObserver: NSObjectProtocol?

    /// The action handler used to processed the tracked elements.
    private let handler: RUMActionsHandling

    /// Creates a new `DDApplicationInstrumentation`.
    ///
    /// Note creating an instance by itself does nothing. The instrumentation needs to be started by calling `install()`
    /// and stopped by calling `uninstall()`. `uninstall()` will also be called automatically on deinit.
    init(handler: RUMActionsHandling) throws {
        self.handler = handler
    }

    deinit {
        uninstall()
    }

    /// Installs and starts the instrumentation facilities.
    func install() {
        installEventMonitor()
        installMenuObserver()
    }

    /// Stops and uninstalls the instrumentation facilities.
    internal func uninstall() {
        eventMonitor.map { NSEvent.removeMonitor($0) }
        eventMonitor = nil

        menuObserver.map { NotificationCenter.default.removeObserver($0) }
        menuObserver = nil
    }

    /// Installs the local event monitor that tracks `.leftMouseDown` events dispatched through the main event tracking loop.
    ///
    /// Read the documentation of `eventMonitor` for more information.
    private func installEventMonitor() {
        eventMonitor.map { NSEvent.removeMonitor($0) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak handler] event in
            handler?.notify_sendEvent(event: event)
            return event
        }
    }

    /// Creates the notification observer for `NSMenu.didSendActionNotification` to track menu usage.
    ///
    /// Read the documentation of `menuObserver` for more details.
    private func installMenuObserver() {
        menuObserver.map { NotificationCenter.default.removeObserver($0) }
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didSendActionNotification,
            object: nil,
            queue: .main
        ) { [weak handler] notification in
            guard let menuItem = notification.userInfo?[Self.menuItemUserInfoKey] as? NSMenuItem else {
                return
            }
            handler?.notify_menuItemSelected(menuItem)
        }
    }
}
#endif
