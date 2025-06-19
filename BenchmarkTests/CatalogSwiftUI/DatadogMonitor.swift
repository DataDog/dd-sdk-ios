/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

@frozen public enum TextPrivacyLevel {
    case maskSensitiveInputs
    case maskAllInputs
    case maskAll
}

@frozen public enum ImagePrivacyLevel {
    case maskNonBundledOnly
    case maskAll
    case maskNone
}

@frozen public enum TouchPrivacyLevel {
    case show
    case hide
}

public protocol DatadogMonitor {
    func viewModifier(name: String) -> AnyViewModifier
    func actionModifier(name: String) -> AnyViewModifier
    func privacyOverride(
        text: TextPrivacyLevel?,
        image: ImagePrivacyLevel?,
        touch: TouchPrivacyLevel?,
        hide: Bool?
    ) -> AnyViewModifier
}

struct NOPDatadogMonitor: DatadogMonitor {
    func viewModifier(name: String) -> AnyViewModifier { AnyViewModifier() }
    func actionModifier(name: String) -> AnyViewModifier { AnyViewModifier() }
    func privacyOverride(
        text _: TextPrivacyLevel?,
        image _: ImagePrivacyLevel?,
        touch _: TouchPrivacyLevel?,
        hide _: Bool?
    ) -> AnyViewModifier {
        AnyViewModifier()
    }
}

extension EnvironmentValues {
  @Entry public var datadogMonitor: any DatadogMonitor = NOPDatadogMonitor()
}

extension View {
    func trackView(name: String) -> some View {
        modifier(TrackViewModifier(name: name))
    }
    
    func privacyOverride(
        text: TextPrivacyLevel? = nil,
        image: ImagePrivacyLevel? = nil,
        touch: TouchPrivacyLevel? = nil,
        hide: Bool? = nil
    ) -> some View {
        modifier(PrivacyOverrideModifier(text: text, image: image, touch: touch, hide: hide))
    }
}

private struct TrackViewModifier: ViewModifier {
    @Environment(\.datadogMonitor) private var monitor
    
    var name: String
    
    func body(content: Content) -> some View {
        content.modifier(monitor.viewModifier(name: name))
    }
}

private struct PrivacyOverrideModifier: ViewModifier {
    @Environment(\.datadogMonitor) private var monitor
    
    var text: TextPrivacyLevel?
    var image: ImagePrivacyLevel?
    var touch: TouchPrivacyLevel?
    var hide: Bool?
    
    func body(content: Content) -> some View {
        content.modifier(monitor.privacyOverride(text: text, image: image, touch: touch, hide: hide))
    }
}
