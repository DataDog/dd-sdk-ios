/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Defines types that are dispatched by RUM on the message-bus.
public enum RUMDispatchMessages {
    /// The key references a `true` value if the RUM view is reset.
    public static let viewReset = "rum-view-reset"
}
