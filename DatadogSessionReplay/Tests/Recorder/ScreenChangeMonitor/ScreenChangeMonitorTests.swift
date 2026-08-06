/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import UIKit
import XCTest

@_spi(Internal)
import DatadogInternal

@testable import DatadogSessionReplay

@MainActor
final class ScreenChangeMonitorTests: XCTestCase {
    private let testTimerScheduler = TestTimerScheduler(now: 0)
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var screenChangeMonitor: ScreenChangeMonitor!
    private var changesets: [CALayerChangeset] = []
    private var window: UIWindow?

    override func setUp() async throws {
        try await super.setUp()

        screenChangeMonitor = try ScreenChangeMonitor(
            minimumDeliveryInterval: 0.1,
            timerScheduler: testTimerScheduler
        ) { [weak self] changeset in
            self?.changesets.append(changeset)
        }
    }

    override func tearDown() {
        screenChangeMonitor?.stop()
        screenChangeMonitor = nil
        window?.isHidden = true
        window = nil
        changesets.removeAll()
        super.tearDown()
    }

    func testStartAndStop() {
        // given
        let layer = CALayer()

        // when
        testTimerScheduler.advance(to: 0.01)
        layer.display() // ignored
        testTimerScheduler.advance(to: 1.00)

        // then
        XCTAssertEqual(changesets.count, 0, "Should ignore layer changes before calling start()")

        // when
        screenChangeMonitor.start()

        testTimerScheduler.advance(to: 1.01)
        layer.display()
        testTimerScheduler.advance(to: 1.20)

        // then
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(changesets[0].aspects(for: .init(layer)), .display)

        // given
        changesets.removeAll()

        // when
        screenChangeMonitor.stop()

        testTimerScheduler.advance(to: 2.00)
        layer.display()
        testTimerScheduler.advance(to: 3.00)

        // then
        XCTAssertEqual(changesets.count, 0, "Should ignore layer changes after calling stop()")
    }

    // MARK: - Session Replay slot IDs
    //
    // The embedding host renders through a `CAMetalLayer`, which never triggers `display` or
    // `draw(in:)` on its own. Without a change reported when the slot is assigned, the embedded
    // content could stay unrecorded until something unrelated changed on screen.

    @available(iOS 13.0, *)
    func testWhenSlotIDIsAssignedToMetalBackedViewInWindow_itReportsLayoutChange() {
        // given — a Metal-backed view on screen with its layout settled, as after the host
        // presented the embedded content
        let view = MetalBackedView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let window = makeKeyWindow(with: view)
        CATransaction.flush()

        screenChangeMonitor.start()
        testTimerScheduler.advance(to: 1.00)
        changesets.removeAll()

        // when — the embedding SDK registers the slot. Nothing else on screen changes.
        view.dd.sessionReplaySlotID = "renderer-slot"
        CATransaction.flush()

        // then — the swizzled `CALayer.layoutSublayers` fired, even though the layer draws
        // none of its contents through Core Animation
        testTimerScheduler.advance(to: 1.20)
        XCTAssertTrue(view.layer is CAMetalLayer)
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(changesets.first?.aspects(for: .init(view.layer)), .layout)
        withExtendedLifetime(window) {}
    }

    @available(iOS 13.0, *)
    func testWhenSlotIDIsAssignedBeforeTheViewIsOnScreen_itReportsLayoutChangeOnAttachment() {
        // given — the slot is minted eagerly, before the host presents the view. A detached
        // layer is not in the render tree, so no layout pass runs for it yet.
        let view = MetalBackedView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        screenChangeMonitor.start()
        testTimerScheduler.advance(to: 1.00)
        view.dd.sessionReplaySlotID = "renderer-slot"

        // when — the host presents it
        let window = makeKeyWindow(with: view)
        CATransaction.flush()

        // then — the pending layout is flushed on attachment, so the slot is still recorded
        testTimerScheduler.advance(to: 1.20)
        let aspects = changesets.map { $0.aspects(for: .init(view.layer)) }
        XCTAssertTrue(aspects.contains { $0?.contains(.layout) == true }, "got \(aspects)")
        withExtendedLifetime(window) {}
    }

    private func makeKeyWindow(with view: UIView) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)
        window.makeKeyAndVisible()
        self.window = window
        return window
    }
}

/// Mimics `FlutterView`, which renders through Metal rather than Core Animation.
@available(iOS 13.0, *)
private final class MetalBackedView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
}
#endif
