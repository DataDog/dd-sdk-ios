/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal
import UIKit

/// A wrapper class for Objective-C compatibility, providing overrides for Session Replay privacy settings.
@objc
public final class DDSessionReplayOverride: NSObject {
    /// Internal Swift equivalent of the Session Replay Override, tied to the view.
    internal var _swift: SessionReplayOverrideExtension<UIView>

    @objc
    override public init() {
        _swift = SessionReplayOverrideExtension(UIView())
        super.init()
    }

    /// Text and input privacy override (e.g., mask or unmask specific text fields, labels, etc.).
    @objc public var textAndInputPrivacy: DDTextAndInputPrivacyLevelOverride {
       get { return .init(_swift.textAndInputPrivacy) }
       set { _swift.textAndInputPrivacy = newValue._swift }
   }

    /// Image privacy override (e.g., mask or unmask specific images).
    @objc public var imagePrivacy: DDImagePrivacyLevelOverride {
        get { return .init(_swift.imagePrivacy) }
        set { _swift.imagePrivacy = newValue._swift }
    }

    /// Touch privacy override (e.g., hide or show touch interactions on specific views).
    @objc public var touchPrivacy: DDTouchPrivacyLevelOverride {
        get { return .init(_swift.touchPrivacy) }
        set { _swift.touchPrivacy = newValue._swift }
    }

    /// Hidden privacy override (e.g., mark a view as hidden, rendering it as an opaque wireframe in replays).
    @objc public var hiddenPrivacy: DDHiddenPrivacyLevelOverride {
        get { return .init(_swift.hiddenPrivacy) }
        set { _swift.hiddenPrivacy = newValue._swift }
    }
}

/// Text and input privacy override (e.g., mask or unmask specific text fields, labels, etc.).
@objc
public enum DDTextAndInputPrivacyLevelOverride: Int {
    case none  // Represents `nil` in Swift
    case maskSensitiveInputs
    case maskAllInputs
    case maskAll

    internal var _swift: TextAndInputPrivacyLevel? {
        switch self {
        case .none: return nil
        case .maskSensitiveInputs: return .maskSensitiveInputs
        case .maskAllInputs: return .maskAllInputs
        case .maskAll: return .maskAll
        }
    }

    internal init(_ swift: TextAndInputPrivacyLevel?) {
        switch swift {
        case .maskSensitiveInputs: self = .maskSensitiveInputs
        case .maskAllInputs: self = .maskAllInputs
        case .maskAll: self = .maskAll
        case nil: self = .none
        }
    }
}

/// Image privacy override (e.g., mask or unmask specific images).
@objc
public enum DDImagePrivacyLevelOverride: Int {
    case none  // Represents `nil` in Swift
    case maskNone
    case maskNonBundledOnly
    case maskAll

    internal var _swift: ImagePrivacyLevel? {
        switch self {
        case .none: return nil
        case .maskNone: return .maskNone
        case .maskNonBundledOnly: return .maskNonBundledOnly
        case .maskAll: return .maskAll
        }
    }

    internal init(_ swift: ImagePrivacyLevel?) {
        switch swift {
        case .maskNone: self = .maskNone
        case .maskNonBundledOnly: self = .maskNonBundledOnly
        case .maskAll: self = .maskAll
        case nil: self = .none
        }
    }
}

/// Touch privacy override (e.g., hide or show touch interactions on specific views).
@objc
public enum DDTouchPrivacyLevelOverride: Int {
    case none  // Represents `nil` in Swift
    case show
    case hide

    internal var _swift: TouchPrivacyLevel? {
        switch self {
        case .none: return nil
        case .show: return .show
        case .hide: return .hide
        }
    }

    internal init(_ swift: TouchPrivacyLevel?) {
        switch swift {
        case .show: self = .show
        case .hide: self = .hide
        case nil: self = .none
        }
    }
}

/// Hidden privacy override (e.g., mark a view as hidden, rendering it as an opaque wireframe in replays).
@objc
public enum DDHiddenPrivacyLevelOverride: Int {
    case none  // Represents `nil` in Swift
    case hide

    internal var _swift: HiddenPrivacyLevel? {
        switch self {
        case .none: return nil
        case .hide: return .hide
        }
    }

    internal init(_ swift: HiddenPrivacyLevel?) {
        if let swift = swift {
            self = (swift == .hide) ? .hide : .none
        } else {
            self = .none
        }
    }
}
#endif
