/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS) || os(visionOS)

import UIKit
@_spi(Internal)
import DatadogInternal

/// Handles scroll and swipe gesture detection on UIScrollView-based components.
/// Tracks scroll lifecycle events, classifies gestures as scroll or swipe based on velocity,
/// and generates RUM commands for the action pipeline.
internal final class RUMScrollHandler: UIScrollViewHandler {
    /// Velocity threshold (in points/second) to classify a gesture as a swipe vs. scroll.
    /// Gestures with velocity magnitude >= this value are classified as swipe.
    static let velocityThreshold: CGFloat = 500

    /// Attribute key for gesture direction, matching Android's `action.gesture.direction`.
    static let gestureDirectionAttribute: String = "action.gesture.direction"

    /// State tracked for an active scroll gesture.
    private struct ScrollState {
        let startTime: Date
        let startOffset: CGPoint
        let actionName: String
        /// Velocity captured when the user lifts their finger (end of drag).
        /// This is the only reliable moment to read velocity — after deceleration it's zero.
        var liftVelocity: CGPoint?
    }

    private let dateProvider: DateProvider
    private let predicate: UITouchRUMActionsPredicate

    weak var subscriber: RUMCommandSubscriber?

    /// Active scrolls keyed by scroll view identity.
    private var activeScrolls: [ObjectIdentifier: ScrollState] = [:]

    init(
        dateProvider: DateProvider,
        predicate: UITouchRUMActionsPredicate
    ) {
        self.dateProvider = dateProvider
        self.predicate = predicate
    }

    // MARK: - RUMCommandPublisher

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    // MARK: - UIScrollViewHandler

    /// Called when the user begins dragging.
    func notify_scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Only track user-initiated scrolls
        guard scrollView.panGestureRecognizer.state == .began || scrollView.panGestureRecognizer.state == .changed else {
            return
        }

        guard let action = predicate.rumAction(targetView: scrollView) else {
            return // Filtered by predicate
        }

        // If there's an active scroll on this view (e.g. user started dragging during deceleration),
        // finalize the previous one before starting a new one.
        finalizeScrollIfNeeded(scrollView)

        let state = ScrollState(
            startTime: dateProvider.now,
            startOffset: scrollView.contentOffset,
            actionName: action.name
        )

        activeScrolls[ObjectIdentifier(scrollView)] = state

        let command = RUMStartUserActionCommand(
            time: state.startTime,
            globalAttributes: [:],
            attributes: action.attributes,
            instrumentation: .uikit,
            actionType: .scroll,
            name: action.name
        )

        subscriber?.process(command: command)
    }

    /// Called when dragging ends. Captures lift velocity while the gesture recognizer still has it.
    /// If no deceleration follows, finalizes the scroll immediately.
    func notify_scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let id = ObjectIdentifier(scrollView)

        // Capture velocity now — after deceleration it will be zero
        let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
        activeScrolls[id]?.liftVelocity = velocity

        if !decelerate {
            finalizeScroll(scrollView)
        }
    }

    /// Called when deceleration completes after a fling. Finalize the gesture.
    func notify_scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finalizeScroll(scrollView)
    }

    // MARK: - Private

    /// Finalizes the active scroll on this view if one exists. Called before starting a new scroll
    /// to ensure every START has a matching STOP (e.g. when the user drags during deceleration).
    private func finalizeScrollIfNeeded(_ scrollView: UIScrollView) {
        let id = ObjectIdentifier(scrollView)

        if activeScrolls[id] != nil {
            finalizeScroll(scrollView)
        }
    }

    private func finalizeScroll(_ scrollView: UIScrollView) {
        let id = ObjectIdentifier(scrollView)

        guard let state = activeScrolls.removeValue(forKey: id) else {
            return
        }

        let velocity = state.liftVelocity ?? .zero
        let gestureType = classifyGesture(velocity: velocity)
        let direction = calculateDirection(start: state.startOffset, end: scrollView.contentOffset)

        var attributes: [AttributeKey: AttributeValue] = [:]
        attributes[Self.gestureDirectionAttribute] = direction

        let command = RUMStopUserActionCommand(
            time: dateProvider.now,
            globalAttributes: [:],
            attributes: attributes,
            actionType: gestureType,
            name: state.actionName
        )

        subscriber?.process(command: command)
    }

    private func classifyGesture(velocity: CGPoint) -> RUMActionType {
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        return speed >= Self.velocityThreshold ? .swipe : .scroll
    }

    private func calculateDirection(start: CGPoint, end: CGPoint) -> String {
        let dx = end.x - start.x
        let dy = end.y - start.y

        if abs(dx) > abs(dy) {
            return dx > 0 ? "right" : "left"
        } else {
            return dy > 0 ? "down" : "up"
        }
    }
}

