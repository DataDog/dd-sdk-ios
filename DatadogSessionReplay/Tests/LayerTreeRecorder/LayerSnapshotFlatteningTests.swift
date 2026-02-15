/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import QuartzCore

@testable import DatadogSessionReplay

extension LayerSnapshotTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func flattenedReturnsArrayWithNoChildren() {
        // given
        let leaf1 = Fixtures.snapshot(replayID: 1, hasContents: true)
        let leaf2 = Fixtures.snapshot(replayID: 2, hasContents: true)
        let container = Fixtures.snapshot(replayID: 3, children: [leaf1, leaf2])
        let root = Fixtures.snapshot(replayID: 4, hasContents: true, children: [container])

        // when
        let result = root.flattened()

        // then
        for snapshot in result {
            #expect(snapshot.children.isEmpty)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func flattenedOrdersParentBeforeChildren() {
        // given
        let child1 = Fixtures.snapshot(replayID: 2, hasContents: true)
        let child2 = Fixtures.snapshot(replayID: 3, hasContents: true)
        let parent = Fixtures.snapshot(replayID: 1, hasContents: true, children: [child1, child2])

        // when
        let result = parent.flattened()

        // then
        #expect(result.map(\.replayID) == [1, 2, 3])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func flattenedPreservesNestedStructureOrder() {
        // given
        let leaf1 = Fixtures.snapshot(replayID: 1, hasContents: true)
        let leaf2 = Fixtures.snapshot(replayID: 2, hasContents: true)
        let containerA = Fixtures.snapshot(replayID: 3, children: [leaf1, leaf2])
        let leaf3 = Fixtures.snapshot(replayID: 4, hasContents: true)
        let root = Fixtures.snapshot(replayID: 5, hasContents: true, children: [containerA, leaf3])

        // when
        let result = root.flattened()

        // then
        #expect(result.map(\.replayID) == [5, 1, 2, 4])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func flattenedSortsSiblingsByZPosition() {
        // given
        let child1 = Fixtures.snapshot(replayID: 1, zPosition: 1, hasContents: true)
        let child2 = Fixtures.snapshot(replayID: 2, zPosition: -1, hasContents: true)
        let child3 = Fixtures.snapshot(replayID: 3, zPosition: 0, hasContents: true)
        let parent = Fixtures.snapshot(replayID: 0, hasContents: true, children: [child1, child2, child3])

        // when
        let result = parent.flattened()

        // then
        #expect(result.map(\.replayID) == [0, 2, 3, 1])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func flattenedStableSortsEqualZPosition() {
        // given
        let child1 = Fixtures.snapshot(replayID: 1, zPosition: 0, hasContents: true)
        let child2 = Fixtures.snapshot(replayID: 2, zPosition: 1, hasContents: true)
        let child3 = Fixtures.snapshot(replayID: 3, zPosition: 0, hasContents: true)
        let child4 = Fixtures.snapshot(replayID: 4, zPosition: 1, hasContents: true)
        let parent = Fixtures.snapshot(replayID: 0, hasContents: true, children: [child1, child2, child3, child4])

        // when
        let result = parent.flattened()

        // then
        #expect(result.map(\.replayID) == [0, 1, 3, 2, 4])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func flattenedExcludesContainers() {
        // given
        let leaf1 = Fixtures.snapshot(replayID: 1, hasContents: true)
        let leaf2 = Fixtures.snapshot(replayID: 2, hasContents: true)
        let container = Fixtures.snapshot(replayID: 3, children: [leaf1, leaf2])

        // when
        let result = container.flattened()

        // then
        #expect(result.map(\.replayID) == [1, 2])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func flattenedExcludesDeeplyNestedContainers() {
        // given
        let leaf = Fixtures.snapshot(replayID: 1, hasContents: true)
        let container2 = Fixtures.snapshot(replayID: 2, children: [leaf])
        let container1 = Fixtures.snapshot(replayID: 3, children: [container2])
        let root = Fixtures.snapshot(replayID: 4, children: [container1])

        // when
        let result = root.flattened()

        // then
        #expect(result.map(\.replayID) == [1])
    }
}
#endif
