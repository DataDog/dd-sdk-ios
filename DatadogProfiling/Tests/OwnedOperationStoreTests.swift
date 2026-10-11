/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
@_spi(Internal) import DatadogInternal
import TestUtilities
@testable import DatadogProfiling

final class OwnedOperationStoreTests: XCTestCase {
    private final class OriginalFeature: DatadogFeature, RUMOperationOriginProviding {
        static let name = "rum"
        let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
        var operationOrigin: RUMOperationOrigin?
        let monitor = NSObject()
        var sessionActive = true
        func isOperationMonitor(_ monitor: AnyObject) -> Bool { self.monitor === monitor }
        func isOperationSessionActive(start: Date, lastInteraction: Date) -> Bool { sessionActive }
    }

    private final class Fixture {
        let feature = OriginalFeature()
        let core: SingleFeatureCoreMock<OriginalFeature>
        let origin: RUMOperationOrigin
        let date = Date(timeIntervalSince1970: 100)
        init(sessionID: String = "session") {
            core = SingleFeatureCoreMock(feature: feature)
            origin = RUMOperationOrigin(core: core, owner: RUMContextHandoff.Owner())
            feature.operationOrigin = origin
            origin.attach(feature: feature, monitor: feature.monitor)
            origin.setSession(sessionID)
            origin.updateSession(sessionID, start: date, lastInteraction: date)
        }
        func ownership(_ sessionID: String = "session") throws -> RUMOperationOwnership {
            try XCTUnwrap(origin.ownership(for: sessionID))
        }
        func message(_ ownership: RUMOperationOwnership, id: String = "start", name: String = "operation",
                     key: String? = nil, step: RUMVitalOperationStepEvent.Vital.StepType = .start,
                     date: Date? = nil, attributes: [AttributeKey: AttributeValue] = [:]) -> OwnedOperationMessage {
            OwnedOperationMessage(ownership: ownership, attributes: attributes,
                operation: Vital(id: id, name: name, operationKey: key, stepType: step, date: date ?? self.date))
        }
    }

    func testTupleIdentitySeparatesLegacyStringCollisionsAndOptionalKeys() throws {
        let fixture = Fixture()
        let ownership = try fixture.ownership()
        let store = OwnedOperationStore { _ in }
        XCTAssertTrue(store.prepare(ownership))
        let inputs: [(String, String?, String)] = [
            ("a-b", "c", "first"), ("a", "b-c", "second"),
            ("empty", nil, "nil"), ("empty", "", "empty")
        ]
        for (name, key, id) in inputs {
            store.start(fixture.message(ownership, id: id, name: name, key: key))
        }
        XCTAssertEqual(Set(store.values.map(\.id)), Set(inputs.map { $0.2 }))
    }

    func testSameTupleKeepsLatestStartAndOriginalStartDateAcrossSelectedViews() throws {
        let fixture = Fixture()
        let ownership = try fixture.ownership()
        let store = OwnedOperationStore { _ in }
        XCTAssertTrue(store.prepare(ownership))
        store.start(fixture.message(ownership, id: "older"))
        let later = fixture.date.addingTimeInterval(2)
        store.start(fixture.message(ownership, id: "latest", date: later))
        let end = fixture.message(ownership, id: "end", step: .end, date: later.addingTimeInterval(3),
                                  attributes: [RUMCoreContext.IDs.viewID: ["view-B"]])
        XCTAssertTrue(store.end(end))
        store.installCorrelation(from: end)
        let vital = try XCTUnwrap(store.values.first)
        XCTAssertEqual(vital.id, "latest")
        XCTAssertEqual(vital.date, later)
        XCTAssertEqual(vital.duration, 3_000_000_000)
        XCTAssertEqual(store.values.count, 1)
        XCTAssertTrue(store.correlation?.ownership === ownership)
    }

    func testOrphanEndDoesNotCreateAStartOrProfileOperation() throws {
        let fixture = Fixture()
        let ownership = try fixture.ownership()
        let store = OwnedOperationStore { _ in }
        XCTAssertTrue(store.prepare(ownership))
        XCTAssertFalse(store.end(fixture.message(ownership, step: .end)))
        XCTAssertTrue(store.isEmpty)
        XCTAssertFalse(store.hasStarts)
    }

    func testDifferentOwnersWithTheSameTupleCannotEndEachOther() throws {
        let first = Fixture(), second = Fixture()
        let a = try first.ownership(), b = try second.ownership()
        let store = OwnedOperationStore { _ in }
        XCTAssertTrue(store.prepare(a)); XCTAssertTrue(store.prepare(b))
        store.start(first.message(a, id: "A"))
        XCTAssertFalse(store.end(second.message(b, step: .end)))
        store.start(second.message(b, id: "B"))
        XCTAssertTrue(store.end(second.message(b, step: .end, date: second.date.addingTimeInterval(1))))
        XCTAssertEqual(store.values.count, 2)
        XCTAssertNil(store.values.first { $0.id == "A" }?.duration)
        XCTAssertEqual(store.values.first { $0.id == "B" }?.duration, 1_000_000_000)
    }

