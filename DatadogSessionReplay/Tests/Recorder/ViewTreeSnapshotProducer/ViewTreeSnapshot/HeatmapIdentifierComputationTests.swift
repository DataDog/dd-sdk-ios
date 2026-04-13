/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import UIKit
import DatadogInternal

@_spi(Internal)
@testable import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct HeatmapIdentifierComputationTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Uses accessibility identifier as path component when set")
    func accessibilityIdentifierComponent() {
        // Given
        let view = UIView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        view.backgroundColor = .red
        view.accessibilityIdentifier = "myButton"

        let recorder = ViewTreeRecorder(
            nodeRecorders: [UIViewRecorder(identifier: UUID())],
            bundleIdentifier: "com.example.app"
        )
        let context = ViewTreeRecordingContext.mockWith(
            recorder: .mockWith(rumContext: .mockWith(viewPath: "Home")),
            coordinateSpace: view
        )
        let expected = HeatmapIdentifier(
            elementPath: ["myButton"],
            screenName: "Home",
            bundleIdentifier: "com.example.app"
        )

        // When
        let nodes = recorder.record(view, in: context)

        // Then
        #expect(nodes.first?.heatmapIdentifier == expected)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Uses cls:ClassName#typeIndex when accessibility identifier is not set")
    func classNameComponent() {
        // Given
        let view = UIView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        view.backgroundColor = .red

        let recorder = ViewTreeRecorder(
            nodeRecorders: [UIViewRecorder(identifier: UUID())],
            bundleIdentifier: "com.example.app"
        )
        let context = ViewTreeRecordingContext.mockWith(
            recorder: .mockWith(rumContext: .mockWith(viewPath: "Home")),
            coordinateSpace: view
        )
        let expected = HeatmapIdentifier(
            elementPath: ["cls:UIView#0"],
            screenName: "Home",
            bundleIdentifier: "com.example.app"
        )

        // When
        let nodes = recorder.record(view, in: context)

        // Then
        #expect(nodes.first?.heatmapIdentifier == expected)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Computes correct type indices for same-type siblings")
    func sameTypeSiblingTypeIndices() {
        // Given
        let parent = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        parent.backgroundColor = .white
        let button0 = UIButton(frame: .init(x: 0, y: 0, width: 100, height: 44))
        button0.backgroundColor = .blue
        let label = UILabel(frame: .init(x: 0, y: 44, width: 100, height: 20))
        label.text = "Hello"
        label.textColor = .black
        let button1 = UIButton(frame: .init(x: 0, y: 64, width: 100, height: 44))
        button1.backgroundColor = .blue

        parent.addSubview(button0)
        parent.addSubview(label)
        parent.addSubview(button1)

        let recorder = ViewTreeRecorder(
            nodeRecorders: createDefaultNodeRecorders(featureFlags: .allEnabled),
            bundleIdentifier: "com.example.app"
        )
        let context = ViewTreeRecordingContext.mockWith(
            recorder: .mockWith(rumContext: .mockWith(viewPath: "Home")),
            coordinateSpace: parent
        )

        // When
        let nodes = recorder.record(parent, in: context)

        // Then
        let firstButtonIdentifier = nodes.first(where: { node in
            node.heatmapIdentifier == HeatmapIdentifier(
                elementPath: ["cls:UIView#0", "cls:UIButton#0"],
                screenName: "Home",
                bundleIdentifier: "com.example.app"
            )
        })?.heatmapIdentifier

        let secondButtonIdentifier = nodes.first(where: { node in
            node.heatmapIdentifier == HeatmapIdentifier(
                elementPath: ["cls:UIView#0", "cls:UIButton#1"],
                screenName: "Home",
                bundleIdentifier: "com.example.app"
            )
        })?.heatmapIdentifier

        #expect(firstButtonIdentifier != nil)
        #expect(secondButtonIdentifier != nil)
        #expect(firstButtonIdentifier != secondButtonIdentifier)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Populates heatmap cache during traversal")
    func registryPopulation() {
        // Given
        let parent = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let child = UIView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        child.backgroundColor = .red
        parent.addSubview(child)

        let recorder = ViewTreeRecorder(
            nodeRecorders: [UIViewRecorder(identifier: UUID())],
            bundleIdentifier: "com.example.app"
        )
        let heatmapCache = HeatmapCache()
        let context = ViewTreeRecordingContext.mockWith(
            recorder: .mockWith(rumContext: .mockWith(viewPath: "Home")),
            coordinateSpace: parent,
            heatmapCache: heatmapCache
        )

        // When
        _ = recorder.record(parent, in: context)

        // Then
        #expect(heatmapCache.identifiers[ObjectIdentifier(parent)] != nil)
        #expect(heatmapCache.identifiers[ObjectIdentifier(child)] != nil)
        #expect(heatmapCache.identifiers[ObjectIdentifier(parent)] != heatmapCache.identifiers[ObjectIdentifier(child)])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips heatmap computation when viewPath is nil")
    func noViewPath() {
        // Given
        let view = UIView(frame: .init(x: 0, y: 0, width: 100, height: 100))

        let recorder = ViewTreeRecorder(
            nodeRecorders: [UIViewRecorder(identifier: UUID())],
            bundleIdentifier: "com.example.app"
        )
        let heatmapCache = HeatmapCache()
        let context = ViewTreeRecordingContext.mockWith(
            recorder: .mockWith(rumContext: .mockWith(viewPath: nil)),
            coordinateSpace: view,
            heatmapCache: heatmapCache
        )

        // When
        let nodes = recorder.record(view, in: context)

        // Then
        #expect(nodes.first?.heatmapIdentifier == nil)
        #expect(heatmapCache.identifiers.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Wireframes carry permanentId from their node")
    func wireframePermanentId() {
        // Given
        let identifier = HeatmapIdentifier(rawValue: "abc123")
        var node = Node(
            viewAttributes: .mockAny(),
            wireframesBuilder: UIViewWireframesBuilder(
                wireframeID: 1,
                attributes: .mockWith(
                    frame: .init(x: 0, y: 0, width: 100, height: 100),
                    clip: .init(x: 0, y: 0, width: 100, height: 100)
                )
            )
        )
        node.heatmapIdentifier = identifier

        // When
        let builder = WireframesBuilder()
        builder.heatmapIdentifier = node.heatmapIdentifier
        let wireframes = node.wireframesBuilder.buildWireframes(with: builder)

        // Then
        let permanentId = wireframes.first.flatMap { wireframe -> String? in
            switch wireframe {
            case .shapeWireframe(let value): return value.permanentId
            case .textWireframe(let value): return value.permanentId
            case .imageWireframe(let value): return value.permanentId
            case .placeholderWireframe(let value): return value.permanentId
            case .webviewWireframe(let value): return value.permanentId
            }
        }
        #expect(permanentId == "abc123")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Wireframes have nil permanentId when no heatmap identifier")
    func wireframeNoPermanentId() {
        // Given
        let node = Node(
            viewAttributes: .mockAny(),
            wireframesBuilder: UIViewWireframesBuilder(
                wireframeID: 1,
                attributes: .mockWith(
                    frame: .init(x: 0, y: 0, width: 100, height: 100),
                    clip: .init(x: 0, y: 0, width: 100, height: 100)
                )
            )
        )

        // When
        let builder = WireframesBuilder()
        let wireframes = node.wireframesBuilder.buildWireframes(with: builder)

        // Then
        let permanentId = wireframes.first.flatMap { wireframe -> String? in
            switch wireframe {
            case .shapeWireframe(let value): return value.permanentId
            case .textWireframe(let value): return value.permanentId
            case .imageWireframe(let value): return value.permanentId
            case .placeholderWireframe(let value): return value.permanentId
            case .webviewWireframe(let value): return value.permanentId
            }
        }
        #expect(permanentId == nil)
    }
}
#endif
