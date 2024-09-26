/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

// MARK: - DatadogExtension for UIView

/// Extension on `DatadogExtension` to provide access to `SessionReplayOverride` for any `UIView`.
extension DatadogExtension where ExtendedType: UIView {
    /// Provides access to Session Replay override settings for the view.
    /// Usage: `myView.dd.sessionReplayOverride.textAndInputPrivacy = .maskNone`.
    public var sessionReplayOverride: SessionReplayOverrideExtension {
        return SessionReplayOverrideExtension(self.type)
    }
}

// MARK: - Associated Keys

private var associatedTextAndInputPrivacyKey: UInt8 = 3
private var associatedImagePrivacyKey: UInt8 = 4
private var associatedTouchPrivacyKey: UInt8 = 5
private var associatedHiddenPrivacyKey: UInt8 = 6

// MARK: - SessionReplayOverrideExtension

/// `UIView` extension  to manage the Session Replay privacy override settings.
public final class SessionReplayOverrideExtension {
    private let view: UIView

    public init(_ view: UIView) {
        self.view = view
    }

    /// Text and input privacy override (e.g., mask or unmask specific text fields, labels, etc.).
    public var textAndInputPrivacy: TextAndInputPrivacyLevel? {
        get {
            return objc_getAssociatedObject(view, &associatedTextAndInputPrivacyKey) as? TextAndInputPrivacyLevel
        }
        set {
            objc_setAssociatedObject(view, &associatedTextAndInputPrivacyKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    /// Image privacy override (e.g., mask or unmask specific images).
    public var imagePrivacy: ImagePrivacyLevel? {
        get {
            return objc_getAssociatedObject(view, &associatedImagePrivacyKey) as? ImagePrivacyLevel
        }
        set {
            objc_setAssociatedObject(view, &associatedImagePrivacyKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    /// Touch privacy override (e.g., hide or show touch interactions on specific views).
    public var touchPrivacy: TouchPrivacyLevel? {
        get {
            return objc_getAssociatedObject(view, &associatedTouchPrivacyKey) as? TouchPrivacyLevel
        }
        set {
            objc_setAssociatedObject(view, &associatedTouchPrivacyKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    /// Hidden privacy override (e.g., mark a view as hidden, rendering it as an opaque wireframe in replays).
    public var hide: Bool? {
        get {
            return objc_getAssociatedObject(view, &associatedHiddenPrivacyKey) as? Bool
        }
        set {
            objc_setAssociatedObject(view, &associatedHiddenPrivacyKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
}

extension SessionReplayOverrideExtension: Equatable {
    public static func == (lhs: SessionReplayOverrideExtension, rhs: SessionReplayOverrideExtension) -> Bool {
        return lhs.view === rhs.view
        && lhs.textAndInputPrivacy == rhs.textAndInputPrivacy
        && lhs.imagePrivacy == rhs.imagePrivacy
        && lhs.touchPrivacy == rhs.touchPrivacy
        && lhs.hide == rhs.hide
    }
}
#endif
