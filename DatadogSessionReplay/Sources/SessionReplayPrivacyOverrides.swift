/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

// MARK: - DatadogExtension for UIView

/// Extension to provide access to `SessionReplayPrivacyOverrides` for any `UIView`.
extension DatadogExtension where ExtendedType: UIView {
    /// Provides access to Session Replay override settings for the view.
    /// Usage: `myView.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = .maskNone`.
    public var sessionReplayPrivacyOverrides: SessionReplayPrivacyOverrides {
        return SessionReplayPrivacyOverrides(self.type)
    }
}

// MARK: - Associated Keys

private var associatedTextAndInputPrivacyKey: UInt8 = 3
private var associatedImagePrivacyKey: UInt8 = 4
private var associatedTouchPrivacyKey: UInt8 = 5
private var associatedHiddenPrivacyKey: UInt8 = 6

// MARK: - SessionReplayPrivacyOverrides

/// `UIView` extension  to manage the Session Replay privacy override settings.
public final class SessionReplayPrivacyOverrides {
    internal let view: UIView

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

// MARK: - Equatable
extension PrivacyOverrides: Equatable {
    public static func == (lhs: SessionReplayPrivacyOverrides, rhs: SessionReplayPrivacyOverrides) -> Bool {
        return lhs.view === rhs.view
        && lhs.textAndInputPrivacy == rhs.textAndInputPrivacy
        && lhs.imagePrivacy == rhs.imagePrivacy
        && lhs.touchPrivacy == rhs.touchPrivacy
        && lhs.hide == rhs.hide
    }
}

// MARK: - Merge
extension PrivacyOverrides {
    /// Merges child and parent overrides, giving precedence to the child’s overrides, if set.
    /// If the child has no overrides set, it inherits its parent’s overrides.
    internal static func merge(_ child: PrivacyOverrides, with parent: PrivacyOverrides) -> PrivacyOverrides {
        let merged = child

        // Apply child overrides if present
        merged.textAndInputPrivacy = merged.textAndInputPrivacy ?? parent.textAndInputPrivacy
        merged.imagePrivacy = merged.imagePrivacy ?? parent.imagePrivacy
        merged.touchPrivacy = merged.touchPrivacy ?? parent.touchPrivacy
        /// `hide` is a boolean, so we explicitly check if either the parent or the child has it set to `true`.
        ///  `false` and `nil` behave the same way, it deactivates the `hide` override.
        /// In practice, this check should not hit, as parent views with `hide = true` should ignore their children.
        if merged.hide == true || parent.hide == true {
            merged.hide = true
        }

        return merged
    }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias PrivacyOverrides = SessionReplayPrivacyOverrides
#endif
