/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Available privacy levels for text and input masking in Session Replay.
public enum TextAndInputPrivacyLevel: String, CaseIterable {
    /// Show all texts except sensitive inputs, eg. password fields.
    case maskSensitiveInputs = "mask_sensitive_inputs"

    /// Mask all inputs fields, eg. textfields, switches, checkboxes.
    case maskAllInputs = "mask_all_inputs"

    /// Mask all texts and inputs, eg. labels.
    case maskAll = "mask_all"
}
#endif
