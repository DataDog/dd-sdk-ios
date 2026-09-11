/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import UIKit
import DatadogInternal

/// Factory responsible for creating RUM user action commands from UIEvents.
/// This abstraction allows for platform-specific implementations (iOS/tvOS).
internal protocol UIEventCommandFactory {
    /// Resolves the event's scene and creates a RUM command if applicable.
    /// Scene resolution is independent from action eligibility so customer
    /// work dispatched by a filtered interaction still receives the correct
    /// request-local RUM context.
    /// - Parameter event: The `UIEvent` to process
    func result(from event: UIEvent) -> UIEventCommandResult
}

internal struct UIEventCommandResult {
    let command: RUMAddUserActionCommand?
    let target: RUMCommandTarget?
}

// MARK: iOS implementation
/// iOS-specific implementation that detects user interactions through touches.
/// Handles both UIKit and SwiftUI components using different detection strategies.
internal final class UITouchCommandFactory: UIEventCommandFactory {
    let dateProvider: DateProvider
    let heatmapIdentifierRegistry: any HeatmapIdentifierRegistry
    let uiKitPredicate: UITouchRUMActionsPredicate?
    let swiftUIPredicate: SwiftUIRUMActionsPredicate?
    let swiftUIDetector: SwiftUIComponentDetector?
    let sceneIdentifierProvider: (UIView) -> RUMSceneIdentifier?

    init(
        dateProvider: DateProvider,
        heatmapIdentifierRegistry: any HeatmapIdentifierRegistry,
        uiKitPredicate: UITouchRUMActionsPredicate?,
        swiftUIPredicate: SwiftUIRUMActionsPredicate?,
        swiftUIDetector: SwiftUIComponentDetector?,
        sceneIdentifierProvider: @escaping (UIView) -> RUMSceneIdentifier? = { view in
            guard let identifier = view.window?
                .windowScene?
                .session
                .persistentIdentifier else {
                return nil
            }
            return RUMSceneIdentifier(rawValue: identifier)
        }
    ) {
        self.dateProvider = dateProvider
        self.heatmapIdentifierRegistry = heatmapIdentifierRegistry
        self.uiKitPredicate = uiKitPredicate
        self.swiftUIPredicate = swiftUIPredicate
        self.swiftUIDetector = swiftUIDetector
        self.sceneIdentifierProvider = sceneIdentifierProvider
    }

    func result(from event: UIEvent) -> UIEventCommandResult {
        guard let allTouches = event.allTouches else {
            return UIEventCommandResult(command: nil, target: nil)
        }
        guard !allTouches.isEmpty else {
            return UIEventCommandResult(command: nil, target: nil)
        }

        if allTouches.count > 1 {
            let sceneIdentifiers = allTouches.compactMap { touch in
                touch.view.flatMap(sceneIdentifierProvider)
            }
            let uniqueScenes = Set(sceneIdentifiers)
            let target = sceneIdentifiers.count == allTouches.count && uniqueScenes.count == 1
                ? uniqueScenes.first.map(RUMCommandTarget.scene)
                : nil
            // Multi-touch gestures are not tap actions, but customer callbacks
            // still receive a source-scene scope when every touch agrees.
            return UIEventCommandResult(command: nil, target: target)
        }
        guard let tap = allTouches.first else {
            return UIEventCommandResult(command: nil, target: nil)
        }
        let target = target(for: tap.view)

        // Detect UIKit interactions first,
        // as they are more likely to happen.
        if var rumAction = createUIKitActionCommand(from: tap) {
            rumAction.target = target
            return UIEventCommandResult(command: rumAction, target: target)
        }

        guard swiftUIPredicate != nil,
              var command = swiftUIDetector?.createActionCommand(
            from: tap,
            predicate: swiftUIPredicate,
            dateProvider: dateProvider
        ) else {
            return UIEventCommandResult(command: nil, target: target)
        }
        command.target = target
        return UIEventCommandResult(command: command, target: target)
    }

