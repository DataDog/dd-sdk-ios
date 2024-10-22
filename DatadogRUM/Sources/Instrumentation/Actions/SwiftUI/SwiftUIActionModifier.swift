/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(SwiftUI)
import SwiftUI
import DatadogInternal

#if !os(tvOS)

/// `SwiftUI.ViewModifier` which notifes RUM instrumentation when modified view is tapped.
/// It makes an entry point to RUM actions instrumentation in SwiftUI.
@available(iOS 13, *)
internal struct RUMTapActionModifier: SwiftUI.ViewModifier {
    /// The SDK core instance.
    weak var core: DatadogCoreProtocol?

    /// The required number of taps to complete the tap action.
    let count: Int

    /// Action Name used for RUM Explorer.
    let name: String

    /// Custom attributes to attach to the Action.
    let attributes: [String: Encodable]

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture(count: count).onEnded { _ in
                guard let core = core else {
                    return // core was deallocated
                }
                guard let feature = core.get(feature: RUMFeature.self) else {
                    return // RUM not enabled
                }
                feature.instrumentation.actionsHandler
                    .notify_viewModifierTapped(actionName: name, actionAttributes: attributes)
            }
        )
    }
}

@available(iOS 13, *)
public extension SwiftUI.View {
    /// Monitor this view tap actions with Datadog RUM. An Action event will be logged after a number
    /// of required taps.
    ///
    /// - Parameters:
    ///   - name: The action name.
    ///   - attributes: custom attributes to attach to the View.
    ///   - count: The required number of taps to complete the tap action.
    ///   - core: The SDK core instance.
    /// - Returns: This view after applying a `ViewModifier` for monitoring the view.
    func trackRUMTapAction(
        name: String,
        attributes: [String: Encodable] = [:],
        count: Int = 1,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) -> some View {
        return modifier(
            RUMTapActionModifier(
                core: core,
                count: count,
                name: name,
                attributes: attributes
            )
        )
    }
}

#endif
#endif
