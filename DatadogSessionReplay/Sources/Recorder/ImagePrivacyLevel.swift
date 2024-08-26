/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Available privacy levels for image masking in the Session Replay.
public enum ImagePrivacyLevel: String {
    /// Only SF Symbols and images loaded using UIImage(named:) that are bundled within the application will be recorded.
    case maskNonBundledOnly = "mask_non_bundled_only"

    /// No images will be recorded.
    case maskAll = "mask_all"

    /// All images including the ones downloaded from the Internet or genereated during the app runtime will be recorded.
    case maskNone = "mask_none"
}
#endif
