/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

internal protocol CALayerHandler: AnyObject {
    func notify_setNeedsDisplay(layer: CALayer)
    func notify_draw(layer: CALayer, context: CGContext)
}

internal class CALayerSwizzler {
    private let setNeedsDisplaySwizzler: SetNeedsDisplaySwizzler
    private let drawSwizzler: DrawSwizzler

    init(handler: CALayerHandler) throws {
        self.setNeedsDisplaySwizzler = try SetNeedsDisplaySwizzler(handler: handler)
        self.drawSwizzler = try DrawSwizzler(handler: handler)
    }

    func swizzle() {
        setNeedsDisplaySwizzler.swizzle()
        drawSwizzler.swizzle()
    }

    func unswizzle() {
        setNeedsDisplaySwizzler.unswizzle()
        drawSwizzler.unswizzle()
    }

    // MARK: - Swizzlings

    /// Swizzles `CALayer.setNeedsDisplay`
    class SetNeedsDisplaySwizzler: MethodSwizzler<
        @convention(c) (CALayer, Selector) -> Void,
        @convention(block) (CALayer) -> Void
    > {
        private static let selector = #selector(CALayer.setNeedsDisplay as (CALayer) -> () -> Void)
        private let method: Method
        private let handler: CALayerHandler

        init(handler: CALayerHandler) throws {
            self.method = try dd_class_getInstanceMethod(CALayer.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (CALayer) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] layer in
                    handler?.notify_setNeedsDisplay(layer: layer)
                    previousImplementation(layer, Self.selector)
                }
            }
        }
    }

    /// Swizzles `CALayer.draw(in:)`
    class DrawSwizzler: MethodSwizzler<
        @convention(c) (CALayer, Selector, CGContext) -> Void,
        @convention(block) (CALayer, CGContext) -> Void
    > {
        private static let selector = #selector(CALayer.draw(in:))
        private let method: Method
        private let handler: CALayerHandler

        init(handler: CALayerHandler) throws {
            self.method = try dd_class_getInstanceMethod(CALayer.self, Self.selector)
            self.handler = handler
        }

        func swizzle() {
            typealias Signature = @convention(block) (CALayer, CGContext) -> Void
            swizzle(method) { previousImplementation -> Signature in
                return { [weak handler = self.handler] layer, context in
                    handler?.notify_draw(layer: layer, context: context)
                    previousImplementation(layer, Self.selector, context)
                }
            }
        }
    }
}
#endif
