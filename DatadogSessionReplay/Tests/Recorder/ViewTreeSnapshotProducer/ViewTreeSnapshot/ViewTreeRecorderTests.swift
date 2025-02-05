/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import SafariServices
import SwiftUI

@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

private struct MockSemantics: NodeSemantics {
    static var importance: Int = .mockAny()
    var subtreeStrategy: NodeSubtreeStrategy
    var nodes: [Node]
    var resources: [Resource]

    init(subtreeStrategy: NodeSubtreeStrategy, nodeNames: [String], resourcesIdentifiers: [String]) {
        self.subtreeStrategy = subtreeStrategy
        self.nodes = nodeNames.map {
            Node(viewAttributes: .mockAny(), wireframesBuilder: MockWireframesBuilder(nodeName: $0))
        }
        self.resources = resourcesIdentifiers.map {
            MockResource(identifier: $0, data: .mockRandom())
        }
    }
}

private struct MockWireframesBuilder: NodeWireframesBuilder {
    let nodeName: String
    var wireframeRect: CGRect = .mockAny()
    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] { [] }
}

class ViewTreeRecorderTests: XCTestCase {
    // MARK: - Querying Node Recorders

    func testItQueriesAllNodeRecorders() {
        // Given
        let rootView = UIView(frame: .mockRandom())
        let childView = UIView(frame: .mockRandom())
        let grandchildView = UIView(frame: .mockRandom())
        childView.addSubview(grandchildView)
        rootView.addSubview(childView)

        // When
        let recorders: [NodeRecorderMock] = [
            NodeRecorderMock(resultForView: { _ in nil }),
            NodeRecorderMock(resultForView: { _ in nil }),
            NodeRecorderMock(resultForView: { _ in nil }),
        ]
        let recorder = ViewTreeRecorder(nodeRecorders: recorders)
        _ = recorder.record(rootView, in: .mockAny())

        // Then
        XCTAssertEqual(recorders[0].queriedViews, [rootView, childView, grandchildView])
        XCTAssertEqual(recorders[1].queriedViews, [rootView, childView, grandchildView])
        XCTAssertEqual(recorders[2].queriedViews, [rootView, childView, grandchildView])
    }

    func testItQueriesNodeRecordersUntilOneFindsBestSemantics() {
        // Given
        let view = UIView(frame: .mockRandom())
        let unknownElement = UnknownElement.constant
        let ambiguousElement = AmbiguousElement(nodes: .mockAny())
        let specificElement = SpecificElement(subtreeStrategy: .mockRandom(), nodes: .mockAny())

        // When
        let recorders: [NodeRecorderMock] = [
            NodeRecorderMock(resultForView: { _ in unknownElement }),
            NodeRecorderMock(resultForView: { _ in ambiguousElement }),
            NodeRecorderMock(resultForView: { _ in ambiguousElement }),
            NodeRecorderMock(resultForView: { _ in specificElement }), // here we find best semantics...
            NodeRecorderMock(resultForView: { _ in specificElement }), // ... so this one should not be queried
        ]
        let recorder = ViewTreeRecorder(nodeRecorders: recorders)
        _ = recorder.record(view, in: .mockAny())

        // Then
        XCTAssertEqual(recorders[0].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[1].queriedViews, [view], "It should be queried as semantics is not known")
        XCTAssertEqual(recorders[2].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[3].queriedViews, [view], "It should be queried as only 'ambiguous' semantics is known")
        XCTAssertEqual(recorders[4].queriedViews, [], "It should NOT be queried as 'specific' semantics is known")
    }

    // MARK: - Recording Nodes Recursively

