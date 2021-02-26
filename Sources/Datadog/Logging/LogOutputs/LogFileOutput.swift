/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `LogOutput` writing logs to file.
internal struct LogFileOutput: LogOutput {
    let fileWriter: Writer
    /// Integration with RUM Errors.
    let rumErrorsIntegration: LoggingWithRUMErrorsIntegration?

    func write(log: Log) {
        fileWriter.write(value: log)

        if log.status == .error || log.status == .critical {
            rumErrorsIntegration?.addError(for: log)
        }
    }
}
