/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

struct TimelineEvent: Identifiable {
    let id: Int
    let start: CGFloat
    let duration: TimeInterval
    let event: Event
}

extension TimelineEvent {
    enum Event {
        case viewHitch
        case appHang
        case userAction
        case resource
    }
}