    func testItQueriesViewTreeRecursivelyAndReturnsNodesAndResourcesInDFSOrder() {
        // Given

        /*
                rootView
                /   |   \
               /    |    \
               a    b     c
              / \        / \
             aa ab      ca cb
             /  / \
          aaa aba abb
        */

        let rootView = UIView.mockAny()
        let (a, b, c) = (UIView.mockAny(), UIView.mockAny(), UIView.mockAny())
        let (aa, aaa, ab, aba, abb) = (UIView.mockAny(), UIView.mockAny(), UIView.mockAny(), UIView.mockAny(), UIView.mockAny())
        let (ca, cb) = (UIView.mockAny(), UIView.mockAny())

        rootView.addSubview(a)
        rootView.addSubview(b)
        rootView.addSubview(c)
        a.addSubview(aa)
        aa.addSubview(aaa)
        a.addSubview(ab)
        ab.addSubview(aba)
        ab.addSubview(abb)
        c.addSubview(ca)
        c.addSubview(cb)

        let semanticsByView: [UIView: NodeSemantics] = [
            rootView: MockSemantics(subtreeStrategy: .record, nodeNames: ["rootView"], resourcesIdentifiers: ["rootResource"]),
            a: MockSemantics(subtreeStrategy: .record, nodeNames: ["a"], resourcesIdentifiers: ["a"]),
            b: MockSemantics(subtreeStrategy: .record, nodeNames: ["b"], resourcesIdentifiers: ["b"]),
            c: MockSemantics(subtreeStrategy: .ignore, nodeNames: ["c"], resourcesIdentifiers: ["c"]), // ignore subtree of `c`
            aa: MockSemantics(subtreeStrategy: .ignore, nodeNames: ["aa", "aav1", "aav2", "aav3"], resourcesIdentifiers: ["aa", "aav1", "aav2", "aav3"]), // replace `aaa` (subtree of `aa`) with 3 nodes
            ab: MockSemantics(subtreeStrategy: .record, nodeNames: ["ab"], resourcesIdentifiers: ["ab"]),
            aba: MockSemantics(subtreeStrategy: .record, nodeNames: ["aba"], resourcesIdentifiers: ["aba"]),
            abb: MockSemantics(subtreeStrategy: .record, nodeNames: ["abb"], resourcesIdentifiers: ["abb"]),
            ca: MockSemantics(subtreeStrategy: .record, nodeNames: ["ca"], resourcesIdentifiers: ["ca"]),
            cb: MockSemantics(subtreeStrategy: .record, nodeNames: ["cb"], resourcesIdentifiers: ["cb"]),
        ]

        // When
        let nodeRecorder = NodeRecorderMock(resultForView: { view in semanticsByView[view] })
        let recorder = ViewTreeRecorder(nodeRecorders: [nodeRecorder])
        let nodes = recorder.record(rootView, in: .mockRandom())

        // Then
        let expectedNodes = ["rootView", "a", "aa", "aav1", "aav2", "aav3", "ab", "aba", "abb", "b", "c"]
        let actualNodes = nodes.compactMap { ($0.wireframesBuilder as? MockWireframesBuilder)?.nodeName }
        XCTAssertEqual(expectedNodes, actualNodes, "Nodes must be recorded in DFS order")

        let expectedQueriedViews: [UIView] = [rootView, a, b, c, aa, ab, aba, abb]
        XCTAssertEqual(nodeRecorder.queriedViews.count, expectedQueriedViews.count)
        expectedQueriedViews.forEach { XCTAssertTrue(nodeRecorder.queriedViews.contains($0)) }

        let expectedSkippedViews: [UIView] = [aaa, ca, cb]
        expectedSkippedViews.forEach { XCTAssertFalse(nodeRecorder.queriedViews.contains($0)) }
    }

    // MARK: - Recording Certain Node Semantics

    func testItRecordsInvisibleViews() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let views: [UIView] = [
            UIView.mock(withFixture: .invisible),
            UILabel.mock(withFixture: .invisible),
            UIImageView.mock(withFixture: .invisible),
            UITextField.mock(withFixture: .invisible),
            UISwitch.mock(withFixture: .invisible),
        ]

