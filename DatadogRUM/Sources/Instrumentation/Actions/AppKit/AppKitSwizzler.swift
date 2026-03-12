/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit
import DatadogInternal

internal final class DDApplicationSwizzler {
    let sendEvent: SendEvent
    let sendAction: NSControlSendAction

    init(handler: RUMActionsHandling) throws {
        sendEvent = try SendEvent(handler: handler)
        sendAction = try NSControlSendAction(handler: handler)
    }

    func swizzle() {
        sendEvent.swizzle()
        sendAction.swizzle()
    }

    internal func unswizzle() {
        sendEvent.unswizzle()
        sendAction.unswizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles the `DDApplication.sendEvent(_:)`
    class SendEvent: MethodSwizzler <
        @convention(c) (DDApplication, Selector, DDEvent) -> Bool,
        @convention(block) (DDApplication, DDEvent) -> Bool
    > {
        private static let selector = #selector(DDApplication.sendEvent(_:))
        private let method: Method
        private let handler: RUMActionsHandling

        init(handler: RUMActionsHandling) throws {
            self.method = try dd_class_getInstanceMethod(DDApplication.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (DDApplication, DDEvent) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] application, event  in
                    handler?.notify_sendEvent(application: application, event: event)
                    return previousImplementation(application, Self.selector, event)
                }
            }
        }
    }

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
//                    handler?.notify_sendEvent(application: application, event: event)
                    print("Swizzled sendAction(\(selector), to:\(target)) on \(control)")
                    return previousImplementation(control, Self.selector, selector, target)
                }
            }
        }
    }
}
#endif
