/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI)
import SwiftUI
import DatadogInternal

/// `SwiftUI.ViewModifier` which notifes RUM instrumentation when modified view appears and disappears.
/// It makes an entry point to RUM views instrumentation in SwiftUI.
@available(iOS 13, tvOS 13, *)
internal struct RUMViewModifier: SwiftUI.ViewModifier {
    /// Datadog RUM instrumentation instance
    let instrumentation: RUMInstrumentation?

    /// The Content View identifier.
    /// The id will be unique per modified view.
    let identity: String = UUID().uuidString

    /// View Name used for RUM Explorer.
    let name: String

    /// View Path used for RUM Explorer.
    let path: String

    /// Custom attributes to attach to the View.
    let attributes: [AttributeKey: AttributeValue]

    func body(content: Content) -> some View {
        content.onAppear {
            instrumentation?.viewsHandler
                .notify_onAppear(
                    identity: identity,
                    name: name,
                    path: path,
                    attributes: attributes
                )
        }
        .onDisappear {
            instrumentation?.viewsHandler
                .notify_onDisappear(identity: identity)
        }
    }
}

@available(iOS 13, tvOS 13, *)
public extension SwiftUI.View {
    /// Monitor this view with Datadog RUM. A start and stop events will be logged when this view appears
    /// and disappears.
    ///
    /// - Parameters:
    ///   - name: the View name used for RUM Explorer.
    ///   - attributes: custom attributes to attach to the View.
    ///   - core: The SDK core instance.
    /// - Returns: This view after applying a `ViewModifier` for monitoring the view.
    func trackRUMView(
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:],
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> some View {
        let path = "\(name)/\(typeDescription.hashValue)"
        let instrumentation = core.get(feature: RUMFeature.self)?.instrumentation
        return modifier(
            RUMViewModifier(
                instrumentation: instrumentation,
                name: name,
                path: path,
                attributes: attributes
            )
        )
    }
}

#endif
