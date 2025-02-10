/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

// MARK: - Associated Keys

internal var associatedOverridesKey: UInt8 = 3

// MARK: - DatadogExtension for UIView

/// Extension to provide access to `SessionReplayPrivacyOverrides` for any `UIView`.
extension DatadogExtension where ExtendedType: UIView {
    /// Provides access to Session Replay override settings for the view.
    /// Usage: `myView.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = .maskNone`.
    public var sessionReplayPrivacyOverrides: SessionReplayPrivacyOverrides {
        if let overrides = _privacyOverrides {
            return overrides
        }

        let overrides = SessionReplayPrivacyOverrides()
        objc_setAssociatedObject(type, &associatedOverridesKey, overrides, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return overrides
    }

    /// Internal accessor
    internal var _privacyOverrides: SessionReplayPrivacyOverrides? {
        objc_getAssociatedObject(type, &associatedOverridesKey) as? SessionReplayPrivacyOverrides
    }
}

// MARK: - SessionReplayPrivacyOverrides

/// `UIView` extension  to manage the Session Replay privacy override settings.
public final class SessionReplayPrivacyOverrides {
    /// Text and input privacy override (e.g., mask or unmask specific text fields, labels, etc.).
    public var textAndInputPrivacy: TextAndInputPrivacyLevel?
    /// Image privacy override (e.g., mask or unmask specific images).
    public var imagePrivacy: ImagePrivacyLevel?
    /// Touch privacy override (e.g., hide or show touch interactions on specific views).
    public var touchPrivacy: TouchPrivacyLevel?
    /// Hidden privacy override (e.g., mark a view as hidden, rendering it as an opaque wireframe in replays).
    public var hide: Bool?

    /// Creates a new instance of privacy overrides.
    internal init() {
        // Initialize with all properties as nil
    }
}

// MARK: - Equatable

extension PrivacyOverrides: Equatable {
    public static func == (lhs: SessionReplayPrivacyOverrides, rhs: SessionReplayPrivacyOverrides) -> Bool {
        return lhs.textAndInputPrivacy == rhs.textAndInputPrivacy
        && lhs.imagePrivacy == rhs.imagePrivacy
        && lhs.touchPrivacy == rhs.touchPrivacy
        && lhs.hide == rhs.hide
    }
}

// MARK: - Merge

extension PrivacyOverrides {
    /// Merges child and parent overrides, giving precedence to the child’s overrides, if set.
    /// If the child has no overrides set, it inherits its parent’s overrides.
    internal static func merge(_ child: PrivacyOverrides?, with parent: PrivacyOverrides?) -> PrivacyOverrides? {
        guard let child = child else {
            return parent
        }
        guard let parent = parent else {
            return child
        }

        // Apply parent overrides where child has none set
        child.textAndInputPrivacy = child.textAndInputPrivacy ?? parent.textAndInputPrivacy
        child.imagePrivacy = child.imagePrivacy ?? parent.imagePrivacy
        child.touchPrivacy = child.touchPrivacy ?? parent.touchPrivacy

        /// `hide` is a boolean, so we explicitly check if either the parent or the child has it set to `true`.
        /// `false` and `nil` behave the same way, it deactivates the `hide` override.
        /// In practice, this check should not hit, as parent views with `hide = true` should ignore their children.
        if child.hide == true || parent.hide == true {
            child.hide = true
        }

        return child
    }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias PrivacyOverrides = SessionReplayPrivacyOverrides
#endif
