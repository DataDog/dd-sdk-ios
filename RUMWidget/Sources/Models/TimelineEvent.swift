/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

struct AppEvent: Identifiable {
    let id: Event
    let text: String
    let width: CGFloat
    let start: CGFloat

    init(id: Event, text: String, width: CGFloat = 2, start: CGFloat) {
        self.id = id
        self.text = text
        self.width = width
        self.start = start
    }
}

extension AppEvent {
    enum Event: Int {
        case load
        case attribute101
        case attribute50000
        case main
        case didFinishLaunching
        case ttid
        case ttfd
    }
}

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
        case appEvent
    }
}