    // MARK: UIKit

    private func createUIKitActionCommand(from tap: UITouch) -> RUMAddUserActionCommand? {
        guard let uiKitPredicate else {
            return nil
        }

        guard tap.phase == .ended else {
            return nil // not in `.ended` phase
        }

        guard let view = tap.view else {
            return nil
        }

        guard view.isSafeForPrivacy else {
            return nil // no valid view
        }

        guard let targetView = bestActionTarget(for: view) else {
            return nil // Tapped view is not eligible for producing RUM Action
        }

        guard let action = uiKitPredicate.rumAction(targetView: targetView) else {
            return nil
        }

        var heatmapAttributes: HeatmapAttributes?

        // Heatmap identifiers are looked up by `tap.view`, not the action target
        if let heatmapIdentifier = heatmapIdentifierRegistry.heatmapIdentifier(for: ObjectIdentifier(view)) {
            heatmapAttributes = HeatmapAttributes(
                identifier: heatmapIdentifier,
                size: view.bounds.size,
                location: tap.location(in: view)
            )
        }

        return RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .uikit,
            actionType: .tap,
            name: action.name,
            heatmapAttributes: heatmapAttributes
        )
    }

    private func target(for view: UIView?) -> RUMCommandTarget {
        view.flatMap(sceneIdentifierProvider).map(RUMCommandTarget.scene)
            ?? .processRepresentative
    }

    /// Traverses the hierarchy of the `view` bottom-up to find the best view which could be considered for RUM Action's target,
    /// e.g. if the tapped `view` is a `UILabel` embedded in a `UIStackView` inside the `UITableViewCell` it will
    /// return the `UITableViewCell` as the best guess of user interaction.
    ///
    /// May return `nil` if there's no good guess and the RUM Action for given `view` should not be produced.
    private func bestActionTarget(for view: UIView) -> UIView? {
        if let uiControl = view as? UIControl {
            // If the `view` is a `UIControl` (interactive element), accept it.
            return uiControl
        } else {
            // If the `view` is not an interactive element, check if it's a child of a known view hierarchy
            // which can be considered as interactive.
            // For now this includes checking if the interacted view is an (in-)direct child of the `UITableViewCell`
            // or `UICollectionCell`, which is a common pattern when building list-based navigation on iOS.
            let bestParent = view.findInParentHierarchy { parent in
                return parent is UITableViewCell
                || parent is UICollectionViewCell
                || parent is UIControl
                || parent.isUIAlertActionView
                || parent.isUIAlertTextField
            }
            return bestParent // best parent or `nil`
        }
    }
}

// MARK: tvOS implementation
/// tvOS-specific implementation that detects user interactions through touches.
internal struct UIPressCommandFactory: UIEventCommandFactory {
    let dateProvider: DateProvider

    let uiKitPredicate: UIPressRUMActionsPredicate

    func result(from event: UIEvent) -> UIEventCommandResult {
        guard let event = event as? UIPressesEvent else {
            return UIEventCommandResult(command: nil, target: nil)
        }
        guard event.allPresses.count == 1, let press = event.allPresses.first else {
            return UIEventCommandResult(command: nil, target: nil)
        }
        guard let view = press.responder as? UIView else {
            return UIEventCommandResult(command: nil, target: nil)
        }
        let target: RUMCommandTarget
        if let identifier = view.window?.windowScene?.session.persistentIdentifier {
            target = .scene(RUMSceneIdentifier(rawValue: identifier))
        } else {
            target = .processRepresentative
        }
        guard press.phase == .ended,
              view.isSafeForPrivacy,
              let action = uiKitPredicate.rumAction(press: press.type, targetView: view) else {
            return UIEventCommandResult(command: nil, target: target)
        }
        var command = RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .uikit,
            actionType: .click,
            name: action.name
        )
        command.target = target
        return UIEventCommandResult(command: command, target: target)
    }
}
#endif
