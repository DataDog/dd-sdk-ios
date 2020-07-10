/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public class RUMMonitor {
    private let rumApplicationID: String

    public init(rumApplicationID: String) {
        self.rumApplicationID = rumApplicationID
    }

    /// TODO: RUMM-585 Replace with real RUMMonitor public API
    public func sendFakeViewEvent(viewURL: String) {
        let event = RUMViewEvent(
            date: Date(timeIntervalSinceNow: -1).timeIntervalSince1970.toMilliseconds,
            application: .init(id: rumApplicationID),
            session: .init(id: UUID().uuidString.lowercased(), type: "user"),
            view: .init(
                id: UUID().uuidString.lowercased(),
                url: viewURL,
                timeSpent: TimeInterval(0.5).toNanoseconds,
                action: .init(count: 0),
                error: .init(count: 0),
                resource: .init(count: 0)
            ),
            dd: .init(documentVersion: 1)
        )

        RUMFeature.instance?.storage.writer.write(value: event)
    }
}
