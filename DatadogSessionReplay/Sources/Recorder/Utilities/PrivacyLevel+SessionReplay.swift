//
//  PrivacyLevel+SessionReplay.swift
//  DatadogSessionReplay iOS
//
//  Created by Marie Denis on 16/09/2024.
//  Copyright © 2024 Datadog. All rights reserved.
//

#if os(iOS)
import UIKit
import DatadogInternal

// MARK: - DatadogExtension for UIView

/// Extension on `DatadogExtension` to provide access to `SessionReplayOverride` for any `UIView`.
extension DatadogExtension where ExtendedType: UIView {
    /// Provides access to Session Replay override settings for the view.
    /// Usage: `myView.dd.sessionReplayOverride.textAndInputPrivacy = .maskNone`.
    public var sessionReplayOverride: SessionReplayOverrideExtension<ExtendedType> {
        get {
            return SessionReplayOverrideExtension(self.type)
        }
        set {}
    }
}

// MARK: - Associated Keys

private var associatedTextAndInputPrivacyKey: UInt8 = 3
private var associatedImagePrivacyKey: UInt8 = 4
private var associatedTouchPrivacyKey: UInt8 = 5
private var associatedHiddenPrivacyKey: UInt8 = 6

// MARK: - SessionReplayOverrideExtension

/// `UIView` extension  to manage the Session Replay privacy override settings.
public struct SessionReplayOverrideExtension<ExtendedType> {
    private let view: ExtendedType

    public init(_ view: ExtendedType) {
        self.view = view
    }

    /// Text and input privacy override (e.g., mask or unmask specific text fields, labels, etc.).
    public var textAndInputPrivacy: TextAndInputPrivacyLevel? {
        get {
            return objc_getAssociatedObject(view as AnyObject, &associatedTextAndInputPrivacyKey) as? TextAndInputPrivacyLevel
        }
        set {
            objc_setAssociatedObject(view as AnyObject, &associatedTextAndInputPrivacyKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Image privacy override (e.g., mask or unmask specific images).
    public var imagePrivacy: ImagePrivacyLevel? {
        get {
            return objc_getAssociatedObject(view as AnyObject, &associatedImagePrivacyKey) as? ImagePrivacyLevel
        }
        set {
            objc_setAssociatedObject(view as AnyObject, &associatedImagePrivacyKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Touch privacy override (e.g., hide or show touch interactions on specific views).
    public var touchPrivacy: TouchPrivacyLevel? {
        get {
            return objc_getAssociatedObject(view as AnyObject, &associatedTouchPrivacyKey) as? TouchPrivacyLevel
        }
        set {
            objc_setAssociatedObject(view as AnyObject, &associatedTouchPrivacyKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Hidden privacy override (e.g., mark a view as hidden, rendering it as an opaque wireframe in replays).
    public var hiddenPrivacy: HiddenPrivacyLevel? {
        get {
            return objc_getAssociatedObject(view as AnyObject, &associatedHiddenPrivacyKey) as? HiddenPrivacyLevel
        }
        set {
            objc_setAssociatedObject(view as AnyObject, &associatedHiddenPrivacyKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
#endif
