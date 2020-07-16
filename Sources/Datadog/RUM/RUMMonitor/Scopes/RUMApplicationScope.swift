/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMApplicationScope: RUMScope {
    /// No-op session ID used shortly before the real session is initialized.
    static let nullSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()

    let eventBuilder: RUMEventBuilder // TODO: RUMM-518 move to `RUMMSessionScope`
    let eventOutput: RUMEventOutput // TODO: RUMM-518 move to `RUMMSessionScope`

    init(
        rumApplicationID: String,
        eventBuilder: RUMEventBuilder,
        eventOutput: RUMEventOutput
    ) {
        self.eventBuilder = eventBuilder
        self.eventOutput = eventOutput
        self.context = RUMContext(
            rumApplicationID: rumApplicationID,
            sessionID: RUMApplicationScope.nullSessionID,
            activeViewID: nil,
            activeViewURI: nil,
            activeUserActionID: nil
        )
    }

    // MARK: - RUMScope

    let context: RUMContext

    func process(command: RUMCommand) -> Bool {
        return false
    }
}
