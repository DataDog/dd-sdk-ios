/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import Testing
@_spi(Internal)
@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct DiffSRCompositionTreeTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition tree mutation is nil when unchanged")
    func compositionTreeMutationIsNilWhenUnchanged() throws {
        // Given
        let tree = SRCompositionTree(
            layers: [
                .mockWith(id: 2, children: [.init(id: 42, type: .wireframe)])
            ],
            root: .mockWith(id: 1, children: [.init(id: 2, type: .layer)])
        )

        // When
        let mutation = try tree.mutations(from: tree)

        // Then
        #expect(mutation == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition tree mutation replaces root when root changes")
    func compositionTreeMutationReplacesRootWhenRootChanges() throws {
        // Given
        let oldTree = SRCompositionTree(
            root: .mockWith(id: 1, children: [])
        )
        let newRoot = SRCompositionLayer.mockWith(
            id: 1,
            children: [.init(id: 2, type: .layer)]
        )
        let newTree = SRCompositionTree(root: newRoot)

        // When
        let mutation = try #require(try newTree.mutations(from: oldTree))

        // Then
        #expect(mutation.root == newRoot)
        #expect(mutation.adds == nil)
        #expect(mutation.removes == nil)
        #expect(mutation.updates == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition tree mutation includes layer additions, removals, and updates")
    func compositionTreeMutationIncludesLayerAdditionsRemovalsAndUpdates() throws {
        // Given
        let oldTree = SRCompositionTree(
            layers: [
                .mockWith(id: 2, children: []),
                .mockWith(id: 4, children: [])
            ],
            root: .mockWith(id: 1, children: [.init(id: 2, type: .layer)])
        )
        let addedLayer = SRCompositionLayer.mockWith(id: 3, children: [])
        let updatedLayer = SRCompositionLayer.mockWith(
            id: 2,
            children: [.init(id: 42, type: .wireframe)]
        )
        let newTree = SRCompositionTree(
            layers: [
                updatedLayer,
                addedLayer
            ],
            root: oldTree.root
        )

        // When
        let mutation = try #require(try newTree.mutations(from: oldTree))

        // Then
        #expect(mutation.root == nil)
        #expect(mutation.adds == [addedLayer])
        #expect(mutation.removes == [4])

        #expect(mutation.updates?.count == 1)

        let update = try #require(mutation.updates?.first)
        #expect(update.id == 2)
        #expect(update.children == updatedLayer.children)
        #expect(update.height == nil)
        #expect(update.modifiers == nil)
        #expect(update.width == nil)
        #expect(update.x == nil)
        #expect(update.y == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition tree mutation ignores non-root layer list order")
    func compositionTreeMutationIgnoresNonRootLayerListOrder() throws {
        // Given
        let firstLayer = SRCompositionLayer.mockWith(id: 2, children: [])
        let secondLayer = SRCompositionLayer.mockWith(id: 3, children: [])
        let oldTree = SRCompositionTree(
            layers: [firstLayer, secondLayer],
            root: .mockWith(id: 1, children: [
                .init(id: 2, type: .layer),
                .init(id: 3, type: .layer)
            ])
        )
        let newTree = SRCompositionTree(
            layers: [secondLayer, firstLayer],
            root: oldTree.root
        )

        // When
        let mutation = try newTree.mutations(from: oldTree)

        // Then
        #expect(mutation == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition layer mutation skips unchanged fields")
    func compositionLayerMutationSkipsUnchangedFields() throws {
        // Given
        let layer = SRCompositionLayer(
            children: [.init(id: 1, type: .wireframe)],
            compositeOperation: .destinationIn,
            height: 100,
            id: 42,
            modifiers: [.compositionLayerOpacityModifier(value: .init(value: 0.5))],
            width: 200,
            x: 10,
            y: 20
        )

        // When
        let mutation = try layer.mutations(from: layer)

        // Then
        #expect(mutation.id == 42)
        #expect(mutation.children == nil)
        #expect(mutation.compositeOperation == nil)
        #expect(mutation.height == nil)
        #expect(mutation.modifiers == nil)
        #expect(mutation.width == nil)
        #expect(mutation.x == nil)
        #expect(mutation.y == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition layer mutation includes changed fields")
    func compositionLayerMutationIncludesChangedFields() throws {
        // Given
        let oldLayer = SRCompositionLayer(
            children: [.init(id: 1, type: .wireframe)],
            compositeOperation: .destinationIn,
            height: 100,
            id: 42,
            modifiers: [.compositionLayerOpacityModifier(value: .init(value: 0.5))],
            width: 200,
            x: 10,
            y: 20
        )
        let newLayer = SRCompositionLayer(
            children: [.init(id: 2, type: .layer)],
            compositeOperation: .destinationOut,
            height: 110,
            id: 42,
            modifiers: [.compositionLayerGaussianBlurModifier(value: .init(radius: 4))],
            width: 220,
            x: 15,
            y: 25
        )

        // When
        let mutation = try newLayer.mutations(from: oldLayer)

        // Then
        #expect(mutation.id == 42)
        #expect(mutation.children == newLayer.children)
        #expect(mutation.compositeOperation == .destinationOut)
        #expect(mutation.height == 110)
        #expect(mutation.modifiers == newLayer.modifiers)
        #expect(mutation.width == 220)
        #expect(mutation.x == 15)
        #expect(mutation.y == 25)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition layer mutation clears children with empty array")
    func compositionLayerMutationClearsChildrenWithEmptyArray() throws {
        // Given
        let oldLayer = SRCompositionLayer(
            children: [.init(id: 1, type: .wireframe)],
            height: 100,
            id: 42,
            width: 200,
            x: 10,
            y: 20
        )
        let newLayer = SRCompositionLayer(
            children: [],
            height: 100,
            id: 42,
            width: 200,
            x: 10,
            y: 20
        )

        // When
        let mutation = try newLayer.mutations(from: oldLayer)

        // Then
        #expect(mutation.id == 42)
        #expect(mutation.children?.isEmpty == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition layer mutation clears modifiers with empty array")
    func compositionLayerMutationClearsModifiersWithEmptyArray() throws {
        // Given
        let oldLayer = SRCompositionLayer(
            children: [],
            height: 100,
            id: 42,
            modifiers: [.compositionLayerOpacityModifier(value: .init(value: 0.5))],
            width: 200,
            x: 10,
            y: 20
        )
        let newLayer = SRCompositionLayer(
            children: [],
            height: 100,
            id: 42,
            width: 200,
            x: 10,
            y: 20
        )

        // When
        let mutation = try newLayer.mutations(from: oldLayer)

        // Then
        #expect(mutation.id == 42)
        #expect(mutation.modifiers?.isEmpty == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition layer mutation clears composite operation with source-over")
    func compositionLayerMutationClearsCompositeOperationWithSourceOver() throws {
        // Given
        let oldLayer = SRCompositionLayer(
            children: [],
            compositeOperation: .destinationIn,
            height: 100,
            id: 42,
            width: 200,
            x: 10,
            y: 20
        )
        let newLayer = SRCompositionLayer(
            children: [],
            height: 100,
            id: 42,
            width: 200,
            x: 10,
            y: 20
        )

        // When
        let mutation = try newLayer.mutations(from: oldLayer)

        // Then
        #expect(mutation.id == 42)
        #expect(mutation.compositeOperation == .sourceOver)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition layer mutation throws when IDs differ")
    func compositionLayerMutationThrowsWhenIDsDiffer() {
        // Given
        let oldLayer = SRCompositionLayer(
            children: [],
            height: 100,
            id: 42,
            width: 200,
            x: 10,
            y: 20
        )
        let newLayer = SRCompositionLayer(
            children: [],
            height: 100,
            id: 43,
            width: 200,
            x: 10,
            y: 20
        )

        // When / Then
        #expect(throws: CompositionLayerMutationError.idMismatch) {
            _ = try newLayer.mutations(from: oldLayer)
        }
    }
}

private extension SRCompositionLayer {
    static func mockWith(
        id: Int64,
        children: [SRCompositionLayerChild],
        modifiers: [SRCompositionLayerModifier]? = nil
    ) -> SRCompositionLayer {
        return SRCompositionLayer(
            children: children,
            height: 100,
            id: id,
            modifiers: modifiers,
            width: 200,
            x: 10,
            y: 20
        )
    }
}
#endif
