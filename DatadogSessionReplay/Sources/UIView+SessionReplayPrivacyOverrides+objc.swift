//
//  SessionReplayPrivacyOverridesExtension+objc.swift
//  DatadogSessionReplay iOS
//
//  Created by Marie Denis on 10/10/2024.
//  Copyright © 2024 Datadog. All rights reserved.
//

#if os(iOS)
import UIKit

private var associatedSROverrideKey: UInt8 = 0

// MARK: UIView extension
/// Objective-C accessible extension for UIView
@objc
@_spi(objc)
public extension UIView {
    @objc var ddSessionReplayPrivacyOverrides: objc_SessionReplayPrivacyOverrides {
        return objc_SessionReplayPrivacyOverrides(view: self)
    }
}

// MARK: DDSessionReplayPrivacyOverrides
/// A wrapper class for Objective-C compatibility, providing overrides for Session Replay privacy settings.
@objc(DDSessionReplayPrivacyOverrides)
@objcMembers
@_spi(objc)
public final class objc_SessionReplayPrivacyOverrides: NSObject {
    /// Internal Swift equivalent of the Session Replay Override, tied to the view.
    internal var _swift: PrivacyOverrides

    @objc
    public init(view: UIView) {
        _swift = PrivacyOverrides(view)
        super.init()
    }

    /// Text and input privacy override (e.g., mask or unmask specific text fields, labels, etc.).
    @objc public var textAndInputPrivacy: objc_TextAndInputPrivacyLevelOverride {
        get { return objc_TextAndInputPrivacyLevelOverride(_swift.textAndInputPrivacy) }
        set { _swift.textAndInputPrivacy = newValue._swift }
    }

    /// Image privacy override (e.g., mask or unmask specific images).
    @objc public var imagePrivacy: objc_ImagePrivacyLevelOverride {
        get { return objc_ImagePrivacyLevelOverride(_swift.imagePrivacy) }
        set { _swift.imagePrivacy = newValue._swift }
    }

    /// Touch privacy override (e.g., hide or show touch interactions on specific views).
    @objc public var touchPrivacy: objc_TouchPrivacyLevelOverride {
        get { return objc_TouchPrivacyLevelOverride(_swift.touchPrivacy) }
        set { _swift.touchPrivacy = newValue._swift }
    }

    /// Hidden privacy override (e.g., mark a view as hidden, rendering it as an opaque wireframe in replays).
    @objc public var hide: NSNumber? {
        get {
            guard let hide = _swift.hide else {
                return nil
            }
            return NSNumber(value: hide)
        }
        set {
            _swift.hide = newValue?.boolValue
        }
    }
}

#endif
