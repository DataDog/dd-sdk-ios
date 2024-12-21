/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal
import UIKit

/// Defines operations used for reporting memory warnings.
internal protocol MemoryWarningReporting: RUMCommandPublisher {
    /// Reports the given memory warning.
    /// - Parameter warning: The memory warning to report.
    func report(warning: MemoryWarning)
}

/// Receives memory warnings and reports them as RUM errors.
internal class MemoryWarningReporter: MemoryWarningReporting {
    enum Constants {
        /// The standardized `error.message` for RUM errors describing a memory warning.
        static let memoryWarningErrorMessage = "Memory Warning"
        /// The standardized `error.type` for RUM errors describing a memory warning.
        static let memoryWarningErrorType = "MemoryWarning"
        /// The standardized `error.stack` when backtrace generation was not available.
        static let memoryWarningStackNotAvailableErrorMessage = "Stack trace was not generated because `DatadogCrashReporting` had not been enabled."
    }

    private(set) weak var subscriber: RUMCommandSubscriber?

    /// Reports the given memory warning as a RUM error.
    /// - Parameter warning: The memory warning to report.
    func report(warning: MemoryWarning) {
        let command = RUMAddCurrentViewMemoryWarningCommand(
            time: warning.date,
            globalAttributes: [:],
            attributes: [:],
            message: Constants.memoryWarningErrorMessage,
            type: Constants.memoryWarningErrorType,
            stack: warning.backtrace?.stack ?? Constants.memoryWarningStackNotAvailableErrorMessage,
            threads: warning.backtrace?.threads,
            binaryImages: warning.backtrace?.binaryImages,
            isStackTraceTruncated: warning.backtrace?.wasTruncated
        )
        subscriber?.process(command: command)
    }

    func publish(to subscriber: any RUMCommandSubscriber) {
        self.subscriber = subscriber
    }
}
