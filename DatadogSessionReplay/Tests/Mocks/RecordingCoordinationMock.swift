/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay
import Datadog
import TestUtilities

final class RecordingCoordinationMock: RecordingCoordination {
    var currentRUMContext: RUMContext?

    var shouldRecord: Bool

    internal init(currentRUMContext: RUMContext?, shouldRecord: Bool = true) {
        self.currentRUMContext = currentRUMContext
        self.shouldRecord = shouldRecord
    }
}
