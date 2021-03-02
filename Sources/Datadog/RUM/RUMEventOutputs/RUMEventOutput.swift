/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for writing RUM events to some destination.
internal protocol RUMEventOutput {
    func write<DM: RUMDataModel>(rumEvent: RUMEvent<DM>)
}
