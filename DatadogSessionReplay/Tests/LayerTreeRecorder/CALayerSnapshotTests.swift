/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import Testing
import UIKit

@testable import DatadogSessionReplay

@MainActor
struct CALayerSnapshotTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures visible layer hierarchy with absolute frames")
    func capturesVisibleLayerHierarchyWithViewportFrames() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let child = CALayer()
        child.frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        root.addSublayer(child)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        #expect(snapshot.absoluteFrame == root.bounds)
        #expect(snapshot.sublayers.count == 1)
        #expect(snapshot.sublayers.first?.absoluteFrame == child.frame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Prunes sublayers outside clipping parent bounds")
    func prunesSublayersOutsideClippingParentBounds() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        parent.masksToBounds = true
        root.addSublayer(parent)

        let child = CALayer()
        child.frame = CGRect(x: 60, y: 0, width: 20, height: 20)
        parent.addSublayer(child)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        let parentSnapshot = try #require(snapshot.sublayers.first)
        #expect(parentSnapshot.sublayers.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Applies hide privacy override and ignores private subtree")
    func appliesHidePrivacyOverrideAndIgnoresPrivateSubtree() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let privateView = UIView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        privateView.dd.sessionReplayPrivacyOverrides.hide = true
        root.addSublayer(privateView.layer)

        let child = CALayer()
        child.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        privateView.layer.addSublayer(child)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        let privateSnapshot = try #require(snapshot.sublayers.first)
        #expect(privateSnapshot.isPrivate)
        #expect(privateSnapshot.observation.semantics == .layer)
        #expect(privateSnapshot.sublayers.isEmpty)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension CALayerSnapshot.Context {
    static func mockAny(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskAll,
        imagePrivacyLevel: ImagePrivacyLevel = .maskAll
    ) -> Self {
        .init(
            textAndInputPrivacyLevel: textAndInputPrivacyLevel,
            imagePrivacyLevel: imagePrivacyLevel
        )
    }
}
#endif
