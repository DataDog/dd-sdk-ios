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
        @convention(c) (NSControl, Selector, Selector?, Any?) -> Bool,
        @convention(block) (NSControl, Selector?, Any?) -> Bool
    > {
        private static let selector = #selector(NSControl.sendAction(_:to:))
        private let method: Method
        private let handler: RUMActionsHandling

        init(handler: RUMActionsHandling) throws {
            self.method = try dd_class_getInstanceMethod(NSControl.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (NSControl, Selector?, Any?) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] control, selector, target  in
                    let result = previousImplementation(control, Self.selector, selector, target)
                    if result {
                        handler?.notify_sendAction(control: control, action: selector, target: target)
                    }
                    return result
                }
            }
        }
    }
}
#endif
