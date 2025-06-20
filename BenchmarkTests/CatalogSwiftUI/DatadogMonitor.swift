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
    func privacyView<Content: View>(
        text: TextPrivacyLevel?,
        image: ImagePrivacyLevel?,
        touch: TouchPrivacyLevel?,
        hide: Bool?,
        @ViewBuilder content: @escaping () -> Content
    ) -> AnyView
}

struct NOPDatadogMonitor: DatadogMonitor {
    func viewModifier(name: String) -> AnyViewModifier { AnyViewModifier() }
    func actionModifier(name: String) -> AnyViewModifier { AnyViewModifier() }
    func privacyView<Content: View>(
        text: TextPrivacyLevel?,
        image: ImagePrivacyLevel?,
        touch: TouchPrivacyLevel?,
        hide: Bool?,
        content: @escaping () -> Content
    ) -> AnyView {
        AnyView(content())
    }
}

extension EnvironmentValues {
  @Entry public var datadogMonitor: any DatadogMonitor = NOPDatadogMonitor()
}

struct PrivacyView<Content: View>: View {
    @Environment(\.datadogMonitor) private var monitor
    
    private var text: TextPrivacyLevel?
    private var image: ImagePrivacyLevel?
    private var touch: TouchPrivacyLevel?
    private var hide: Bool?
    private let content: () -> Content
    
    init(
        text: TextPrivacyLevel? = nil,
        image: ImagePrivacyLevel? = nil,
        touch: TouchPrivacyLevel? = nil,
        hide: Bool? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.text = text
        self.image = image
        self.touch = touch
        self.hide = hide
        self.content = content
    }
    
    var body: some View {
        monitor.privacyView(
            text: text,
            image: image,
            touch: touch,
            hide: hide,
            content: content
        )
    }
}

extension View {
    func trackView(name: String) -> some View {
        modifier(TrackViewModifier(name: name))
    }
}

private struct TrackViewModifier: ViewModifier {
    @Environment(\.datadogMonitor) private var monitor
    
    var name: String
    
    func body(content: Content) -> some View {
        content.modifier(monitor.viewModifier(name: name))
    }
}
