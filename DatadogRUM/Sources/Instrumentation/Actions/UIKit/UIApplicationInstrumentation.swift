/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(UIKit) && !os(watchOS)
import UIKit
import DatadogInternal

internal class DDApplicationInstrumentation {
    let sendEvent: SendEvent

    init(handler: RUMActionsHandling) throws {
        sendEvent = try SendEvent(handler: handler)
    }

    func install() {
        sendEvent.swizzle()
    }

    internal func uninstall() {
        sendEvent.unswizzle()
    }

    deinit {
        sendEvent.unswizzle()
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
}
#endif

#if os(iOS)
/// Intercepts UIKit delivery with the captured scene ownership of the input.
@available(iOS 27.0, *)
internal final class DDSceneApplicationInstrumentation: DDApplicationInstrumentation {
    private let sceneSendEvent: SceneSendEvent

    init(handler: RUMSceneActionsHandling) throws {
        sceneSendEvent = try SceneSendEvent(handler: handler)
        try super.init(handler: handler)
    }

    override func install() {
        sceneSendEvent.swizzle()
    }

    override func uninstall() {
        sceneSendEvent.unswizzle()
    }

    deinit {
        sceneSendEvent.unswizzle()
    }

    /// UIKit's `sendEvent:` returns Void, independently of the legacy generic interceptor.
    final class SceneSendEvent: MethodSwizzler<
        @convention(c) (UIApplication, Selector, UIEvent) -> Void,
        @convention(block) (UIApplication, UIEvent) -> Void
    > {
        private static let selector = #selector(UIApplication.sendEvent(_:))
        private let method: Method
        private weak var handler: RUMSceneActionsHandling?

        init(handler: RUMSceneActionsHandling) throws {
            method = try dd_class_getInstanceMethod(UIApplication.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIApplication, UIEvent) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] application, event in
                    if let handler {
                        handler.intercept(application: application, event: event) {
                            previousImplementation(application, Self.selector, event)
                        }
                    } else {
                        previousImplementation(application, Self.selector, event)
                    }
                }
            }
        }
    }
}
#endif
