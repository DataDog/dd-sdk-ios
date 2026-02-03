/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Resolves the app's launch reason (`LaunchReason`) for platforms like tvOS, where
/// it cannot be determined immediately at SDK initialization (e.g., no `task_role` kernel's API support).
///
/// The resolver uses a short launch window and app state heuristics to infer whether the app
/// was launched by the user or in the background. During this window, incoming RUM commands
/// are buffered along with their context and writer.
///
/// Once the reason is resolved (based on app state, lifecycle events, or time), all buffered
/// commands are forwarded in FIFO order with the resolved `launchReason` injected into their contexts.
internal final class LaunchReasonResolver {
    /// Launch window configuration constants.
    enum Constants {
        /// Time to wait before assuming a background launch.
        static let launchWindowThreshold: TimeInterval = 10.0
    }

    /// Launch window duration before resolving `.backgroundLaunch`.
    private let threshold: TimeInterval
    /// Buffer of commands received while the launch reason is unresolved.
    private var buffer: [(command: RUMCommand, context: DatadogContext, writer: Writer)] = []
    /// Resolved launch reason, updated once a conclusive condition is met.
    private var resolvedReason: LaunchReason?

    /// Initializes the resolver with a custom or default threshold.
    ///
    /// - Parameter launchWindowThreshold: Time window in seconds before resolving as background launch.
    init(launchWindowThreshold: TimeInterval = Constants.launchWindowThreshold) {
        self.threshold = launchWindowThreshold
    }

    /// Defers processing of a RUM command until `launchReason` is resolved.
    ///
    /// If the `launchReason` is known - either already set in the `context` or already resolved internally - the command
    /// is immediately passed to `onReady` with the resolved reason injected into its `DatadogContext`.
    ///
    /// If the reason is still `.uncertain`, the command is buffered and forwarded later when resolution occurs.
    /// All buffered commands are flushed in FIFO order with the resolved reason once available.
    ///
    /// - Parameters:
    ///   - command: Incoming RUM command to buffer or forward.
    ///   - context: The associated `DatadogContext` (typically with `launchReason = .uncertain`).
    ///   - writer: The writer to be used when the command is ready.
    ///   - onReady: Callback called once per command, with the resolved launch reason injected into context.
    func deferUntilLaunchReasonResolved(
        command: RUMCommand,
        context: DatadogContext,
        writer: Writer,
        onReady: (RUMCommand, DatadogContext, Writer) -> Void
    ) {
        // If the launch reason was already resolved externally (e.g., via iOS `task_role` or prewarm flag),
        // forward the command immediately. This is a defensive check — callers should avoid deferring resolution
        // when the reason is already known.
        guard context.launchInfo.launchReason == .uncertain else {
            onReady(command, context, writer)
            return
        }

        // If already resolved internally, inject and forward immediately:
        if let resolvedReason {
            onReady(command, context.replacing(launchReason: resolvedReason), writer)
            return
        }

        // Otherwise, buffer the command for deferred resolution.
        buffer.append((command, context, writer))

        // Check whether this command leads to launch reason resolution.
        guard let reason = evaluateLaunchReason(command: command, context: context) else {
            return // not yet
        }

        // If resolved, forward all buffered commands in FIFO order,
        // injecting the resolved reason into each context.
        for (bufferedCommand, bufferedContext, bufferedWriter) in buffer {
            let updatedContext = bufferedContext.replacing(launchReason: reason)
            onReady(bufferedCommand, updatedContext, bufferedWriter)
        }

        // Store resolved reason and clear the buffer (no further buffering needed)
        resolvedReason = reason
        buffer.removeAll()
    }

    /// Attempts to resolve the launch reason based on current state, lifecycle events, or elapsed time.
    ///
    /// - Returns: A resolved `LaunchReason`, or `nil` if it remains uncertain.
    private func evaluateLaunchReason(command: RUMCommand, context: DatadogContext) -> LaunchReason? {
        if context.applicationStateHistory.initialState != .background {
            return .userLaunch
        }

        if let lifecycleCommand = command as? RUMHandleAppLifecycleEventCommand,
           lifecycleCommand.event == .willEnterForeground {
            return .userLaunch
        }

        let elapsed = command.time.timeIntervalSince(context.launchInfo.processLaunchDate)
        if elapsed >= threshold {
            return .backgroundLaunch
        }

        return nil
    }
}

private extension DatadogContext {
    /// Returns a copy of this context with the updated `launchReason`.
    func replacing(launchReason: LaunchReason) -> DatadogContext {
        var copy = self
        copy.launchInfo.launchReason = launchReason
        return copy
    }
}
