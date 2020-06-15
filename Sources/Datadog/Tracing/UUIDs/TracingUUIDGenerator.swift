/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol TracingUUIDGenerator {
    func generateUnique() -> TracingUUID
}

internal struct DefaultTracingUUIDGenerator: TracingUUIDGenerator {
    func generateUnique() -> TracingUUID {
       // TODO: RUMM-333 Add boundaries to trace & span ID generation, keeping in mind that `0` is reserved (ref: DDTracer.java#L600)
       // NOTE: RUMM-340 Consider thread safety if the generation will depend on local state
       return TracingUUID(rawValue: .random(in: 1...UInt64.max))
   }
}