#endif

#if os(iOS)

/// Resolved-On ownership adapter; gesture classification stays in the legacy handler.
@available(iOS 27.0, *)
internal final class RUMSceneScrollHandler: UIScrollViewHandler, RUMCommandSubscriber {
    private struct Capture {
        let scene: RUMSceneIdentifier?
        let value: RUMContextHandoff.CurrentValue?

        func pending(receipt: RUMContextHandoff.ActionReceipt?) -> Capture {
            Capture(scene: scene, value: value.map {
                RUMContextHandoff.CurrentValue(
                    rumContext: $0.rumContext,
                    sceneIdentifier: $0.sceneIdentifier,
                    hasPendingUserAction: true,
                    excludedUserActionID: $0.rumContext?.userActionID,
                    actionReceipt: receipt
                )
            })
        }

        /// Terminal callbacks cannot expose a prior or queued action's identity.
        var terminal: Capture {
            Capture(scene: scene, value: scene.map {
                RUMContextHandoff.CurrentValue(
                    rumContext: nil,
                    sceneIdentifier: $0.rawValue,
                    hasPendingUserAction: false,
                    excludedUserActionID: nil
                )
            })
        }
    }

    private struct Gesture {
        let ownership: RUMContinuousActionOwnership
        let capture: Capture
    }

    private struct PublicationFrame {
        let scrollID: ObjectIdentifier
        let capture: Capture
        var publishedStart: Capture?
    }

    private let legacyHandler: RUMScrollHandler
    private let dateProvider: DateProvider
    private let owner: RUMContextHandoff.Owner
    private weak var expectedMonitor: Monitor?
    private weak var subscriber: RUMCommandSubscriber?
    private let sceneIdentifier: (UIWindow) -> RUMSceneIdentifier?
    private var gestures: [ObjectIdentifier: Gesture] = [:]
    private var publicationFrame: PublicationFrame?

    init(
        legacyHandler: RUMScrollHandler,
        dateProvider: DateProvider,
        owner: RUMContextHandoff.Owner,
        expectedMonitor: Monitor,
        sceneIdentifier: @escaping (UIWindow) -> RUMSceneIdentifier? = {
            $0.windowScene.map { RUMSceneIdentifier(rawValue: $0.session.persistentIdentifier) }
        }
    ) {
        self.legacyHandler = legacyHandler
        self.dateProvider = dateProvider
        self.owner = owner
        self.expectedMonitor = expectedMonitor
        self.sceneIdentifier = sceneIdentifier
        legacyHandler.publish(to: self)
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
        legacyHandler.publish(to: self)
    }

