/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A helper that resolves the app launch reason (`LaunchReason`) for tvOS apps, using a timed window and
/// observed lifecycle events. This is needed because tvOS does not expose kernel-level signals (like `task_role`)
/// that are available on iOS to detect whether an app was launched by the user or in the background.
///
/// It buffers RUM commands along with their corresponding `DatadogContext` and `Writer`. Once the launch reason is resolved
/// (either by receiving a `willEnterForeground` event or exceeding the launch window threshold),
/// it replays all buffered items in FIFO order. The original commands and writers are preserved, but the
/// `launchReason` field in each context is updated with the resolved value before forwarding.
internal final class LaunchReasonResolver {
    private let window: AppLaunchWindow

    init(launchWindowThreshold: TimeInterval) {
        self.window = AppLaunchWindow(launchWindowThreshold: launchWindowThreshold)
    }

    /// Buffers the given command and forwards it once the launch reason is resolved.
    /// If resolution occurs as a result of this command, all previously buffered commands are forwarded in order,
    /// with their `DatadogContext.launchInfo.launchReason` updated to match the resolved reason.
    /// If the context already contains a known `launchReason`, the command is forwarded immediately without modification.
    func forwardWithLaunchReason(
        command: RUMCommand,
        context: DatadogContext,
        writer: Writer,
        forwardingBlock: ([(command: RUMCommand, context: DatadogContext, writer: Writer)]) -> Void
    ) {
        guard context.launchInfo.launchReason == .uncertain else {
            // Unexpected pre-set reason, forward as-is.
            forwardingBlock([(command, context, writer)])
            return
        }

        if window.resolvedReason != .uncertain {
            // Launch reason already resolved, inject and forward immediately.
            let resolvedCommand = (command, context.replacing(launchReason: window.resolvedReason), writer)
            forwardingBlock([resolvedCommand])
        } else {
            // Buffer command and check if this one resolved the launch reason.
            window.buffer(command: command, context: context, writer: writer)

            if window.resolvedReason != .uncertain {
                let resolvedCommands = window
                    .flushBuffer()
                    .map { oldCommand, oldContext, oldWriter in (oldCommand, oldContext.replacing(launchReason: window.resolvedReason), oldWriter) }
                forwardingBlock(resolvedCommands)
            }
        }
    }
}

private extension DatadogContext {
    func replacing(launchReason newLaunchReason: LaunchReason) -> DatadogContext {
        var new = self
        new.launchInfo.launchReason = newLaunchReason
        return new
    }
}

internal final class AppLaunchWindow {
    internal enum Constants {
        /// Default time to wait before classifying as background launch.
        static let launchWindowThreshold: TimeInterval = 10.0
    }

    /// Time to wait before classifying as background launch.
    private let threshold: TimeInterval

    /// Commands buffered during launch window (with original context and writer).
    private var buffer: [(command: RUMCommand, context: DatadogContext, writer: Writer)] = []

    /// Launch reason, resolved once conditions are met.
    private(set) var resolvedReason: LaunchReason = .uncertain

    init(launchWindowThreshold: TimeInterval) {
        self.threshold = launchWindowThreshold
    }

    /// Buffers the command if launch reason is not yet resolved.
    /// Once resolved, this becomes a no-op.
    func buffer(command: RUMCommand, context: DatadogContext, writer: Writer) {
        guard resolvedReason == .uncertain else {
            return
        }

        buffer.append((command, context, writer))

        // Resolve immediately if app did not start in background.
        if context.applicationStateHistory.initialState != .background {
            resolvedReason = .userLaunch
            return
        }

        // Resolve as background if command exceeds launch window.
        let elapsed = command.time.timeIntervalSince(context.launchInfo.processLaunchDate)
        if elapsed >= threshold {
            resolvedReason = .backgroundLaunch
            return
        }

        // Resolve as user launch if lifecycle indicates foreground entry.
        if let lifecycleCommand = command as? RUMHandleAppLifecycleEventCommand,
           lifecycleCommand.event == .willEnterForeground {
            resolvedReason = .userLaunch
        }
    }

    /// Returns and clears all buffered commands in FIFO order.
    func flushBuffer() -> [(RUMCommand, DatadogContext, Writer)] {
        defer { buffer.removeAll() }
        return buffer
    }
}
