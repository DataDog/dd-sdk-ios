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
    func reportMemoryWarning()
}

/// Receives memory warnings and reports them as RUM errors.
internal class MemoryWarningReporter: MemoryWarningReporting {
    enum Constants {
        /// The standardized `error.message` for RUM errors describing a memory warning.
        static let memoryWarningErrorMessage = "Memory Warning"
        /// The standardized `error.type` for RUM errors describing a memory warning.
        static let memoryWarningErrorType = "MemoryWarning"
    }

    private(set) weak var subscriber: RUMCommandSubscriber?

    /// Reports the given memory warning as a RUM error.
    func reportMemoryWarning() {
        let command = RUMAddCurrentViewMemoryWarningCommand(
            time: Date(),
            globalAttributes: [:],
            attributes: [:],
            message: Constants.memoryWarningErrorMessage,
            type: Constants.memoryWarningErrorType,
            stack: nil,
            threads: nil,
            binaryImages: nil,
            isStackTraceTruncated: nil
        )
        subscriber?.process(command: command)
    }

    func publish(to subscriber: any RUMCommandSubscriber) {
        self.subscriber = subscriber
    }
}
