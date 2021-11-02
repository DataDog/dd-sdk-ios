/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal class UIApplicationSwizzler {
    let sendEvent: SendEvent

    init(handler: UIEventHandler) throws {
        sendEvent = try SendEvent(handler: handler)
    }

    func swizzle() {
        sendEvent.swizzle()
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func unswizzle() {
        sendEvent.unswizzle()
    }
#endif

    // MARK: - Swizzlings

    /// Swizzles the `UIApplication.sendEvent(_:)`
    class SendEvent: MethodSwizzler <
        @convention(c) (UIApplication, Selector, UIEvent) -> Bool,
        @convention(block) (UIApplication, UIEvent) -> Bool
    > {
        private static let selector = #selector(UIApplication.sendEvent(_:))
        private let method: FoundMethod
        private let handler: UIEventHandler

        init(handler: UIEventHandler) throws {
            self.method = try Self.findMethod(with: Self.selector, in: UIApplication.self)
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