    func testQueuedOriginalRetirementCannotEraseReplacementRecordsOrStamp() throws {
        let first = Fixture(), second = Fixture()
        let a = try first.ownership(), b = try second.ownership()
        var queued: [RUMOperationOwnership] = []
        let store = OwnedOperationStore { queued.append($0) }
        XCTAssertTrue(store.prepare(a))
        store.start(first.message(a, id: "A"))
        store.installCorrelation(from: first.message(a, attributes: [RUMCoreContext.IDs.viewID: ["A"]]))
        first.origin.retire()
        XCTAssertEqual(queued.count, 1)
        XCTAssertTrue(store.prepare(b))
        store.start(second.message(b, id: "B"))
        let fresh = second.message(b, attributes: [RUMCoreContext.IDs.viewID: ["B"]])
        var attributes = fresh.attributes
        store.installCorrelation(from: fresh)
        store.retire(queued[0], attributes: &attributes)
        XCTAssertEqual(store.values.map(\.id), ["B"])
        XCTAssertTrue(store.correlation?.ownership === b)
        XCTAssertEqual(attributes[RUMCoreContext.IDs.viewID] as? [String], ["B"])
    }

    func testInvalidationFiltersOnlyInstalledKeysBeforeClearingStamp() throws {
        let fixture = Fixture()
        let ownership = try fixture.ownership()
        let store = OwnedOperationStore { _ in }
        XCTAssertTrue(store.prepare(ownership))
        let message = fixture.message(ownership, attributes: [RUMCoreContext.IDs.sessionID: "original"])
        store.installCorrelation(from: message)
        var attributes: [AttributeKey: AttributeValue] = message.attributes
        attributes["unrelated"] = "preserved"
        fixture.origin.retire()
        store.pruneInvalid(attributes: &attributes)
        XCTAssertNil(attributes[RUMCoreContext.IDs.sessionID])
        XCTAssertEqual(attributes["unrelated"] as? String, "preserved")
        XCTAssertNil(store.correlation)
    }

    func testLaterLegacyAssignmentCannotBeErasedByOldRetirement() throws {
        let fixture = Fixture()
        let ownership = try fixture.ownership()
        let store = OwnedOperationStore { _ in }
        XCTAssertTrue(store.prepare(ownership))
        store.start(fixture.message(ownership))
        store.installCorrelation(from: fixture.message(ownership, attributes: [RUMCoreContext.IDs.viewID: ["old"]]))
        store.didAssignLegacyAttributes()
        var attributes: [AttributeKey: AttributeValue] = [RUMCoreContext.IDs.viewID: ["legacy"]]
        fixture.origin.retire()
        store.retire(ownership, attributes: &attributes)
        XCTAssertEqual(attributes[RUMCoreContext.IDs.viewID] as? [String], ["legacy"])
        XCTAssertNil(store.correlation)
    }

    func testUnchangedValidAttributesKeepTheirStampAndIdleSubscription() throws {
        let fixture = Fixture()
        let ownership = try fixture.ownership()
        var retired: [RUMOperationOwnership] = []
        let store = OwnedOperationStore { retired.append($0) }
        XCTAssertTrue(store.prepare(ownership))
        let message = fixture.message(ownership, attributes: [RUMCoreContext.IDs.sessionID: "original"])
        store.installCorrelation(from: message)
        let generation = try XCTUnwrap(store.correlation).generation
        var attributes = message.attributes
        store.removeRecords(preservingOngoing: false)
        store.pruneInvalid(attributes: &attributes)
        XCTAssertEqual(store.correlation?.generation, generation)
        fixture.origin.retire()
        XCTAssertEqual(retired.count, 1)
        store.retire(retired[0], attributes: &attributes)
        XCTAssertTrue(attributes.isEmpty)
    }

    func testSessionRolloverRetiresOriginalWithoutBorrowingNewSession() throws {
        let fixture = Fixture()
        let original = try fixture.ownership()
        var retired: [RUMOperationOwnership] = []
        let store = OwnedOperationStore { retired.append($0) }
        XCTAssertTrue(store.prepare(original))
        store.start(fixture.message(original))
        fixture.origin.setSession("new")
        fixture.origin.updateSession("new", start: fixture.date, lastInteraction: fixture.date)
        let replacement = try fixture.ownership("new")
        XCTAssertFalse(original.isValid)
        XCTAssertTrue(replacement.isValid)
        XCTAssertEqual(retired.count, 1)
        XCTAssertFalse(store.prepare(original))
        XCTAssertTrue(store.prepare(replacement))
        var attributes: [AttributeKey: AttributeValue] = [:]
        store.retire(original, attributes: &attributes)
        XCTAssertTrue(store.isEmpty)
    }

    func testRecentOngoingPredicateAndCleanupRemainStepTypeAware() throws {
        let fixture = Fixture()
        let ownership = try fixture.ownership()
        let store = OwnedOperationStore { _ in }
        XCTAssertTrue(store.prepare(ownership))
        store.start(fixture.message(ownership, id: "old", name: "old", date: fixture.date))
        store.start(fixture.message(ownership, id: "recent", name: "recent", date: fixture.date.addingTimeInterval(70)))
        XCTAssertTrue(store.canExtend(at: fixture.date.addingTimeInterval(80), cutOff: 60))
        store.removeRecords(preservingOngoing: true)
        XCTAssertEqual(store.values.count, 2, "No invented per-entry TTL removes the older start")
        XCTAssertFalse(store.canExtend(at: fixture.date.addingTimeInterval(130), cutOff: 60))
        store.removeRecords(preservingOngoing: false)
        XCTAssertTrue(store.isEmpty)
    }
}
#endif
