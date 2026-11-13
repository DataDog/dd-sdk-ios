/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Disables and enables sudden termination of the app.
///
/// On macOS, AppKit can kill an app that supports sudden termination (`NSSupportsSuddenTermination`) without
/// notifying it. The SDK disables sudden termination while it holds data that is not written to storage yet, so
/// that the app terminates normally and the SDK can write that data on `NSApplication.willTerminateNotification`.
///
/// Calls are counted: sudden termination is enabled again once every `disableSuddenTermination()` is balanced
/// by an `enableSuddenTermination()`.
public protocol SuddenTerminationControl {
    func disableSuddenTermination()
    func enableSuddenTermination()
}

extension SuddenTerminationControl {
    /// Runs `work` asynchronously on `queue` and keeps sudden termination disabled until it completes.
    ///
    /// Use it for work that writes to disk, so that the app is not killed while the write is queued or running.
    /// The control is only called on macOS, the only platform with sudden termination.
    public func async(on queue: DispatchQueue, execute work: @escaping () -> Void) {
        #if os(macOS)
        disableSuddenTermination()
        queue.async {
            defer { self.enableSuddenTermination() }
            work()
        }
        #else
        queue.async(execute: work)
        #endif
    }
}

/// Controls sudden termination of the current process. Sudden termination only exists on macOS,
/// so this does nothing on other platforms.
public struct ProcessSuddenTerminationControl: SuddenTerminationControl {
    public init() {}

    public func disableSuddenTermination() {
        #if os(macOS)
        ProcessInfo.processInfo.disableSuddenTermination()
        #endif
    }

    public func enableSuddenTermination() {
        #if os(macOS)
        ProcessInfo.processInfo.enableSuddenTermination()
        #endif
    }
}

/// Keeps sudden termination disabled while a buffer holds data that is not written to storage yet.
///
/// Setting `isHeld` to its current value does nothing, so a buffer can set it after every change.
/// Not thread safe: confine it to the queue that owns the buffer.
public final class SuddenTerminationHold {
    private let control: SuddenTerminationControl

    /// Whether sudden termination is disabled by this hold.
    public var isHeld = false {
        didSet {
            guard isHeld != oldValue else {
                return
            }
            if isHeld {
                control.disableSuddenTermination()
            } else {
                control.enableSuddenTermination()
            }
        }
    }

    public init(control: SuddenTerminationControl) {
        self.control = control
    }

    deinit {
        // The data is lost with its owner, so it can no longer delay termination.
        if isHeld {
            control.enableSuddenTermination()
        }
    }
}
