/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import XCTest

@MainActor
final class ProbeSceneRegistryTests: XCTestCase {
    func testRegistersAndResolvesScenesByExactLogicalAndNativeIdentity() throws {
        let registry = ProbeSceneRegistry()
        let windowA = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let windowB = UIWindow(frame: CGRect(x: 400, y: 0, width: 400, height: 800))

        let handleA = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: windowA,
                currentRoute: ["home"]
            )
        )
        let handleB = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-B",
                nativeSceneID: "native-B",
                window: windowB,
                currentRoute: ["home", "detail-1"]
            )
        )

        XCTAssertEqual(registry.handle(logicalSceneID: "scene-A"), handleA)
        XCTAssertEqual(registry.handle(logicalSceneID: "scene-B"), handleB)
        XCTAssertEqual(
            registry.snapshot(nativeSceneID: "native-A")?.logicalSceneID,
            "scene-A"
        )
        XCTAssertEqual(
            registry.snapshot(nativeSceneID: "native-B")?.currentRoute,
            ["home", "detail-1"]
        )
        XCTAssertTrue(registry.window(for: handleA) === windowA)
        XCTAssertTrue(registry.window(for: handleB) === windowB)
    }

    func testRejectsNativeAliasAndConnectedLogicalRemap() throws {
        let registry = ProbeSceneRegistry()
        let windowA = UIWindow()
        let windowB = UIWindow()

        _ = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: windowA,
                currentRoute: ["home"]
            )
        )

        XCTAssertEqual(
            registry.register(
                logicalSceneID: "scene-B",
                nativeSceneID: "native-A",
                window: windowB,
                currentRoute: ["home"]
            ),
            .rejected(
                reason: "native scene native-A is already registered as scene-A"
            )
        )
        XCTAssertEqual(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-B",
                window: windowB,
                currentRoute: ["home"]
            ),
            .rejected(
                reason: "logical scene scene-A is already connected as native-A"
            )
        )
    }

    func testDisconnectInvalidatesStaleHandleAndReconnectsAtNextGeneration() throws {
        let registry = ProbeSceneRegistry()
        let firstWindow = UIWindow()
        let firstHandle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: firstWindow,
                currentRoute: ["home", "detail-1"]
            )
        )
        XCTAssertNotNil(registry.markReady(firstHandle))

        let disconnected = try XCTUnwrap(registry.disconnect(firstHandle))
        XCTAssertEqual(disconnected.readiness, .disconnected)
        XCTAssertEqual(disconnected.disconnectGeneration, 1)
        XCTAssertFalse(disconnected.hasWindow)
        XCTAssertNil(registry.handle(logicalSceneID: "scene-A"))
        XCTAssertNil(registry.updateRoute(["home"], for: firstHandle))

        let secondWindow = UIWindow()
        let secondHandle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: secondWindow,
                currentRoute: ["home"]
            )
        )

        XCTAssertEqual(secondHandle.disconnectGeneration, 1)
        XCTAssertEqual(
            registry.snapshot(logicalSceneID: "scene-A")?.readiness,
            .attached
        )
        XCTAssertNotNil(registry.markReady(secondHandle))
        XCTAssertEqual(
            registry.snapshot(logicalSceneID: "scene-A")?.readiness,
            .ready
        )
        XCTAssertTrue(registry.window(for: secondHandle) === secondWindow)
    }

    func testDisconnectedLogicalSceneCanAdoptANewNativeSession() throws {
        let registry = ProbeSceneRegistry()
        let firstHandle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A1",
                window: UIWindow(),
                currentRoute: ["home"]
            )
        )
        XCTAssertNotNil(registry.disconnect(firstHandle))

        let secondHandle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A2",
                window: UIWindow(),
                currentRoute: ["home"]
            )
        )

        XCTAssertEqual(secondHandle.nativeSceneID, "native-A2")
        XCTAssertEqual(secondHandle.disconnectGeneration, 1)
        XCTAssertNil(registry.snapshot(nativeSceneID: "native-A1"))
        XCTAssertEqual(
            registry.snapshot(nativeSceneID: "native-A2")?.logicalSceneID,
            "scene-A"
        )
    }

    func testRegistryDoesNotRetainWindows() throws {
        let registry = ProbeSceneRegistry()
        var window: UIWindow? = UIWindow()
        weak var weakWindow = window
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: try XCTUnwrap(window),
                currentRoute: ["home"]
            )
        )

        window = nil

        XCTAssertNil(weakWindow)
        XCTAssertNil(registry.window(for: handle))
        XCTAssertEqual(
            registry.snapshot(logicalSceneID: "scene-A")?.hasWindow,
            false
        )
    }

    func testPresentationRouteAndFutureExecutionContextStaySceneLocal() throws {
        let registry = ProbeSceneRegistry()
        let handleA = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: UIWindow(),
                currentRoute: ["home"]
            )
        )
        let handleB = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-B",
                nativeSceneID: "native-B",
                window: UIWindow(),
                currentRoute: ["home"]
            )
        )
        let presentation = ProbeScenePresentation(
            activationState: .foregroundActive,
            geometry: ProbeGeometry(x: 10, y: 20, width: 600, height: 700),
            horizontalSizeClass: "regular",
            verticalSizeClass: "compact"
        )

        XCTAssertNotNil(registry.updatePresentation(presentation, for: handleA))
        XCTAssertNotNil(
            registry.updateRoute(["home", "detail-2"], for: handleA)
        )
        XCTAssertNotNil(
            registry.associateFutureExecutionContextID(
                "future-window-A",
                with: handleA
            )
        )

        let snapshotA = try XCTUnwrap(
            registry.snapshot(logicalSceneID: "scene-A")
        )
        let snapshotB = try XCTUnwrap(
            registry.snapshot(logicalSceneID: "scene-B")
        )
        XCTAssertEqual(snapshotA.presentation, presentation)
        XCTAssertEqual(snapshotA.currentRoute, ["home", "detail-2"])
        XCTAssertEqual(
            snapshotA.futureExecutionContextID,
            "future-window-A"
        )
        XCTAssertEqual(snapshotB.currentRoute, ["home"])
        XCTAssertNil(snapshotB.futureExecutionContextID)
        XCTAssertEqual(snapshotB, registry.snapshot(nativeSceneID: "native-B"))
        XCTAssertNotEqual(handleA, handleB)
    }

    func testExactNativeDisconnectDoesNotAffectPeerScene() throws {
        let registry = ProbeSceneRegistry()
        let windowA = UIWindow()
        let windowB = UIWindow()
        let handleA = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: windowA,
                currentRoute: ["home"]
            )
        )
        let handleB = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-B",
                nativeSceneID: "native-B",
                window: windowB,
                currentRoute: ["home", "detail-1"]
            )
        )
        XCTAssertNotNil(registry.markReady(handleA))
        XCTAssertNotNil(registry.markReady(handleB))

        XCTAssertNotNil(registry.disconnect(nativeSceneID: "native-A"))

        XCTAssertNil(registry.handle(logicalSceneID: "scene-A"))
        XCTAssertEqual(registry.handle(logicalSceneID: "scene-B"), handleB)
        XCTAssertEqual(
            registry.snapshot(logicalSceneID: "scene-B")?.readiness,
            .ready
        )
        XCTAssertEqual(
            registry.snapshot(logicalSceneID: "scene-B")?.currentRoute,
            ["home", "detail-1"]
        )
    }

    private func registeredHandle(
        _ result: ProbeSceneRegistrationResult
    ) throws -> ProbeSceneHandle {
        guard case .registered(let handle) = result else {
            if case .rejected(let reason) = result {
                XCTFail("registration rejected: \(reason)")
            }
            throw NSError(
                domain: "ProbeSceneRegistryTests",
                code: 1
            )
        }
        return handle
    }
}
