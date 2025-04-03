/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

public struct AnyViewModifier: ViewModifier {
    private let _body: (Content) -> AnyView

    public init<Body: View>(@ViewBuilder body: @escaping (Content) -> Body) {
        self._body = { AnyView(body($0)) }
    }

    public init() {
        self._body = { AnyView($0) }
    }

    public func body(content: Content) -> some View {
        _body(content)
    }
}
