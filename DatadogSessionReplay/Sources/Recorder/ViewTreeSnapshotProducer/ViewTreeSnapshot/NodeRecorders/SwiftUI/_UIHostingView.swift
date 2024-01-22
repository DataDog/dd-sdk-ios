/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@available(iOS 13.0, *)
internal struct _UIHostingView {
    let renderer: DisplayList.ViewRenderer
}

@available(iOS 13.0, *)
extension _UIHostingView: Reflection {
    init(_ mirror: Mirror) throws {
        renderer = try mirror.descendant(path: "renderer")
    }
}
