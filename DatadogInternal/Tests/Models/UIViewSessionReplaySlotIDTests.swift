/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogInternal

@Suite(.datadogTesting)
@MainActor
struct UIViewSessionReplaySlotIDTests {
    @available(iOS 13.0, *)
    @Test
    func slotIDIsNilByDefault() {
        // given
        let view = UIView()

        // when
        let slotID = view.dd.sessionReplaySlotID

        // then
        #expect(slotID == nil)
    }

    @available(iOS 13.0, *)
    @Test
    func slotIDIsStoredPerView() {
        // given
        let view = UIView()
        let otherView = UIView()

        // when
        view.dd.sessionReplaySlotID = "renderer-slot"

        // then
        #expect(view.dd.sessionReplaySlotID == "renderer-slot")
        #expect(otherView.dd.sessionReplaySlotID == nil)
    }

    @available(iOS 13.0, *)
    @Test
    func settingSlotIDToNilClearsIt() {
        // given
        let view = UIView()
        view.dd.sessionReplaySlotID = "renderer-slot"

        // when
        view.dd.sessionReplaySlotID = nil

        // then
        #expect(view.dd.sessionReplaySlotID == nil)
    }

    /// Collects `ddSessionReplaySlotIDDidChange` notification objects for the duration of `body`.
    @available(iOS 13.0, *)
    private func recordingNotifications(_ body: () -> Void) -> [UIView] {
        var views: [UIView] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .ddSessionReplaySlotIDDidChange,
            object: nil,
            queue: nil
        ) { notification in
            (notification.object as? UIView).map { views.append($0) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        body()
        return views
    }

    @available(iOS 13.0, *)
    @Test
    func settingSlotIDNotifiesWithTheView() {
        // given
        let view = UIView()

        // when
        let notifiedViews = recordingNotifications {
            view.dd.sessionReplaySlotID = "renderer-slot"
        }

        // then — Session Replay only snapshots on CALayer activity, which assigning an associated
        // object does not produce; without this the slot's placeholder would not be recorded until
        // some unrelated change happened to trigger the next snapshot
        #expect(notifiedViews.count == 1)
        #expect(notifiedViews.first === view)
    }

    @available(iOS 13.0, *)
    @Test
    func settingSlotIDToTheSameValueDoesNotNotify() {
        // given
        let view = UIView()
        view.dd.sessionReplaySlotID = "renderer-slot"

        // when
        let notifiedViews = recordingNotifications {
            view.dd.sessionReplaySlotID = "renderer-slot"
        }

        // then — nothing changed, so scheduling a snapshot for it would be wasted work
        #expect(notifiedViews.isEmpty)
    }

    @available(iOS 13.0, *)
    @Test
    func clearingSlotIDNotifies() {
        // given
        let view = UIView()
        view.dd.sessionReplaySlotID = "renderer-slot"

        // when
        let notifiedViews = recordingNotifications {
            view.dd.sessionReplaySlotID = nil
        }

        // then — the placeholder must stop being emitted, which also needs a fresh snapshot
        #expect(notifiedViews.count == 1)
        #expect(notifiedViews.first === view)
    }
}
#endif
