/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct RUMViewEventsFilter {
    /// The initial `time_spent` value (1ns) assigned to a view when it starts. This is a placeholder meant to be updated as events are tracked (eventual consistency).
    /// If the value isn’t updated, the view would report a `1ns` duration, so we filter it out to avoid that (see RUM-10723).
    private let oneNanosecondDuration = RUMViewScope.Constants.minimumTimeSpent.toInt64Nanoseconds

    let decoder: JSONDecoder
    let telemetry: Telemetry

    init(telemetry: Telemetry, decoder: JSONDecoder = JSONDecoder()) {
        self.telemetry = telemetry
        self.decoder = decoder
    }

    private enum FilterResult {
        case keep
        case skipRedundant
        case skipOneNs
    }

    /// Filters RUM view events to improve data quality and optimize payload size by removing:
    /// - Redundant view events (duplicate view IDs)
    /// - 1ns view events that represent failed eventual consistency scenarios
    func filter(events: [Event]) -> [Event] {
        var seen = Set<String>()
        var redundantEventsCount = 0
        var oneNsEventsCount = 0

        // reversed is O(1) and no copy because it is view on the original array
        let filtered: [Event] = events.reversed().compactMap { event in
            do {
                let result = try filterEvent(event, seen: &seen)
                switch result {
                case .keep:
                    return event
                case .skipRedundant:
                    redundantEventsCount += 1
                    return nil
                case .skipOneNs:
                    oneNsEventsCount += 1
                    return nil
                }
            } catch {
                telemetry.error("Failed to decode RUM view event metadata", error: error)
                return event
            }
        }

        if redundantEventsCount > 0 || oneNsEventsCount > 0 {
            DD.logger.debug("RUMViewEventsFilter: skipped \(redundantEventsCount) redundant view updates, \(oneNsEventsCount) 1ns views")
        }

        return filtered.reversed()
    }

    private func filterEvent(_ event: Event, seen: inout Set<String>) throws -> FilterResult {
        guard let metadata = event.metadata else {
            // If there is no metadata, we can't filter it.
            return .keep
        }

        let viewMetadata = try decoder.decode(RUMViewEvent.Metadata.self, from: metadata)

        if let duration = viewMetadata.duration, duration == oneNanosecondDuration {
            // Filter out 1ns views to prevent low-quality 1ns sessions.
            // Views start with a 1ns "placeholder" duration that gets updated as events arrive.
            // When eventual consistency fails (e.g., app crashes immediately or has sparse instrumentation),
            // views keep their 1ns duration, which can create problematic 1ns sessions.
            return .skipOneNs
        }

        guard seen.contains(viewMetadata.id) == false else {
            // If we've already seen an update for this view, we can skip the next one.
            return .skipRedundant
        }

        seen.insert(viewMetadata.id)
        return .keep
    }
}
