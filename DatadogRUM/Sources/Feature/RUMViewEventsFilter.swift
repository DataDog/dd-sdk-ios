/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct RUMViewEventsFilter {
    let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func filter(events: [Event]) -> [Event] {
        var seen = Set<String>()
        var skipped: [String: [Int64]] = [:]

        // reversed is O(1) and no copy because it is view on the original array
        let filtered: [Event] = events.reversed().compactMap { event in
            guard let metadata = event.metadata else {
                // If there is no metadata, we can't filter it.
                return event
            }

            guard let viewMetadata = try? decoder.decode(RUMViewEvent.Metadata.self, from: metadata) else {
                // If we can't decode the metadata, we can't filter it.
                return event
            }

            guard seen.contains(viewMetadata.id) == false else {
                // If we've already seen this view, we can skip this
                if skipped[viewMetadata.id] == nil {
                    skipped[viewMetadata.id] = []
                }
                skipped[viewMetadata.id]?.append(viewMetadata.documentVersion)
                return nil
            }

            seen.insert(viewMetadata.id)
            return event
        }

        for (id, versions) in skipped {
            DD.logger.debug("Skipping RUMViewEvent with id: \(id) and versions: \(versions.reversed().map(String.init).joined(separator: ", "))")
        }

        return filtered.reversed()
    }
}
