/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import Foundation

struct TimeseriesEncoder {
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func encode(_ event: TimeseriesEvent) throws -> Data {
        try encoder.encode(event)
    }
}
