/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
#if canImport(SwiftUI)
import SwiftUI
import DatadogInternal

#if !os(tvOS)

/// `SwiftUI.ViewModifier` which notifies RUM instrumentation when the modified view is tapped.
/// It serves as an entry point to RUM actions instrumentation in SwiftUI.
///
/// ⚠️ **Important:**
/// - Do **not** use this modifier on views inside a `List`, as it can interfere with SwiftUI's built-in gesture handling,
///   preventing default interactions (e.g., `Button` actions or `NavigationLink` navigation).
/// - This issue stems from SwiftUI's gesture resolution, where adding an additional `TapGesture` can override system gestures.
/// - If tracking taps inside a `List` is required, consider logging actions manually via `RUMMonitor.shared().addAction(...)`
///   instead of using this modifier.
/// - We consider this a bug in SwiftUI and have reported it to Apple: [FB16488816](https://openradar.appspot.com/FB16488816).
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
    /// Monitor tap actions on this view with Datadog RUM. An Action event will be logged after the required number of taps.
    ///
    /// ⚠️ **Warning:**
    /// - Do **not** apply this modifier inside a `List`, as it can interfere with SwiftUI’s built-in gesture resolution.
    /// - Using this on a `Button` or `NavigationLink` inside a `List` will likely **disable** their default behavior.
    /// - If tracking taps inside a `List` is required, use `RUMMonitor.shared().addAction(...)` in the button’s action instead.
    ///
    /// - Parameters:
    ///   - name: The action name.
    ///   - attributes: Custom attributes to attach to the View.
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
#endif
