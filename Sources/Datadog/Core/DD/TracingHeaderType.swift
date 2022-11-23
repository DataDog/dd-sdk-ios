/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The type of the telemetry tracing header injected to requests.
public enum TracingHeaderType {
    case openTracing
    case openTelemetry
}
