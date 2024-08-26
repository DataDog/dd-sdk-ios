/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
/// Available privacy levels for touch masking in Session Replay.
public enum TouchPrivacyLevel: String {
    /// Show all user touches.
    case show

    /// Hide all user touches.
    case hide
}
#endif
