/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// `CALayerSwizzler` observes `CALayer` display, drawing, and layout without
// altering its behavior.

#if os(iOS)
import QuartzCore
import DatadogInternal

internal protocol CALayerObserver: AnyObject {
    func layerDidDisplay(_ layer: CALayer)
    func layerDidDraw(_ layer: CALayer, in context: CGContext)
    func layerDidLayoutSublayers(_ layer: CALayer)
}

internal final class CALayerSwizzler {
    private let display: Display
    private let draw: Draw
    private let layoutSublayers: LayoutSublayers

    init(observer: CALayerObserver) throws {
        self.display = try Display(observer: observer)
        self.draw = try Draw(observer: observer)
        self.layoutSublayers = try LayoutSublayers(observer: observer)
    }

    func swizzle() {
        display.swizzle()
        draw.swizzle()
        layoutSublayers.swizzle()
    }

    func unswizzle() {
        display.unswizzle()
        draw.unswizzle()
        layoutSublayers.unswizzle()
    }

    private class Display: MethodSwizzler<
        @convention(c) (CALayer, Selector) -> Void,
        @convention(block) (CALayer) -> Void
    > {
        private static let selector = #selector(CALayer.display)

        private let method: Method
        private let observer: CALayerObserver

        init(observer: CALayerObserver) throws {
            self.method = try dd_class_getInstanceMethod(CALayer.self, Self.selector)
            self.observer = observer
        }

        func swizzle() {
            swizzle(method) { implementation in
                { [weak observer = self.observer] layer in
                    implementation(layer, Self.selector)
                    observer?.layerDidDisplay(layer)
                }
            }
        }
    }

    private class Draw: MethodSwizzler<
        @convention(c) (CALayer, Selector, CGContext) -> Void,
        @convention(block) (CALayer, CGContext) -> Void
    > {
        private static let selector = #selector(CALayer.draw(in:))

        private let method: Method
        private let observer: CALayerObserver

        init(observer: CALayerObserver) throws {
            self.method = try dd_class_getInstanceMethod(CALayer.self, Self.selector)
            self.observer = observer
        }

        func swizzle() {
            swizzle(method) { implementation in
                { [weak observer = self.observer] layer, context in
                    implementation(layer, Self.selector, context)
                    observer?.layerDidDraw(layer, in: context)
                }
            }
        }
    }

    private class LayoutSublayers: MethodSwizzler<
        @convention(c) (CALayer, Selector) -> Void,
        @convention(block) (CALayer) -> Void
    > {
        private static let selector = #selector(CALayer.layoutSublayers)

        private let method: Method
        private let observer: CALayerObserver

        init(observer: CALayerObserver) throws {
            self.method = try dd_class_getInstanceMethod(CALayer.self, Self.selector)
            self.observer = observer
        }

        func swizzle() {
            swizzle(method) { implementation in
                { [weak observer = self.observer] layer in
                    implementation(layer, Self.selector)
                    observer?.layerDidLayoutSublayers(layer)
                }
            }
        }
    }
}
#endif
