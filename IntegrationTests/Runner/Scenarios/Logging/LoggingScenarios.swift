/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogLogs

/// Scenario which starts a view controller that sends bunch of logs to the server.
final class LoggingManualInstrumentationScenario: TestScenario {
    static let storyboardName = "LoggingManualInstrumentationScenario"

    func configureFeatures() {
        Logs.enable(
            with: Logs.Configuration(
                eventMapper: {
                    var log = $0
                    log.tags?.append("tag3:added")
                    if log.attributes.userAttributes["some-url"] != nil {
                        log.attributes.userAttributes["some-url"] = "redacted"
                    }
                    return log
                },
                customIntakeURL: Environment.serverMockConfiguration()?.logsEndpoint
            )
        )
    }
}
