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
        view.dd.setSessionReplaySlotID("renderer-slot")

        // then
        #expect(view.dd.sessionReplaySlotID == "renderer-slot")
        #expect(otherView.dd.sessionReplaySlotID == nil)
    }

    @available(iOS 13.0, *)
    @Test
    func settingSlotIDToNilClearsIt() {
        // given
        let view = UIView()
        view.dd.setSessionReplaySlotID("renderer-slot")

        // when
        view.dd.setSessionReplaySlotID(nil)

        // then
        #expect(view.dd.sessionReplaySlotID == nil)
    }

    @available(iOS 13.0, *)
    @Test
    func changingSlotIDMarksTheViewAsNeedingLayout() {
        // given
        let view = LayoutSpyView()
        view.layoutIfNeeded()
        view.setNeedsLayoutCount = 0

        // when
        view.dd.setSessionReplaySlotID("renderer-slot")

        // then
        #expect(view.setNeedsLayoutCount == 1)
    }

    @available(iOS 13.0, *)
    @Test
    func settingSameSlotIDDoesNotMarkTheViewAsNeedingLayout() {
        // given
        let view = LayoutSpyView()
        view.dd.setSessionReplaySlotID("renderer-slot")
        view.layoutIfNeeded()
        view.setNeedsLayoutCount = 0

        // when
        view.dd.setSessionReplaySlotID("renderer-slot")

        // then
        #expect(view.setNeedsLayoutCount == 0)
    }

    @available(iOS 13.0, *)
    @Test
    func clearingSlotIDMarksTheViewAsNeedingLayout() {
        // given
        let view = LayoutSpyView()
        view.dd.setSessionReplaySlotID("renderer-slot")
        view.layoutIfNeeded()
        view.setNeedsLayoutCount = 0

        // when
        view.dd.setSessionReplaySlotID(nil)

        // then
        #expect(view.setNeedsLayoutCount == 1)
    }
}

private final class LayoutSpyView: UIView {
    var setNeedsLayoutCount = 0

    override func setNeedsLayout() {
        setNeedsLayoutCount += 1
        super.setNeedsLayout()
    }
}
#endif
