/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if canImport(SwiftUI)
import SwiftUI

/// `SwiftUI.ViewModifier` for RUM which invoke `addUserAction` from the
/// global RUM Monitor when the modified view receives a tap.
@available(iOS 13, *)
internal struct RUMTapActionModifier: SwiftUI.ViewModifier {
    /// The required number of taps to complete the tap action.
    let count: Int

    /// Action Name used for RUM Explorer.
    let name: String

    /// Custom attributes to attach to the Action.
    let attributes: [AttributeKey: AttributeValue]

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture(count: count).onEnded { _ in
                Global.rum.addUserAction(type: .tap, name: name, attributes: attributes)
            }
        )
    }
}

/// `SwiftUI.ViewModifier` for RUM which invoke `addUserAction` from the
/// global RUM Monitor when the modified view receives a swipe.
@available(iOS 13, *)
internal struct RUMSwipeActionModifier: SwiftUI.ViewModifier {
    /// The minimum dragging distance before the gesture succeeds.
    let minimumDistance: CGFloat

    /// Action Name used for RUM Explorer.
    let name: String

    /// Custom attributes to attach to the Action.
    let attributes: [AttributeKey: AttributeValue]

    /// Start state of the drag gesture.
    @State private var started = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: minimumDistance, coordinateSpace: .local)
                .onChanged { _ in
                    if !started {
                        started.toggle()
                        Global.rum.stopUserAction(type: .swipe, name: name, attributes: attributes)
                    }
                }
                .onEnded { _ in
                    if started {
                        Global.rum.stopUserAction(type: .swipe, name: name, attributes: attributes)
                        started.toggle()
                    }
                }
        )
    }
}

@available(iOS 13, *)
public extension SwiftUI.View {
    /// Monitor this view tap actions with Datadog RUM. An Action event will be logged after a number
    /// of required tap.
    ///
    /// - Parameters:
    ///   - name: The action name.
    ///   - attributes: custom attributes to attach to the View.
    ///   - count: The required number of taps to complete the tap action.
    /// - Returns: This view after applying a `ViewModifier` for monitoring the view.
    func trackRUMTapAction(
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:],
        count: Int = 1
    ) -> some View {
        return modifier(RUMTapActionModifier(count: count, name: name, attributes: attributes))
    }

    /// Monitor this view swipe actions with Datadog RUM. An Action event will be logged after the required
    /// minimum dragging distance
    ///
    /// - Parameters:
    ///   - name: The action name.
    ///   - attributes: custom attributes to attach to the View.
    ///   - minimumDistance: The minimum dragging distance for the action to
    ///     succeed.
    /// - Returns: This view after applying a `ViewModifier` for monitoring the view.
    func trackRUMSwipeAction(
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:],
        minimumDistance: CGFloat = 10
    ) -> some View {
        return modifier(RUMSwipeActionModifier(minimumDistance: minimumDistance, name: name, attributes: attributes))
    }
}

#endif
