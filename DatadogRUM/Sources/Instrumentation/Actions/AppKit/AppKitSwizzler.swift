/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit
import DatadogInternal

internal final class DDApplicationSwizzler {
    private(set) var eventMonitor: Any?
    let sendAction: NSControlSendAction
    let handler: RUMActionsHandling

    init(handler: RUMActionsHandling) throws {
        self.sendAction = try NSControlSendAction(handler: handler)
        self.handler = handler
    }

    func swizzle() {
        sendAction.swizzle()
        eventMonitor.map { NSEvent.removeMonitor($0) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak handler] event in
            handler?.notify_sendEvent(event: event)
            return event
        })
    }

    internal func unswizzle() {
        sendAction.unswizzle()
        eventMonitor.map { NSEvent.removeMonitor($0) }
        eventMonitor = nil
    }

    // MARK: - Swizzlings

    class NSControlSendAction: MethodSwizzler <
        @convention(c) (NSApplication, Selector, Selector?, Any?, Any?) -> Bool,
        @convention(block) (NSApplication, Selector?, Any?, Any?) -> Bool
    > {
        private static let selector = #selector(NSApplication.sendAction(_:to:from:))
        private let method: Method
        private let handler: RUMActionsHandling

        init(handler: RUMActionsHandling) throws {
            self.method = try dd_class_getInstanceMethod(NSApplication.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (NSApplication, Selector?, Any?, Any?) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] app, selector, target, from in
                    let result = previousImplementation(app, Self.selector, selector, target, from)
                    if result {
                        handler?.notify_sendAction(app: app, action: selector, target: target, from: from)
                    }
                    return result
                }
            }
        }
    }
}
#endif