    func notify_scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        interceptWillBeginDragging(scrollView, operation: {})
    }

    func notify_scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        interceptDidEndDragging(scrollView, willDecelerate: willDecelerate, operation: {})
    }

    func notify_scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        interceptDidEndDecelerating(scrollView, operation: {})
    }

    func interceptWillBeginDragging(_ scrollView: UIScrollView, operation: () -> Void) {
        // Capture before the customer predicate can move the view or start navigation.
        let capture = captureSource(scrollView)
        let previousFrame = publicationFrame
        publicationFrame = PublicationFrame(scrollID: ObjectIdentifier(scrollView), capture: capture)
        defer { publicationFrame = previousFrame }
        withCapture(capture) {
            legacyHandler.notify_scrollViewWillBeginDragging(scrollView)
            withCapture(publicationFrame?.publishedStart ?? capture, operation: operation)
        }
    }

    func interceptDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool, operation: () -> Void) {
        let id = ObjectIdentifier(scrollView)
        let capture = gestures[id]?.capture.terminal ?? Capture(scene: nil, value: nil)
        let previousFrame = publicationFrame
        publicationFrame = PublicationFrame(scrollID: id, capture: capture)
        defer { publicationFrame = previousFrame }
        withCapture(capture) {
            legacyHandler.notify_scrollViewDidEndDragging(scrollView, willDecelerate: willDecelerate)
            operation()
        }
    }

    func interceptDidEndDecelerating(_ scrollView: UIScrollView, operation: () -> Void) {
        let id = ObjectIdentifier(scrollView)
        let capture = gestures[id]?.capture.terminal ?? Capture(scene: nil, value: nil)
        let previousFrame = publicationFrame
        publicationFrame = PublicationFrame(scrollID: id, capture: capture)
        defer { publicationFrame = previousFrame }
        withCapture(capture) {
            legacyHandler.notify_scrollViewDidEndDecelerating(scrollView)
            operation()
        }
    }

    func process(command: RUMCommand) {
        guard let frame = publicationFrame else {
            return
        }
        if var start = command as? RUMStartUserActionCommand {
            guard isOwnedSubscriber else {
                return
            }
            let ownership = RUMContinuousActionOwnership(sceneIdentifier: frame.capture.scene, owner: owner)
            start.target = .continuousAction(ownership)
            let receipt = frame.capture.value.map {
                RUMContextHandoff.ActionReceipt(owner: owner, context: $0.rumContext)
            }
            start.actionReceipt = receipt
            let pending = frame.capture.pending(receipt: receipt)
            let gesture = Gesture(ownership: ownership, capture: frame.capture)
            // Reentrant customer code can end this gesture while processing its Start.
            gestures[frame.scrollID] = gesture
            let published = withCapture(pending) {
                publishIfOwned(start)
            }
            if published {
                publicationFrame?.publishedStart = pending
            } else {
                receipt?.reject()
                if gestures[frame.scrollID]?.ownership === ownership {
                    gestures.removeValue(forKey: frame.scrollID)
                }
            }
        } else if var stop = command as? RUMStopUserActionCommand,
                  let gesture = gestures.removeValue(forKey: frame.scrollID) {
            stop.target = .continuousAction(gesture.ownership)
            withCapture(gesture.capture.terminal) {
                _ = publishIfOwned(stop)
            }
        }
    }

    private func captureSource(_ scrollView: UIScrollView) -> Capture {
        guard let window = scrollView.window, let scene = sceneIdentifier(window) else {
            // Source-less callbacks preserve an inherited binding without inventing one.
            return Capture(scene: nil, value: nil)
        }
        let context: RUMCoreContext?
        if isOwnedSubscriber, let monitor = expectedMonitor {
            context = monitor.rumContextSnapshot(for: .scene(scene))
        } else {
            context = nil
        }
        return Capture(scene: scene, value: RUMContextHandoff.CurrentValue(
            rumContext: context,
            sceneIdentifier: scene.rawValue,
            hasPendingUserAction: false,
            excludedUserActionID: nil
        ))
    }

    private var isOwnedSubscriber: Bool {
        guard owner.isValid, let monitor = expectedMonitor, subscriber === monitor else {
            return false
        }
        return monitor.isMultiSceneTrackingEnabled && monitor.rumContextHandoffOwner === owner
    }

    private func publishIfOwned(_ command: RUMCommand) -> Bool {
        guard owner.isValid, let monitor = expectedMonitor, subscriber === monitor,
              monitor.isMultiSceneTrackingEnabled, monitor.rumContextHandoffOwner === owner else { return false }
        monitor.process(command: command)
        return true
    }

    private func withCapture<T>(_ capture: Capture, operation: () -> T) -> T {
        guard let value = capture.value else {
            return operation()
        }
        return RUMContextHandoff.withValue(value, for: owner, operation: operation)
    }
}

#endif
