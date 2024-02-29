/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct Meter {
    let name: String
    let type: SubmissionType
    let interval: Int64?
    let unit: String?
    let resources: [Serie.Resource]
    let tags: [String]

    weak var core: DatadogCoreProtocol?

    /// record a metric value.
    ///
    /// - Parameter value: The metric value
    func record(_ value: Double) {
        let timestamp = Date()
        core?.scope(for: MetricFeature.name)?.eventWriteContext { context, writer in
            let submission = Submission(
                metadata: Submission.Metadata(
                    name: "\(context.source).\(context.applicationBundleIdentifier).\(self.name)",
                    type: self.type,
                    interval: self.interval,
                    unit: self.unit,
                    resources: self.resources,
                    tags: self.tags + [
                        "service:\(context.service)",
                        "env:\(context.env)",
                        "version:\(context.version)",
                        "build_number:\(context.buildNumber)",
                        "source:\(context.source)",
                        "application_name:\(context.applicationName)",
                    ]
                ),
                point: Serie.Point(
                    timestamp: Int64(withNoOverflow: timestamp.timeIntervalSince1970),
                    value: value
                )
            )

            writer.write(value: submission)
        }
    }
}
