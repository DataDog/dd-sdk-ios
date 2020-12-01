/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

extension JSONEncoder {
    static func `default`() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatted = iso8601DateFormatter.string(from: date)
            try container.encode(formatted)
        }
        if #available(iOS 13.0, OSX 10.15, *) {
            // NOTE: The `.sortedKeys` option was added in RUMM-776 after discovering an issue
            // with backend processing of the RUM View payloads. The custom timings encoding for
            // RUM views requires following structure:
            //
            //  ```
            //  {
            //     view: { /* serialized, auto-generated RUM view event */ },
            //     view.custom_timings.<custom-timing-1-name>: <custom-timing-value>,
            //     view.custom_timings.<custom-timing-2-name>: <custom-timing-value>
            //     ...
            //  }
            //  ```
            //
            // To guarantee proper backend-side processing, the `view.custom_timings` keys must be
            // encoded after the `view` object. Using `.sortedKeys` enforces this order.
            //
            encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        return encoder
    }
}
