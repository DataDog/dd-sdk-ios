/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import UIKit
import DatadogInternal

/// Handles scroll and swipe gesture detection on UIScrollView-based components.
/// Tracks scroll lifecycle events, classifies gestures as scroll or swipe based on velocity,
/// and generates RUM commands for the action pipeline.
internal final class UIScrollViewScrollHandler: RUMCommandPublisher {
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

    /// Lock protecting `activeScrolls`.
    private let lock = NSLock()

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

    // MARK: - Scroll Lifecycle

    /// Called when the user begins dragging.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
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

        lock.lock()
        activeScrolls[ObjectIdentifier(scrollView)] = state
        lock.unlock()

        let command = RUMStartUserActionCommand(
            time: state.startTime,
            globalAttributes: [:],
            attributes: action.attributes,
            instrumentation: .uikit,
            actionType: .scroll,
            name: action.name
        )

        DD.logger.debug("🔄 [ScrollTracking] START: \(action.name) at offset \(state.startOffset)")
        subscriber?.process(command: command)
    }

    /// Called when dragging ends. Captures lift velocity while the gesture recognizer still has it.
    /// If no deceleration follows, finalizes the scroll immediately.
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let id = ObjectIdentifier(scrollView)

        // Capture velocity now — after deceleration it will be zero
        let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
        lock.lock()
        activeScrolls[id]?.liftVelocity = velocity
        lock.unlock()

        if !decelerate {
            finalizeScroll(scrollView)
        }
    }

    /// Called when deceleration completes after a fling. Finalize the gesture.
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finalizeScroll(scrollView)
    }

    /// Cleans up all active scroll states (e.g. on app backgrounding).
    func cancelAll() {
        lock.lock()
        activeScrolls.removeAll()
        lock.unlock()
    }

    // MARK: - Private

    /// Finalizes the active scroll on this view if one exists. Called before starting a new scroll
    /// to ensure every START has a matching STOP (e.g. when the user drags during deceleration).
    private func finalizeScrollIfNeeded(_ scrollView: UIScrollView) {
        let id = ObjectIdentifier(scrollView)

        lock.lock()
        let hasActiveScroll = activeScrolls[id] != nil
        lock.unlock()

        if hasActiveScroll {
            finalizeScroll(scrollView)
        }
    }

    private func finalizeScroll(_ scrollView: UIScrollView) {
        let id = ObjectIdentifier(scrollView)

        lock.lock()
        guard let state = activeScrolls.removeValue(forKey: id) else {
            lock.unlock()
            return
        }
        lock.unlock()

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

        DD.logger.debug("🔄 [ScrollTracking] STOP: \(state.actionName) type=\(gestureType == .swipe ? "swipe" : "scroll") direction=\(direction)")
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
