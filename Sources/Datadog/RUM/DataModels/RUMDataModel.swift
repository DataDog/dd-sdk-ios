/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A common interface for all auto-generated RUM Events following the
/// [rum-events-format](https://github.com/DataDog/rum-events-format) spec.
internal protocol RUMDataModel: Codable {}
