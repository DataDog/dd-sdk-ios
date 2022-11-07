/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

internal protocol Writing {
    func startWriting(to featureScope: FeatureScope)
    func write(nextRecord: EnrichedRecord)
}

internal class Writer: Writing {
    /// The `FeatureScope` created for Session Replay and managed by `DatadogCore`.
    ///
    /// The thread-safety of this property is guaranteed by convention:
    /// - it is set right after registration of Session Replay Feature in `DatadogCore`,
    /// - it is then frequently accessed from `Processor` thread only after SR is started.
    ///
    /// Because SR is started after SF Feature gets registered, no other thread-safety measures are required.
    private var scope: FeatureScope?

    // MARK: - Writing

    func startWriting(to featureScope: FeatureScope) {
        scope = featureScope
    }

    func write(nextRecord: EnrichedRecord) {
        scope?.eventWriteContext{ _, writer in
            writer.write(value: nextRecord)
        }
    }
}
