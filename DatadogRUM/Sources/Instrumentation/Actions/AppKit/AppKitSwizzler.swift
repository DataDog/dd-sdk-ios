/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit
import DatadogInternal

/// Installs AppKit action tracking without swizzling.
///
/// Two AppKit input modalities are observed:
/// - **Controls / toolbar / window chrome**: a local `NSEvent` monitor catches `leftMouseDown` and
///   hit-tests the clicked view.
/// - **Menu items**: `NSMenu.didSendActionNotification` is observed, since menu tracking runs its own
///   event pump and never surfaces clicks through the app's `NSEvent` queue (so the local monitor can't
///   see them). The notification fires right after AppKit dispatches a menu item's action and carries the
///   selected `NSMenuItem` in `userInfo["MenuItem"]`.
///
/// The type keeps the `DDApplicationSwizzler` name and `swizzle()`/`unswizzle()` lifecycle to stay
/// symmetric with the UIKit implementation and the shared call sites in `RUMInstrumentation`.
internal final class DDApplicationSwizzler {
    /// `userInfo` key carrying the selected `NSMenuItem` in `NSMenu.didSendActionNotification`.
    private static let menuItemUserInfoKey = "MenuItem"

    private(set) var eventMonitor: Any?
    private(set) var menuObserver: NSObjectProtocol?
    let handler: RUMActionsHandling

    init(handler: RUMActionsHandling) throws {
        self.handler = handler
    }

    func swizzle() {
        installEventMonitor()
        installMenuObserver()
    }

    internal func unswizzle() {
        eventMonitor.map { NSEvent.removeMonitor($0) }
        eventMonitor = nil

        menuObserver.map { NotificationCenter.default.removeObserver($0) }
        menuObserver = nil
    }

    /// Observes `leftMouseDown` events for controls, toolbar items and window chrome.
    private func installEventMonitor() {
        eventMonitor.map { NSEvent.removeMonitor($0) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak handler] event in
            handler?.notify_sendEvent(event: event)
            return event
        }
    }

    /// Observes menu item selections, which the local event monitor cannot see.
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
