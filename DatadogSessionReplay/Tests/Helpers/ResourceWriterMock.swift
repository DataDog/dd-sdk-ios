/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogSessionReplay

class ResourceWriterMock: ResourcesWriting {
    var resources: [[EnrichedResource]] = []

    func write(resources: [EnrichedResource]) {
        self.resources.append(resources)
    }
}
