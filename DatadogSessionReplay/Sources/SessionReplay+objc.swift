/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS)

/// An entry point to Datadog Session Replay feature.
@objc
public final class DDSessionReplay: NSObject {
    override private init() { }

    /// Enables Datadog Session Replay feature.
    ///
    /// Recording will start automatically after enabling Session Replay.
    ///
    /// Note: Session Replay requires the RUM feature to be enabled.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    @objc
    public static func enable(with configuration: DDSessionReplayConfiguration) {
        SessionReplay.enable(with: configuration._swift)
    }
}

/// Session Replay feature configuration.
@objc
public final class DDSessionReplayConfiguration: NSObject {
    internal var _swift: SessionReplay.Configuration = .init(replaySampleRate: 0)

    /// The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    ///
    /// It must be a number between 0.0 and 100.0, where 0 means no replays will be recorded
    /// and 100 means all RUM sessions will contain replay.
    ///
    /// Note: This sample rate is applied in addition to the RUM sample rate. For example, if RUM uses a sample rate of 80%
    /// and Session Replay uses a sample rate of 20%, it means that out of all user sessions, 80% will be included in RUM,
    /// and within those sessions, only 20% will have replays.
    @objc public var replaySampleRate: Float {
        set { _swift.replaySampleRate = newValue }
        get { _swift.replaySampleRate }
    }

    /// Defines the way sensitive content (e.g. text) should be masked.
    ///
    /// Default: `.mask`.
    @objc public var defaultPrivacyLevel: DDSessionReplayConfigurationPrivacyLevel {
        set { _swift.defaultPrivacyLevel = newValue._swift }
        get { .init(_swift.defaultPrivacyLevel) }
    }

    /// Defines the way texts and inputs (e.g. labels, textfields, checkboxes) should be masked.
    ///
    /// Default: `.maskAll`.
    @objc public var textAndInputPrivacyLevel: DDSessionReplayConfigurationTextAndInputPrivacyLevel {
        set { _swift.textAndInputPrivacyLevel = newValue._swift }
        get { .init(_swift.textAndInputPrivacyLevel) }
    }

    /// Defines the way images should be masked.
    ///
    /// Default: `.maskAll`.
    @objc public var imagePrivacyLevel: DDImagePrivacyLevel {
        set { _swift.imagePrivacyLevel = newValue._swift }
        get { .init(_swift.imagePrivacyLevel) }
    }

    /// Defines the way user touches (e.g. tap) should be masked.
    ///
    /// Default: `.mask`.
    @objc public var touchPrivacyLevel: DDTouchPrivacyLevel {
        set { _swift.touchPrivacyLevel = newValue._swift }
        get { .init(_swift.touchPrivacyLevel) }
    }

    /// Custom server url for sending replay data.
    ///
    /// Default: `nil`.
    @objc public var customEndpoint: URL? {
        set { _swift.customEndpoint = newValue }
        get { _swift.customEndpoint }
    }

    /// Creates Session Replay configuration.
    ///
    /// - Parameters:
    ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    ///   - textAndInputPrivacyLevel: The way texts and inputs (e.g. label, textfield, checkbox) should be masked. Default: `.maskAll`.
    ///   - imagePrivacyLevel: Image recording privacy level. Default: `.maskAll`.
    ///   - touchPrivacyLevel: The way user touches (e.g. tap) should be masked. Default: `.hide`.
    @objc
    public required init(
        replaySampleRate: Float,
        textAndInputPrivacyLevel: DDSessionReplayConfigurationTextAndInputPrivacyLevel,
        imagePrivacyLevel: DDImagePrivacyLevel,
        touchPrivacyLevel: DDTouchPrivacyLevel
    ) {
        _swift = SessionReplay.Configuration(
            replaySampleRate: replaySampleRate,
            textAndInputPrivacyLevel: textAndInputPrivacyLevel._swift,
            imagePrivacyLevel: imagePrivacyLevel._swift,
            touchPrivacyLevel: touchPrivacyLevel._swift
        )
        super.init()
    }

    // TODO: RUM-5764 Deprecate former API
    /// Creates Session Replay configuration.
    ///
    /// - Parameters:
    ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    @objc
    public required init(
        replaySampleRate: Float
    ) {
        _swift = SessionReplay.Configuration(
            replaySampleRate: replaySampleRate
        )
        super.init()
    }
}

/// Available privacy levels for content masking.
@objc
public enum DDSessionReplayConfigurationPrivacyLevel: Int {
    /// Record all content.
    case allow

    /// Mask all content.
    case mask

    /// Mask input elements, but record all other content.
    case maskUserInput

    internal var _swift: SessionReplayPrivacyLevel {
        switch self {
        case .allow: return .allow
        case .mask: return .mask
        case .maskUserInput: return .maskUserInput
        default: return .mask
        }
    }

    internal init(_ swift: SessionReplayPrivacyLevel) {
        switch swift {
        case .allow: self = .allow
        case .mask: self = .mask
        case .maskUserInput: self = .maskUserInput
        }
    }
}

/// Available privacy levels for text and input masking.
@objc
public enum DDSessionReplayConfigurationTextAndInputPrivacyLevel: Int {
    /// Show all text except sensitive input (eg. password fields).
    case maskSensitiveInputs

    /// Mask all text and input, eg. textfields, switches, checkboxes.
    case maskAllInputs

    /// Mask all text and input.
    case maskAll

    internal var _swift: SessionReplayTextAndInputPrivacyLevel {
        switch self {
        case .maskSensitiveInputs: return .maskSensitiveInputs
        case .maskAllInputs: return .maskAllInputs
        case .maskAll: return .maskAll
        default: return .maskAll
        }
    }

    internal init(_ swift: SessionReplayTextAndInputPrivacyLevel) {
        switch swift {
        case .maskSensitiveInputs: self = .maskSensitiveInputs
        case .maskAllInputs: self = .maskAllInputs
        case .maskAll: self = .maskAll
        }
    }
}

/// Available image privacy levels for image masking.
@objc
public enum DDImagePrivacyLevel: Int {
    /// Only SF Symbols and images loaded using UIImage(named:) that are bundled within the application package will be recorded.
    case maskNonBundledOnly
    /// No images will be recorded.
    case maskAll
    /// All images including the ones downloaded from the Internet during the app runtime will be recorded.
    case maskNone

    internal var _swift: ImagePrivacyLevel {
        switch self {
        case .maskNonBundledOnly: return .maskNonBundledOnly
        case .maskAll: return .maskAll
        case .maskNone: return .maskNone
        }
    }

    internal init(_ swift: ImagePrivacyLevel) {
        switch swift {
        case .maskNonBundledOnly: self = .maskNonBundledOnly
        case .maskAll: self = .maskAll
        case .maskNone: self = .maskNone
        }
    }
}

/// Available privacy levels for content masking.
@objc
public enum DDTouchPrivacyLevel: Int {
    /// Show all touches.
    case show

    /// Hide all touches.
    case hide

    internal var _swift: TouchPrivacyLevel {
        switch self {
        case .show: return .show
        case .hide: return .hide
        default: return .hide
        }
    }

    internal init(_ swift: TouchPrivacyLevel) {
        switch swift {
        case .show: self = .show
        case .hide: self = .hide
        }
    }
}

#endif
