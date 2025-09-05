/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if os(iOS)

/// An entry point to Datadog Session Replay feature.
@objc(DDSessionReplay)
@objcMembers
@_spi(objc)
public final class objc_SessionReplay: NSObject {
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
    public static func enable(with configuration: objc_SessionReplayConfiguration) {
        SessionReplay.enable(with: configuration._swift)
    }

    /// Starts the recording manually.
    @objc
    public static func startRecording() {
        SessionReplay.startRecording(in: CoreRegistry.default)
    }

    /// Stops the recording manually.
    @objc
    public static func stopRecording() {
        SessionReplay.stopRecording(in: CoreRegistry.default)
    }
}

/// Session Replay feature configuration.
@objc(DDSessionReplayConfiguration)
@objcMembers
@_spi(objc)
public final class objc_SessionReplayConfiguration: NSObject {
    internal var _swift: SessionReplay.Configuration

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

    /// Defines the way texts and inputs (e.g. labels, textfields, checkboxes) should be masked.
    ///
    /// Default: `.maskAll`.
    @objc public var textAndInputPrivacyLevel: objc_TextAndInputPrivacyLevel {
        set { _swift.textAndInputPrivacyLevel = newValue._swift }
        get { .init(_swift.textAndInputPrivacyLevel) }
    }

    /// Defines the way images should be masked.
    ///
    /// Default: `.maskAll`.
    @objc public var imagePrivacyLevel: objc_ImagePrivacyLevel {
        set { _swift.imagePrivacyLevel = newValue._swift }
        get { .init(_swift.imagePrivacyLevel) }
    }

    /// Defines the way user touches (e.g. tap) should be masked.
    ///
    /// Default: `.hide`.
    @objc public var touchPrivacyLevel: objc_TouchPrivacyLevel {
        set { _swift.touchPrivacyLevel = newValue._swift }
        get { .init(_swift.touchPrivacyLevel) }
    }

    /// Defines it the recording should start automatically. When `true`, the recording starts automatically; when `false` it doesn't, and the recording will need to be started manually.
    ///
    /// Default: `true`.
    @objc public var startRecordingImmediately: Bool {
        set { _swift.startRecordingImmediately = newValue }
        get { _swift.startRecordingImmediately }
    }

    /// Custom server url for sending replay data.
    ///
    /// Default: `nil`.
    @objc public var customEndpoint: URL? {
        set { _swift.customEndpoint = newValue }
        get { _swift.customEndpoint }
    }

    /// Feature flags to preview features in Session Replay.
    /// 
    /// Available flags:
    /// - `swiftui`: `false` by default.
    @objc public var featureFlags: [String: Bool] {
        set { _swift.featureFlags = newValue.dd.featureFlags }
        get { _swift.featureFlags.dd.featureFlags }
    }

    /// Creates Session Replay configuration.
    ///
    /// - Parameters:
    ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    ///   - textAndInputPrivacyLevel: The way texts and inputs (e.g. label, textfield, checkbox) should be masked.
    ///   - imagePrivacyLevel: Image recording privacy level.
    ///   - touchPrivacyLevel: The way user touches (e.g. tap) should be masked.
    ///   - featureFlags: Experimental feature flags.
    @objc
    public required init(
        replaySampleRate: Float,
        textAndInputPrivacyLevel: objc_TextAndInputPrivacyLevel,
        imagePrivacyLevel: objc_ImagePrivacyLevel,
        touchPrivacyLevel: objc_TouchPrivacyLevel,
        featureFlags: [String: Bool]?
    ) {
        _swift = SessionReplay.Configuration(
            replaySampleRate: replaySampleRate,
            textAndInputPrivacyLevel: textAndInputPrivacyLevel._swift,
            imagePrivacyLevel: imagePrivacyLevel._swift,
            touchPrivacyLevel: touchPrivacyLevel._swift,
            featureFlags: featureFlags?.dd.featureFlags ?? .defaults
        )
        super.init()
    }

    /// Creates Session Replay configuration.
    ///
    /// - Parameters:
    ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    ///   - textAndInputPrivacyLevel: The way texts and inputs (e.g. label, textfield, checkbox) should be masked.
    ///   - imagePrivacyLevel: Image recording privacy level
    ///   - touchPrivacyLevel: The way user touches (e.g. tap) should be masked.
    @objc
    public convenience init(
        replaySampleRate: Float,
        textAndInputPrivacyLevel: objc_TextAndInputPrivacyLevel,
        imagePrivacyLevel: objc_ImagePrivacyLevel,
        touchPrivacyLevel: objc_TouchPrivacyLevel
    ) {
        self.init(
            replaySampleRate: replaySampleRate,
            textAndInputPrivacyLevel: textAndInputPrivacyLevel,
            imagePrivacyLevel: imagePrivacyLevel,
            touchPrivacyLevel: touchPrivacyLevel,
            featureFlags: nil
        )
    }
}

/// Available privacy levels for text and input masking.
@objc(DDTextAndInputPrivacyLevel)
@_spi(objc)
public enum objc_TextAndInputPrivacyLevel: Int {
    /// Show all text except sensitive input (eg. password fields).
    case maskSensitiveInputs

    /// Mask all text and input, eg. textfields, switches, checkboxes.
    case maskAllInputs

    /// Mask all text and input.
    case maskAll

    internal var _swift: TextAndInputPrivacyLevel {
        switch self {
        case .maskSensitiveInputs: return .maskSensitiveInputs
        case .maskAllInputs: return .maskAllInputs
        case .maskAll: return .maskAll
        }
    }

    internal init(_ swift: TextAndInputPrivacyLevel) {
        switch swift {
        case .maskSensitiveInputs: self = .maskSensitiveInputs
        case .maskAllInputs: self = .maskAllInputs
        case .maskAll: self = .maskAll
        }
    }
}

/// Available image privacy levels for image masking.
@objc(DDImagePrivacyLevel)
@_spi(objc)
public enum objc_ImagePrivacyLevel: Int {
    /// Only SF Symbols and images loaded using UIImage(named:) that are bundled within the application package will be recorded.
    case maskNonBundledOnly
    /// No images will be recorded.
    case maskAll
    /// All images will be recorded, including the ones downloaded from the Internet or generated during the app runtime.
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

/// Available privacy levels for touch masking.
@objc(DDTouchPrivacyLevel)
@_spi(objc)
public enum objc_TouchPrivacyLevel: Int {
    /// Show all touches.
    case show

    /// Hide all touches.
    case hide

    internal var _swift: TouchPrivacyLevel {
        switch self {
        case .show: return .show
        case .hide: return .hide
        }
    }

    internal init(_ swift: TouchPrivacyLevel) {
        switch swift {
        case .show: self = .show
        case .hide: self = .hide
        }
    }
}

private extension DatadogExtension where ExtendedType == [String: Bool] {
    var featureFlags: SessionReplay.Configuration.FeatureFlags {
        type.reduce(into: [:]) { result, element in
            SessionReplay.Configuration.FeatureFlag(rawValue: element.key).map {
                result[$0] = element.value
            }
        }
    }
}

private extension DatadogExtension where ExtendedType == SessionReplay.Configuration.FeatureFlags {
    var featureFlags: [String: Bool] {
        type.reduce(into: [:]) { result, element in
            result[element.key.rawValue] = element.value
        }
    }
}

#endif