        views.forEach { view in
            // When
            let nodes = recorder.record(view, in: .mockRandom())
            // Then
            XCTAssertTrue(nodes.isEmpty, "No nodes should be recorded for \(type(of: view)) when it is not visible")
        }
    }

    func testItRecordsViewsWithNoAppearance() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))

        let view = UIView.mock(withFixture: .visible(.noAppearance))
        let label = UILabel.mock(withFixture: .visible(.noAppearance))
        let imageView = UIImageView.mock(withFixture: .visible(.noAppearance))
        let textField = UITextField.mock(withFixture: .visible(.noAppearance))
        let `switch` = UISwitch.mock(withFixture: .visible(.noAppearance))

        // When
        var nodes = recorder.record(view, in: .mockWith(clip: view.frame))
        XCTAssertTrue(nodes.isEmpty, "No nodes should be recorded for `UIView` when it has no appearance")

        nodes = recorder.record(label, in: .mockWith(clip: label.frame))
        XCTAssertTrue(nodes.isEmpty, "No nodes should be recorded for `UILabel` when it has no appearance")

        nodes = recorder.record(imageView, in: .mockWith(clip: imageView.frame))
        XCTAssertTrue(nodes.isEmpty, "No nodes should be recorded for `UIImageView` when it has no appearance")

        nodes = recorder.record(textField, in: .mockWith(clip: textField.frame))
        XCTAssertTrue(nodes.isEmpty, "No nodes should be recorded for `UITextField` when it has no appearance")

        nodes = recorder.record(`switch`, in: .mockWith(clip: `switch`.frame))
        XCTAssertFalse(
            nodes.isEmpty,
            "`UISwitch` with no appearance should record some nodes as it has style coming from its internal subtree."
        )
    }

    func testItRecordsViewsWithSomeAppearance() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let views: [UIView] = [
            UIView.mock(withFixture: .visible(.someAppearance)),
            UILabel.mock(withFixture: .visible(.someAppearance)),
            UIImageView.mock(withFixture: .visible(.someAppearance)),
            UITextField.mock(withFixture: .visible(.someAppearance)),
            UISwitch.mock(withFixture: .visible(.someAppearance)),
            UITabBar.mock(withFixture: .visible(.someAppearance)),
            UINavigationBar.mock(withFixture: .visible(.someAppearance)),
        ]

        views.forEach { view in
            // When
            let nodes = recorder.record(view, in: .mockWith(clip: view.frame))
            // Then
            XCTAssertFalse(nodes.isEmpty, "Some nodes should be recorded for \(type(of: view)) when it has some appearance")
        }
    }

    func testItOverridesViewControllerContext() throws {
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in nil })
        let recorder = ViewTreeRecorder(nodeRecorders: [nodeRecorder])

        let window = UIWindow()
        window.makeKeyAndVisible()
        defer { window.resignKey() }

        // Given
        let subview = UIView()
        let vc = UIViewController()
        window.rootViewController = vc
        vc.view.addSubview(subview)

        // When
        _ = recorder.record(vc.view, in: .mockRandom())

        // Then
        var context = nodeRecorder.queryContextsByView[vc.view]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .other)

        context = nodeRecorder.queryContextsByView[subview]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .other)

        // Given
        let alert = UIAlertController(title: "", message: "", preferredStyle: .alert)
        window.rootViewController?.present(alert, animated: false)
        alert.view.addSubview(subview)

        // When
        _ = recorder.record(alert.view, in: .mockRandom())

        context = nodeRecorder.queryContextsByView[alert.view]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .alert)

        context = nodeRecorder.queryContextsByView[subview]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .alert)

        window.rootViewController?.dismiss(animated: false)

        // Given
        let safari = SFSafariViewController(url: .mockRandom())
        window.rootViewController = safari
        safari.view.addSubview(subview)

        // When
        _ = recorder.record(safari.view, in: .mockRandom())

        context = nodeRecorder.queryContextsByView[safari.view]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .safari)

        context = nodeRecorder.queryContextsByView[subview]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .safari)

        // Given
        let activity = UIActivityViewController(activityItems: [], applicationActivities: nil)
        activity.view.addSubview(subview)
        window.rootViewController?.present(activity, animated: false)

        // When
        _ = recorder.record(activity.view, in: .mockRandom())

        context = nodeRecorder.queryContextsByView[activity.view]
        XCTAssertEqual(context?.viewControllerContext.isRootView, true)
        XCTAssertEqual(context?.viewControllerContext.parentType, .activity)

        context = nodeRecorder.queryContextsByView[subview]
        XCTAssertEqual(context?.viewControllerContext.isRootView, false)
        XCTAssertEqual(context?.viewControllerContext.parentType, .activity)

        if #available(iOS 13, *) {
            // Given
            let swiftUI = UIHostingController(rootView: EmptyView())
            swiftUI.view.addSubview(subview)
            window.rootViewController?.present(swiftUI, animated: false)

            // When
            _ = recorder.record(swiftUI.view, in: .mockRandom())

            context = nodeRecorder.queryContextsByView[swiftUI.view]
            XCTAssertEqual(context?.viewControllerContext.isRootView, true)
            XCTAssertEqual(context?.viewControllerContext.parentType, .swiftUI)

            context = nodeRecorder.queryContextsByView[subview]
            XCTAssertEqual(context?.viewControllerContext.isRootView, false)
            XCTAssertEqual(context?.viewControllerContext.parentType, .swiftUI)
        }

        window.rootViewController?.dismiss(animated: false)
    }

    // MARK: Privacy Overrides

    func testChildViewInheritsParentHideOverride() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let childView = UIView.mock(withFixture: .visible(.someAppearance))
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.addSubview(childView)
        parentView.dd.sessionReplayPrivacyOverrides.hide = true

        // When
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 1)
    }

    func testChildViewHideOverrideIsTrueAndParentHideOverrideIsFalse() {
        // Given
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let childView = UIView.mock(withFixture: .visible(.someAppearance))
        childView.dd.sessionReplayPrivacyOverrides.hide = true
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.addSubview(childView)
        parentView.dd.sessionReplayPrivacyOverrides.hide = false

        // When
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 2)
    }

    func testChildViewHideOverrideIsTrueAndParentHideOverrideIsNil() {
        // Given
        let childView = UIView.mock(withFixture: .visible(.someAppearance))
        childView.dd.sessionReplayPrivacyOverrides.hide = true
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.addSubview(childView)

        // When
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 2)
    }

    func testImageViewOverrideTakesPrecedenceOverGlobalSetting() {
        // Given
        let globalImagePrivacy: ImagePrivacyLevel = .mockRandom()
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(imagePrivacy: globalImagePrivacy))

        let viewImagePrivacy: ImagePrivacyLevel = .maskNone
        let imageView = UIImageView.mock(withFixture: .visible(.someAppearance))
        imageView.image = .mockRandom()
        imageView.dd.sessionReplayPrivacyOverrides.imagePrivacy = viewImagePrivacy

        // When
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let nodes = recorder.record(imageView, in: context)

        // Then
        XCTAssertEqual(nodes.count, 1)
        let node = nodes.first
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.viewAttributes.imagePrivacy, viewImagePrivacy)
        let builder = node?.wireframesBuilder as? UIImageViewWireframesBuilder
        XCTAssertNotNil(builder)
        XCTAssertNotNil(builder!.imageResource)
    }

    func testChildViewMaskNoneImageOverrideWithParentImageOverride() {
        // Given
        let childImagePrivacy: ImagePrivacyLevel = .maskNone
        let childView = UIImageView.mock(withFixture: .visible(.someAppearance))
        childView.image = .mockRandom()
        childView.dd.sessionReplayPrivacyOverrides.imagePrivacy = childImagePrivacy
        let parentImagePrivacy: ImagePrivacyLevel = .mockRandom()
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.dd.sessionReplayPrivacyOverrides.imagePrivacy = parentImagePrivacy
        parentView.addSubview(childView)

        // When
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].viewAttributes.imagePrivacy, parentImagePrivacy)
        XCTAssertEqual(nodes[1].viewAttributes.imagePrivacy, childImagePrivacy)
        let builder = nodes[1].wireframesBuilder as? UIImageViewWireframesBuilder
        XCTAssertNotNil(builder)
        XCTAssertNotNil(builder!.imageResource)
    }

    func testChildViewMaskAllImageOverrideWithParentImageOverride() {
        // Given
        let childImagePrivacy: ImagePrivacyLevel = .maskAll
        let childView = UIImageView.mock(withFixture: .visible(.someAppearance))
        childView.image = .mockRandom()
        childView.dd.sessionReplayPrivacyOverrides.imagePrivacy = childImagePrivacy
        let parentImagePrivacy: ImagePrivacyLevel = .mockRandom()
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.dd.sessionReplayPrivacyOverrides.imagePrivacy = parentImagePrivacy
        parentView.addSubview(childView)

        // When
        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled))
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].viewAttributes.imagePrivacy, parentImagePrivacy)
        XCTAssertEqual(nodes[1].viewAttributes.imagePrivacy, childImagePrivacy)
        let builder = nodes[1].wireframesBuilder as? UIImageViewWireframesBuilder
        XCTAssertNotNil(builder)
        XCTAssertNil(builder!.imageResource)
    }

    func testItPropagateClippingIntersection() {
        let nodeRecorder = NodeRecorderMock(resultForView: { _ in
            MockSemantics(subtreeStrategy: .record, nodeNames: [], resourcesIdentifiers: [])
        })
        let recorder = ViewTreeRecorder(nodeRecorders: [nodeRecorder])

        // ┌──────────────┐
        // │Root          │
        // │  ┌────────┐  │
        // │  │ View1  │  │
        // │  │ ┌────────┐│
        // │  │ │ View2│ ││
        // │  │ │      │ ││
        // │  │ │      │ ││
        // │  │ │      │ ││
        // │  └─│──────┘ ││
        // │    └────────┘│
        // └──────────────┘

        // Given
        var frame = CGRect(origin: .zero, size: .mockRandom(minWidth: 21, minHeight: 21))
        let rootView = UIView(frame: frame)

        frame = frame.insetBy(dx: 10, dy: 10)
        let view1 = UIView(frame: frame)
        view1.clipsToBounds = true // clip to the first view
        rootView.addSubview(view1)

        frame = frame.offsetBy(dx: 10, dy: 10)
        let view2 = UIView(frame: frame)
        view1.addSubview(view2)

        // When
        _ = recorder.record(rootView, in: .mockWith(coordinateSpace: rootView))

        // Then
        var context = nodeRecorder.queryContextsByView[rootView]
        var attributes = nodeRecorder.queryAttributesByView[rootView]
        // clip to the root view
        XCTAssertEqual(context?.clip, rootView.bounds)
        XCTAssertEqual(attributes?.clip, rootView.bounds)

        context = nodeRecorder.queryContextsByView[view1]
        attributes = nodeRecorder.queryAttributesByView[view1]
        // clip to view 1
        XCTAssertEqual(context?.clip, view1.frame)
        XCTAssertEqual(attributes?.clip, view1.frame)

        context = nodeRecorder.queryContextsByView[view2]
        attributes = nodeRecorder.queryAttributesByView[view2]
        // still clip to view 1
        XCTAssertEqual(context?.clip, view1.frame)
        XCTAssertEqual(attributes?.clip, view1.frame)
    }
}

#endif
