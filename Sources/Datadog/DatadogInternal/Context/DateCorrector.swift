/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Calculates the date correction for adjusting device time to server time.
internal protocol DateCorrector {
    /// Returns recent date correction for adjusting device time to server time.
    var offset: TimeInterval { get }
}
