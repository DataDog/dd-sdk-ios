/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import QuartzCore

@testable import DatadogSessionReplay

@MainActor
struct CALayerReplayIDTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func autoincrementingGeneratorAssignsSequentialIDsToLayers() {
        CALayer.withReplayIDGenerator(.autoincrementing) {
            let layer1 = CALayer()
            let layer2 = CALayer()
            let layer3 = CALayer()

            let id1 = layer1.replayID
            let id2 = layer2.replayID
            let id3 = layer3.replayID

            #expect(id1 == 0)
            #expect(id2 == 1)
            #expect(id3 == 2)

            // Stable on repeated access
            #expect(layer1.replayID == id1)
            #expect(layer2.replayID == id2)
            #expect(layer3.replayID == id3)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func replayIDIsCachedAndGeneratorInvokedOnlyOncePerLayer() {
        var calls = 0
        var counter: Int64 = 42
        let generator = ReplayIDGenerator {
            calls += 1
            let id = counter
            counter = counter &+ 1
            return id
        }

        CALayer.withReplayIDGenerator(generator) {
            let layer = CALayer()

            let first = layer.replayID
            let second = layer.replayID

            #expect(first == 42)
            #expect(second == 42)
            #expect(calls == 1)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func taskLocalGeneratorOverridesWithinScopeAndRestoresAfter() {
        var outerCounter: Int64 = 10
        let outerGenerator = ReplayIDGenerator {
            let id = outerCounter
            outerCounter = outerCounter &+ 1
            return id
        }

        var innerCounter: Int64 = 100
        let innerGenerator = ReplayIDGenerator {
            let id = innerCounter
            innerCounter = innerCounter &+ 1
            return id
        }

        CALayer.withReplayIDGenerator(outerGenerator) {
            let before = CALayer()
            #expect(before.replayID == 10)

            CALayer.withReplayIDGenerator(innerGenerator) {
                let inside = CALayer()
                #expect(inside.replayID == 100)
            }

            let after = CALayer()
            #expect(after.replayID == 11)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func sameLayerKeepsIDAcrossGeneratorOverrides() {
        var outerCounter: Int64 = 7
        let outerGenerator = ReplayIDGenerator {
            let id = outerCounter
            outerCounter = outerCounter &+ 1
            return id
        }

        var innerCounter: Int64 = 100
        let innerGenerator = ReplayIDGenerator {
            let id = innerCounter
            innerCounter = innerCounter &+ 1
            return id
        }

        CALayer.withReplayIDGenerator(outerGenerator) {
            let layer = CALayer()
            let initial = layer.replayID
            #expect(initial == 7)

            CALayer.withReplayIDGenerator(innerGenerator) {
                // Accessing again should not change the cached ID
                let again = layer.replayID
                #expect(again == initial)
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func autoincrementingGeneratorWrapsToZeroAfterInt32Max() {
        var currentID = Int64(Int32.max - 1)
        let maxID = Int64(Int32.max)
        let generator = ReplayIDGenerator {
            let id = currentID
            currentID = currentID < maxID ? (currentID + 1) : 0
            return id
        }

        CALayer.withReplayIDGenerator(generator) {
            let layer1 = CALayer()
            let layer2 = CALayer()
            let layer3 = CALayer()

            #expect(layer1.replayID == Int64(Int32.max - 1))
            #expect(layer2.replayID == Int64(Int32.max))
            #expect(layer3.replayID == 0)
        }
    }
}
#endif
