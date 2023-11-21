/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

internal class UIApplicationSwizzler {
    let sendEvent: SendEvent

    init(handler: UIEventHandler) throws {
        sendEvent = try SendEvent(handler: handler)
    }

    func swizzle() {
        sendEvent.swizzle()
    }

    internal func unswizzle() {
        sendEvent.unswizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles the `UIApplication.sendEvent(_:)`
    class SendEvent: MethodSwizzler <
        @convention(c) (UIApplication, Selector, UIEvent) -> Bool,
        @convention(block) (UIApplication, UIEvent) -> Bool
    > {
        private static let selector = #selector(UIApplication.sendEvent(_:))
        private let method: Method
        private let handler: UIEventHandler

        init(handler: UIEventHandler) throws {
            self.method = try dd_sel_findMethod(Self.selector, in: UIApplication.self)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (UIApplication, UIEvent) -> Bool
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] application, event  in
                    handler?.notify_sendEvent(application: application, event: event)
                    return previousImplementation(application, Self.selector, event)
                }
            }
        }
    }
}
