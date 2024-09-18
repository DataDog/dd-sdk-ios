//
//  PrivacyLevel+SessionReplay.swift
//  DatadogSessionReplay iOS
//
//  Created by Marie Denis on 16/09/2024.
//  Copyright © 2024 Datadog. All rights reserved.
//

#if os(iOS)
import Foundation
import UIKit
import DatadogInternal
import ObjectiveC

private var associatedSessionReplayOverrideKey: UInt8 = 3

/// Extension for `UIView` to add the ability to override Session Replay privacy settings.
extension DatadogExtension where ExtendedType: UIView {
    /// Provides access to privacy overrides for the current view.
    /// This allows setting specific privacy levels for text & input, image, and touch masking, as well as hiding the view.
    /// Usage: `myView.dd.sessionReplayOverride.textAndInputPrivacy = .maskNone`
    public var sessionReplayOverride: SessionReplayOverride {
        get {
            if let override = objc_getAssociatedObject(self, &associatedSessionReplayOverrideKey) as? SessionReplayOverride {
                return override
            } else {
                return SessionReplayOverride()
            }
        }
        set {
            objc_setAssociatedObject(self, &associatedSessionReplayOverrideKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

/// Structure encapsulating all privacy levels that can be overridden at the view level.
public struct SessionReplayOverride {
    /// Privacy levels for masking within the view.
    /// For each property, if `nil`, the global privacy configuration is applied.
    public var textAndInputPrivacy: TextAndInputPrivacyLevel?
    public var imagePrivacy: ImagePrivacyLevel?
    public var touchPrivacy: TouchPrivacyLevel?
    public var hiddenPrivacy: HiddenPrivacyLevel?

    public init(
        textAndInputPrivacy: TextAndInputPrivacyLevel? = nil,
        imagePrivacy: ImagePrivacyLevel? = nil,
        touchPrivacy: TouchPrivacyLevel? = nil,
        hiddenPrivacy: HiddenPrivacyLevel? = nil
    ) {
        self.textAndInputPrivacy = textAndInputPrivacy
        self.imagePrivacy = imagePrivacy
        self.touchPrivacy = touchPrivacy
        self.hiddenPrivacy = hiddenPrivacy
    }
}
#endif
