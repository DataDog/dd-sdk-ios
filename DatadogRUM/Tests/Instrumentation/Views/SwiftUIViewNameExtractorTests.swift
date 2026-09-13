/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import SwiftUI
@testable import DatadogRUM
@testable import DatadogInternal

class SwiftUIViewNameExtractorTests: XCTestCase {
    var extractor: SwiftUIReflectionBasedViewNameExtractor! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        extractor = SwiftUIReflectionBasedViewNameExtractor()
    }

    override func tearDown() {
        extractor = nil
        super.tearDown()
    }

    // MARK: - View Name Extraction Tests
    func testViewNameExtraction() {
        let testCases: [(String, String?)] = [
            // Format: (input, expectedExtractedName)
            ("LazyView<ViewType>", "ViewType"),
            ("SheetContent<Text>", "Text"),
            ("Optional<Text>", "Text"),
            ("Optional<ViewType>", "ViewType"),
            ("ParameterizedLazyView<String, ViewType>", "ViewType"),
            ("ParameterizedLazyView<String, ViewType>(value: \"xxx\", content: (Function))", "ViewType"),
            ("ViewType.Type", "ViewType"),
            ("SheetContent<ViewType>", "ViewType"),
            ("ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ViewType>>>>", "ViewType"),
            ("ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ContainerType<ViewType>>>>>", "ViewType"),
            ("DetailView", "DetailView")
        ]

        for (input, expected) in testCases {
            let result = extractor.extractViewName(from: input)
            XCTAssertEqual(result, expected, "Failed to extract from: \(input)")
        }
    }

    func testFallbackViewNameExtraction() {
        let testCases: [(String, String)] = [
            // Format: (input, expectedExtractedName)
            // Hosting Controller cases
            ("UIHostingController<HomeView>", "HomeView"),
            ("UIHostingController<AnyView>", "UIHostingController<AnyView>"),
            ("UIHostingController<ModifiedContent<ModifiedContent<Element, NavigationColumnModifier>, StyleContextWriter<SidebarStyleContext>>>", "AutoTracked_HostingController_Fallback"),
            // Navigation Stack Hosting Controller cases
            ("NavigationStackHostingController<DetailView>", "DetailView"),
            ("NavigationStackHostingController<AnyView>", "NavigationStackHostingController<AnyView>"),
            ("NavigationStackHostingController<ModifiedContent<ModifiedContent<Element, NavigationColumnModifier>, StyleContextWriter<SidebarStyleContext>>>", "AutoTracked_NavigationStackController_Fallback")
        ]

        for (input, expected) in testCases {
            // Use the internal method directly
            let result = extractor.extractFallbackViewName(from: input)
            XCTAssertEqual(result, expected, "Failed to extract fallback name from: \(input)")
        }
    }

    // MARK: - SwiftUIViewPath Tests
    func testSwiftUIViewPathComponents() {
        // HostingController cases
        XCTAssertEqual(
            SwiftUIViewPath.hostingControllerModifiedContent.pathComponents,
            [.host, .rootView, .content, .storage, .view]
        )
        XCTAssertEqual(
            SwiftUIViewPath.hostingControllerRootView.pathComponents,
            [.host, .rootView, .content, .storage, .view, .content, .storage, .view, .content, .content]
        )
        XCTAssertEqual(
            SwiftUIViewPath.hostingControllerBase.pathComponents,
            [.host, .rootView]
        )
        // NavigationStack cases
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackBase.pathComponents,
            [.host, .rootView, .storage, .view, .content, .content, .content]
        )
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackContent.pathComponents,
            [.host, .rootView, .storage, .view, .content, .content, .content, .content, .list, .item, .type]
        )
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackAnyView.pathComponents,
            [.host, .rootView, .storage, .view, .content, .content, .content, .root]
        )
        // Modal case
        XCTAssertEqual(
            SwiftUIViewPath.sheetContent.pathComponents,
            [.host, .rootView, .storage, .view, .content]
        )
    }

    // MARK: - Controller Detection Tests
    func testDetectControllerType() {
        // Define test cases with controller, class name and expected controller type
        let testCases: [(String, ControllerType)] = [
            // Format: (controller, className, expectedType)
            ("_TtGC7SwiftUI19UIHostingController", .hostingController),
            ("SwiftUI.UIKitNavigationController", .navigationStackHostingController),
            ("NavigationStackHostingController", .navigationStackHostingController),
            ("_TtGC7SwiftUI29PresentationHostingController", .modal),
            ("UIViewController", .unknown)
        ]

        for (className, expectedType) in testCases {
            XCTAssertEqual(ControllerType(from: className), expectedType, "Controller type detection failed for: \(className)")
        }
    }

    func testShouldSkipViewController() {
        let navigationController = UINavigationController()
        let mockViewController = UIViewController()

        // Test cases with controller and class name
        let testCases: [(UIViewController, String, Bool)] = [
            // Format: (controller, className, expectedShouldSkipResult)
            // TabBarController cases
            (mockViewController, "SwiftUI.UIKitTabBarController", true),
            (mockViewController, "SwiftUI.TabHostingController", true),
            (mockViewController, "_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_", true),
            // NavigationController case
            (navigationController, navigationController.canonicalClassName, true),
            // Other ViewControllers cases
            (mockViewController, "SwiftUI.NotifyingMulticolumnSplitViewController", true),
            (mockViewController, mockViewController.canonicalClassName, false),
        ]

        for (controller, className, expectedResult) in testCases {
            let result = extractor.shouldSkipViewController(viewController: controller, className: className)
            XCTAssertEqual(result, expectedResult, "Skip logic failed for \(className)")
        }
    }

    func testExtractNameFilteringForUIKitControllers() {
        let tabbar = UITabBarController()
        let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        let splitViewController = UISplitViewController()

        // Should return nil for UIKit bundle controllers
        XCTAssertNil(extractor.extractName(from: tabbar))
        XCTAssertNil(extractor.extractName(from: pageViewController))
        XCTAssertNil(extractor.extractName(from: splitViewController))

        let hostingController = UIHostingController(rootView: EmptyView())
        XCTAssertNotNil(hostingController)
    }
}

#if os(iOS) || os(visionOS)
private final class RUMOccurrenceIdentityGenerator {
    private var identities: [String]
    private(set) var invocationCount = 0

    init(_ identities: [String]) {
        self.identities = identities
    }

    func next() -> String {
        invocationCount += 1
        guard !identities.isEmpty else {
            return "unexpected-extra-identity"
        }
        return identities.removeFirst()
    }
}

class RUMViewTrackingStateTests: XCTestCase {
    private let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
    private let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
    private let identity = "stable-identity"

    func testWhenViewAppearsBeforeWindowAttaches_itStartsAfterAttachment() {
        let state = RUMViewTrackingState(identity: identity)

        XCTAssertEqual(state.appear(), [])
        XCTAssertEqual(
            state.update(attachment: .attached(sceneA)),
            [.start(identity: identity, sceneIdentifier: sceneA)]
        )
    }

    func testWhenWindowAttachesBeforeViewAppears_itStartsOnAppearance() {
        let state = RUMViewTrackingState(identity: identity)

        XCTAssertEqual(state.update(attachment: .attached(sceneA)), [])
        XCTAssertEqual(
            state.appear(),
            [.start(identity: identity, sceneIdentifier: sceneA)]
        )
    }

    func testWhenTraitBackedViewMountsBeforeAppearance_itStartsOnce() {
        let state = RUMViewTrackingState(identity: identity)

        XCTAssertEqual(
            state.mount(in: sceneA),
            [.start(identity: identity, sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.appear(), [])
        XCTAssertEqual(state.mount(in: sceneA), [])
    }

    func testWhenMountedViewDisappears_itStopsTheMountedScene() {
        let state = RUMViewTrackingState(identity: identity)

        _ = state.mount(in: sceneA)

        XCTAssertEqual(
            state.disappear(),
            [.stop(identity: identity, sceneIdentifier: sceneA)]
        )
    }

    func testWhenRetainedReaderUpdatesAfterDisappearance_itDoesNotRestartView() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.mountFromReader(in: sceneA)
        _ = state.disappear()

        XCTAssertEqual(state.mountFromReader(in: sceneA), [])
        XCTAssertFalse(state.isAppeared)
        XCTAssertNil(state.activeLifecycleGeneration)
    }

    func testWhenInactiveViewReconnects_readerMountWaitsForSemanticAppearance() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.mountFromReader(in: sceneA)
        _ = state.disappear()
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))

        XCTAssertEqual(state.mountFromReader(in: sceneA), [])
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertFalse(state.isAppeared)
        XCTAssertNil(state.activeLifecycleGeneration)
        XCTAssertEqual(
            state.appear(),
            [.start(identity: identity, sceneIdentifier: sceneA)]
        )
    }

    func testWhenDisconnectedStateReceivesStaleInitialTrait_itWaitsForResolvedReaderMount() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.mountFromReader(in: sceneA)
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))

        XCTAssertEqual(state.mountFromInitialTrait(in: sceneA), [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertNil(state.activeLifecycleGeneration)

        XCTAssertEqual(
            state.mountFromReader(in: sceneB),
            [.start(identity: identity, sceneIdentifier: sceneB)]
        )
    }

    func testWhenMountedViewMovesToAnotherScene_itMigratesOnce() {
        let state = RUMViewTrackingState(identity: identity)

        _ = state.mount(in: sceneA)

        XCTAssertEqual(
            state.mount(in: sceneB),
            [
                .stop(identity: identity, sceneIdentifier: sceneA),
                .start(identity: identity, sceneIdentifier: sceneB)
            ]
        )
        XCTAssertEqual(state.appear(), [])
    }

    func testWhenMountedViewDetachesThenDisappears_itStopsTheMountedScene() {
        let state = RUMViewTrackingState(identity: identity)

        _ = state.mount(in: sceneA)

        XCTAssertEqual(state.update(attachment: .detached), [])
        XCTAssertEqual(
            state.disappear(),
            [.stop(identity: identity, sceneIdentifier: sceneA)]
        )
    }

    func testWhenActiveSceneDisconnects_itInvalidatesSilentlyUntilExplicitRemount() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.mount(in: sceneA)
        let revision = state.revision

        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertNil(state.activeLifecycleGeneration)
        XCTAssertEqual(state.lifecycleGeneration, 1)
        XCTAssertEqual(state.revision, revision + 1)

        XCTAssertEqual(state.update(attachment: .attached(sceneA)), [])
        XCTAssertEqual(state.appear(), [])
        XCTAssertEqual(state.disappear(), [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertFalse(state.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertEqual(state.revision, revision + 1)

        XCTAssertEqual(
            state.mount(in: sceneA),
            [.start(identity: identity, sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.lifecycleGeneration, 2)
    }

    func testWhenKeyedSceneDisconnects_itRequiresNewGenerationToRemount() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail-1", generation: 1)
        let replacement = keyedConfiguration("detail-2", generation: 2)
        _ = state.mount(in: sceneA, configuration: initial)

        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertEqual(state.configuration, initial)
        XCTAssertEqual(state.mount(in: sceneA, configuration: initial), [])
        XCTAssertEqual(state.appear(configuration: replacement), [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)

        XCTAssertEqual(
            state.mount(in: sceneB, configuration: replacement),
            [.start(identity: "detail-2", sceneIdentifier: sceneB)]
        )
        XCTAssertEqual(state.configuration, replacement)
        XCTAssertEqual(state.lifecycleGeneration, 2)
        XCTAssertEqual(state.descriptor(for: "detail-2")?.name, "detail-2")
        XCTAssertEqual(state.sceneIdentifier, sceneB)
        XCTAssertEqual(identities.invocationCount, 2)
    }

    func testWhenRetainedSwiftUIViewReappearsAfterNavigation_itStartsANewRUMViewOccurrence() {
        let state = RUMViewTrackingState(identity: identity)

        let firstAppearance = state.mount(in: sceneA)
        let navigationAway = state.disappear()
        let navigationBack = state.appear()

        XCTAssertEqual(
            firstAppearance + navigationAway + navigationBack,
            [
                .start(identity: identity, sceneIdentifier: sceneA),
                .stop(identity: identity, sceneIdentifier: sceneA),
                .start(identity: identity, sceneIdentifier: sceneA)
            ]
        )
        XCTAssertEqual(state.lifecycleGeneration, 2)
    }

    func testWhenKeyedViewReappears_itUsesAFreshCommandIdentity() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let firstConfiguration = keyedConfiguration("home", generation: 1)
        let returnedConfiguration = keyedConfiguration("home", generation: 2)
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )

        let firstAppearance = state.mount(in: sceneA, configuration: firstConfiguration)
        let navigationAway = state.disappear(configuration: firstConfiguration)
        let navigationBack = state.appear(configuration: returnedConfiguration)

        XCTAssertEqual(
            firstAppearance + navigationAway + navigationBack,
            [
                .start(identity: "home-1", sceneIdentifier: sceneA),
                .stop(identity: "home-1", sceneIdentifier: sceneA),
                .start(identity: "home-2", sceneIdentifier: sceneA)
            ]
        )
        XCTAssertEqual(state.lifecycleGeneration, 2)
        XCTAssertEqual(state.disappear(configuration: firstConfiguration), [])
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(
            state.disappear(configuration: returnedConfiguration),
            [.stop(identity: "home-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenAppearedKeyChangesInSameScene_itReplacesTheOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let detail1 = keyedConfiguration("detail-1", generation: 1)
        let detail2 = keyedConfiguration("detail-2", generation: 2)

        XCTAssertEqual(
            state.mount(in: sceneA, configuration: detail1),
            [.start(identity: "detail-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(
            state.reconcile(
                configuration: detail2,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            [
                .replace(
                    oldIdentity: "detail-1",
                    newIdentity: "detail-2",
                    sceneIdentifier: sceneA
                )
            ]
        )
    }

    func testWhenAppearedKeyIsUnchanged_itDoesNotCreateAnotherOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "unused"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail", generation: 1)
        let updatedBinding = keyedConfiguration("detail", generation: 2)
        _ = state.mount(in: sceneA, configuration: initial)

        XCTAssertEqual(
            state.reconcile(
                configuration: updatedBinding,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            []
        )
        XCTAssertEqual(state.configuration, updatedBinding)
        XCTAssertEqual(state.lifecycleGeneration, 1)
    }

    func testWhenSameKeyDescriptorChanges_itAppliesOnlyToTheNextOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let initial = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("detail"),
            bindingGeneration: 1,
            descriptor: .init(
                name: "Detail 1",
                path: "/detail/1",
                attributes: ["screen": "detail-1"]
            )
        )
        let updated = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("detail"),
            bindingGeneration: 2,
            descriptor: .init(
                name: "Detail 2",
                path: "/detail/2",
                attributes: ["screen": "detail-2"]
            )
        )
        _ = state.mount(in: sceneA, configuration: initial)

        XCTAssertEqual(
            state.reconcile(
                configuration: updated,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            []
        )
        XCTAssertEqual(state.descriptor(for: "detail-1")?.name, "Detail 1")
        XCTAssertEqual(state.descriptor(for: "detail-1")?.path, "/detail/1")
        XCTAssertEqual(
            state.descriptor(for: "detail-1")?.attributes["screen"] as? String,
            "detail-1"
        )

        _ = state.disappear(configuration: updated)
        XCTAssertEqual(
            state.appear(configuration: updated),
            [.start(identity: "detail-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.descriptor(for: "detail-2")?.name, "Detail 2")
        XCTAssertEqual(state.descriptor(for: "detail-2")?.path, "/detail/2")
        XCTAssertEqual(
            state.descriptor(for: "detail-2")?.attributes["screen"] as? String,
            "detail-2"
        )
    }

    func testWhenKeyReturnsToEarlierValue_itCreatesAThirdOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1a", "detail-2", "detail-1b"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let first = keyedConfiguration("detail-1", generation: 1)
        let second = keyedConfiguration("detail-2", generation: 2)
        let returned = keyedConfiguration("detail-1", generation: 3)

        let start = state.mount(in: sceneA, configuration: first)
        let replace = state.reconcile(
            configuration: second,
            attachment: .attached(sceneA),
            isAppeared: true
        )
        let replaceAgain = state.reconcile(
            configuration: returned,
            attachment: .attached(sceneA),
            isAppeared: true
        )

        XCTAssertEqual(
            start + replace + replaceAgain,
            [
                .start(identity: "detail-1a", sceneIdentifier: sceneA),
                .replace(
                    oldIdentity: "detail-1a",
                    newIdentity: "detail-2",
                    sceneIdentifier: sceneA
                ),
                .replace(
                    oldIdentity: "detail-2",
                    newIdentity: "detail-1b",
                    sceneIdentifier: sceneA
                )
            ]
        )
        XCTAssertEqual(state.lifecycleGeneration, 3)
    }

    func testWhenKeyChangesWhileDetached_itStopsThenWaitsForAttachment() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let first = keyedConfiguration("detail-1", generation: 1)
        let second = keyedConfiguration("detail-2", generation: 2)
        _ = state.mount(in: sceneA, configuration: first)

        XCTAssertEqual(state.update(configuration: first, attachment: .detached), [])
        XCTAssertEqual(
            state.update(configuration: second, attachment: .detached),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(
            state.update(configuration: second, attachment: .attached(sceneA)),
            [.start(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenKeyAndSceneChangeTogether_itStopsAndStartsInsteadOfReplacing() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-A", "detail-B"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let first = keyedConfiguration("detail-1", generation: 1)
        let second = keyedConfiguration("detail-2", generation: 2)
        _ = state.mount(in: sceneA, configuration: first)

        XCTAssertEqual(
            state.reconcile(
                configuration: second,
                attachment: .attached(sceneB),
                isAppeared: true
            ),
            [
                .stop(identity: "detail-A", sceneIdentifier: sceneA),
                .start(identity: "detail-B", sceneIdentifier: sceneB)
            ]
        )
    }

    func testWhenSameKeyMovesScenes_oldBindingCannotStopMigratedOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-A", "detail-B"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let first = keyedConfiguration("detail", generation: 1)
        let migrated = keyedConfiguration("detail", generation: 2)
        _ = state.mount(in: sceneA, configuration: first)

        XCTAssertEqual(
            state.reconcile(
                configuration: migrated,
                attachment: .attached(sceneB),
                isAppeared: true
            ),
            [
                .stop(identity: "detail-A", sceneIdentifier: sceneA),
                .start(identity: "detail-B", sceneIdentifier: sceneB)
            ]
        )
        XCTAssertEqual(state.disappear(configuration: first), [])
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(
            state.disappear(configuration: migrated),
            [.stop(identity: "detail-B", sceneIdentifier: sceneB)]
        )
    }

    func testWhenKeyedStateReceivesUnversionedLifecycle_itFailsClosed() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let configuration = keyedConfiguration("detail", generation: 1)
        _ = state.mount(in: sceneA, configuration: configuration)

        XCTAssertEqual(state.disappear(), [])
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(
            state.disappear(configuration: configuration),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
    }

    func testWhenOldBindingDisappearsAfterReplacement_itCannotStopNewOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let first = keyedConfiguration("detail-1", generation: 1)
        let second = keyedConfiguration("detail-2", generation: 2)
        _ = state.mount(in: sceneA, configuration: first)
        _ = state.reconcile(
            configuration: second,
            attachment: .attached(sceneA),
            isAppeared: true
        )

        XCTAssertEqual(state.disappear(configuration: first), [])
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(
            state.disappear(configuration: second),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenViewDisappearsBeforeWindowAttaches_itNeverStarts() {
        let state = RUMViewTrackingState(identity: identity)

        XCTAssertEqual(state.appear(), [])
        XCTAssertEqual(state.disappear(), [])
        XCTAssertEqual(state.update(attachment: .attached(sceneA)), [])
    }

    func testWhenAttachedWindowHasNoScene_itPreservesLegacyUnscopedLifecycle() {
        let state = RUMViewTrackingState(identity: identity)

        XCTAssertEqual(state.update(attachment: .attached(nil)), [])
        XCTAssertEqual(
            state.appear(),
            [.start(identity: identity, sceneIdentifier: nil)]
        )
        XCTAssertEqual(
            state.disappear(),
            [.stop(identity: identity, sceneIdentifier: nil)]
        )
    }

    func testWhenAppearedViewTransientlyDetachesAndReattachesSameScene_itDoesNotRestart() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.update(attachment: .attached(sceneA))
        _ = state.appear()

        XCTAssertEqual(state.update(attachment: .detached), [])
        XCTAssertEqual(state.update(attachment: .attached(sceneA)), [])
        XCTAssertEqual(
            state.disappear(),
            [.stop(identity: identity, sceneIdentifier: sceneA)]
        )
    }

    func testWhenAppearedViewDetachesThenDisappears_itStopsOriginalScene() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.update(attachment: .attached(sceneA))
        _ = state.appear()

        XCTAssertEqual(state.update(attachment: .detached), [])
        XCTAssertEqual(
            state.disappear(),
            [.stop(identity: identity, sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.appear(), [])
        XCTAssertEqual(
            state.update(attachment: .attached(sceneB)),
            [.start(identity: identity, sceneIdentifier: sceneB)]
        )
    }

    func testWhenAppearedViewDetachesThenAttachesToAnotherScene_itMigratesOnce() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.update(attachment: .attached(sceneA))
        _ = state.appear()

        XCTAssertEqual(state.update(attachment: .detached), [])
        XCTAssertEqual(
            state.update(attachment: .attached(sceneB)),
            [
                .stop(identity: identity, sceneIdentifier: sceneA),
                .start(identity: identity, sceneIdentifier: sceneB)
            ]
        )
    }

    func testWhenAppearedViewMovesBetweenScenes_itStopsThenStartsWithStableIdentity() {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.update(attachment: .attached(sceneA))
        let initialStart = state.appear()

        XCTAssertEqual(
            initialStart + state.update(attachment: .attached(sceneB)) + state.disappear(),
            [
                .start(identity: identity, sceneIdentifier: sceneA),
                .stop(identity: identity, sceneIdentifier: sceneA),
                .start(identity: identity, sceneIdentifier: sceneB),
                .stop(identity: identity, sceneIdentifier: sceneB)
            ]
        )
        XCTAssertEqual(state.identity, identity)
    }

    func testObserverReportsAttachmentBeforeDetachment() {
        var attachments: [RUMViewTrackingState.Attachment] = []
        let observer = RUMSceneIdentifierReader.ObserverView {
            attachments.append($0)
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        window.addSubview(observer)
        observer.removeFromSuperview()

        XCTAssertEqual(attachments.count, 2)
        guard case .attached = attachments.first else {
            return XCTFail("The observer must report its destination window before detachment")
        }
        XCTAssertEqual(attachments.last, .detached)
    }

    func testObserverTreatsSceneLessWindowAsUnresolvedWhenApplicationSupportsMultipleScenes() {
        XCTAssertEqual(
            RUMSceneIdentifierReader.attachment(
                isAttachedToWindow: true,
                sceneIdentifier: nil,
                applicationSupportsMultipleScenes: true
            ),
            .detached
        )
    }

    func testObserverTreatsUnattachedSceneAsDisconnected() {
        XCTAssertEqual(
            RUMSceneIdentifierReader.attachment(
                isAttachedToWindow: true,
                sceneIdentifier: sceneA,
                applicationSupportsMultipleScenes: true,
                isSceneConnected: false
            ),
            .detached
        )
    }

    func testObserverDoesNotRepeatMountForUnchangedAttachment() {
        var mounts: [RUMSceneIdentifier] = []
        var attachments: [RUMViewTrackingState.Attachment] = []
        let observer = RUMSceneIdentifierReader.ObserverView(
            onChange: { attachments.append($0) },
            onMount: { mounts.append($0) },
            applicationSupportsMultipleScenes: true
        )

        observer.notify(attachment: .attached(sceneA))
        observer.notify(attachment: .attached(sceneA))

        XCTAssertEqual(mounts, [sceneA])
        XCTAssertEqual(attachments, [.attached(sceneA)])
    }

    func testObserverReportsMountAfterSilentSceneDisconnection() {
        var mounts: [RUMSceneIdentifier] = []
        var attachments: [RUMViewTrackingState.Attachment] = []
        let observer = RUMSceneIdentifierReader.ObserverView(
            onChange: { attachments.append($0) },
            onMount: { mounts.append($0) },
            applicationSupportsMultipleScenes: true
        )
        observer.notify(attachment: .attached(sceneA))

        observer.markSceneDisconnected(sceneA)
        observer.notify(attachment: .attached(sceneA))

        XCTAssertEqual(mounts, [sceneA, sceneA])
        XCTAssertEqual(attachments, [.attached(sceneA), .attached(sceneA)])
    }

    func testReaderUpdateRebindsAndReregistersRetainedObserver() {
        var oldAttachments: [RUMViewTrackingState.Attachment] = []
        let observer = RUMSceneIdentifierReader.ObserverView(
            onChange: { oldAttachments.append($0) },
            applicationSupportsMultipleScenes: true
        )
        observer.notify(attachment: .attached(sceneA))
        var registrationCount = 0
        var mounts: [RUMSceneIdentifier] = []
        var reboundAttachments: [RUMViewTrackingState.Attachment] = []
        let reader = RUMSceneIdentifierReader(
            applicationSupportsMultipleScenes: true,
            onCreate: { registeredObserver in
                XCTAssertIdentical(registeredObserver, observer)
                registrationCount += 1
            },
            onMount: { mounts.append($0) },
            onChange: { reboundAttachments.append($0) }
        )

        reader.update(observer: observer)
        observer.notify(attachment: .attached(sceneA))

        XCTAssertEqual(registrationCount, 1)
        XCTAssertEqual(oldAttachments, [.attached(sceneA)])
        XCTAssertEqual(mounts, [sceneA])
        XCTAssertEqual(reboundAttachments, [.detached, .attached(sceneA)])
    }

    func testReaderUpdateReconcilesRetainedObserverWithLatestBinding() {
        var attachmentChanges: [RUMViewTrackingState.Attachment] = []
        let observer = RUMSceneIdentifierReader.ObserverView(
            onChange: { attachmentChanges.append($0) },
            applicationSupportsMultipleScenes: true
        )
        var reconciledGenerations: [UInt64] = []
        var reconciledAttachments: [RUMViewTrackingState.Attachment] = []

        for generation: UInt64 in [1, 2] {
            let reader = RUMSceneIdentifierReader(
                applicationSupportsMultipleScenes: true,
                onReconcile: { attachment in
                    reconciledGenerations.append(generation)
                    reconciledAttachments.append(attachment)
                },
                onChange: { attachmentChanges.append($0) }
            )
            reader.update(observer: observer)
        }

        XCTAssertEqual(reconciledGenerations, [1, 2])
        XCTAssertEqual(reconciledAttachments, [.detached, .detached])
        XCTAssertEqual(attachmentChanges, [.detached])
    }

    private func keyedConfiguration(
        _ key: String,
        generation: UInt64
    ) -> RUMViewTrackingState.Configuration {
        RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey(key),
            bindingGeneration: generation,
            descriptor: .init(name: key, path: "/\(key)", attributes: [:])
        )
    }
}

#if os(iOS)
@MainActor
class RUMSwiftUINavigationOccurrenceSourceTests: XCTestCase {
    private let sceneA = RUMSceneIdentifier(rawValue: "scene-A")

    func testWhenRetainedRouteWasPreviouslyVisible_revealStartsFreshOccurrenceSynchronously() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(state.lifecycleGeneration, 2)
        XCTAssertEqual(state.configuration?.bindingGeneration, 2)
    }

    func testWhenRevealedRouteMountsWithNewSwiftUIState_itAdoptsPublishedOccurrence() {
        let retainedIdentities = RUMOccurrenceIdentityGenerator(
            ["detail-1", "detail-returned"]
        )
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["duplicate"])
        let retainedState = RUMViewTrackingState(
            identity: "retained-fallback",
            occurrenceIdentityGenerator: retainedIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let initial = configuration(key: "detail", generation: 1)
        _ = retainedState.mount(in: sceneA, configuration: initial)
        _ = retainedState.disappear(configuration: initial)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: retainedState,
            configuration: initial,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: retainedState.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("detail"),
                bindingGeneration: 2
            )
        )
        let returned = configuration(key: "detail", generation: 2)
        XCTAssertEqual(
            transitions,
            [.start(identity: "detail-returned", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(retainedState.disappear(configuration: returned), [])

        XCTAssertTrue(
            source.consumeRevealedRoute(
                configuration: returned,
                sceneIdentifier: sceneA,
                into: replacementState
            )
        )
        XCTAssertFalse(retainedState.isAppeared)
        XCTAssertNil(retainedState.activeLifecycleGeneration)
        XCTAssertTrue(replacementState.isAppeared)
        XCTAssertEqual(replacementState.activeLifecycleGeneration, 1)
        XCTAssertEqual(replacementState.appear(configuration: returned), [])
        XCTAssertEqual(
            replacementState.disappear(configuration: returned),
            [.stop(identity: "detail-returned", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(retainedIdentities.invocationCount, 2)
        XCTAssertEqual(replacementIdentities.invocationCount, 0)
    }

    func testWhenRevealedRouteKeepsItsSwiftUIState_consumptionSettlesHandoff() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            _ = state.reconcile(
                configuration: configuration,
                attachment: .attached(sceneIdentifier),
                isAppeared: true
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        let returned = configuration(key: "home", generation: 2)

        XCTAssertFalse(
            source.consumeRevealedRoute(
                configuration: returned,
                sceneIdentifier: sceneA,
                into: state
            )
        )
        XCTAssertEqual(
            state.disappear(configuration: returned),
            [.stop(identity: "home-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(identities.invocationCount, 2)
    }

    func testWhenMultipleRegistrationsCanRevealSameRoute_onlyNewestRegistrationStarts() {
        let olderState = RUMViewTrackingState(
            identity: "older-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(
                ["older-1", "older-2"]
            ).next
        )
        let newerState = RUMViewTrackingState(
            identity: "newer-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(
                ["newer-1", "newer-2"]
            ).next
        )
        let initial = configuration(key: "detail", generation: 1)
        for state in [olderState, newerState] {
            _ = state.mount(in: sceneA, configuration: initial)
            _ = state.disappear(configuration: initial)
            _ = state.update(configuration: initial, attachment: .detached)
        }
        let source = RUMSwiftUINavigationOccurrenceSource()
        let olderRegistration = RUMSwiftUINavigationOccurrenceRegistration()
        let newerRegistration = RUMSwiftUINavigationOccurrenceRegistration()
        var olderTransitions: [RUMViewTrackingState.Transition] = []
        var newerTransitions: [RUMViewTrackingState.Transition] = []
        olderRegistration.rebind(
            to: source,
            state: olderState,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            olderTransitions.append(
                contentsOf: olderState.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }
        newerRegistration.rebind(
            to: source,
            state: newerState,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            newerTransitions.append(
                contentsOf: newerState.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("detail"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(olderTransitions, [])
        XCTAssertEqual(
            newerTransitions,
            [.start(identity: "newer-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenAnotherRouteIsRevealed_pendingHandoffNoLongerSuppressesDisappear() {
        let homeState = RUMViewTrackingState(
            identity: "home-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(
                ["home-1", "home-2"]
            ).next
        )
        let detailState = RUMViewTrackingState(
            identity: "detail-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(
                ["detail-1", "detail-2"]
            ).next
        )
        let initialHome = configuration(key: "home", generation: 1)
        let initialDetail = configuration(key: "detail", generation: 1)
        _ = homeState.mount(in: sceneA, configuration: initialHome)
        _ = homeState.disappear(configuration: initialHome)
        _ = detailState.mount(in: sceneA, configuration: initialDetail)
        _ = detailState.disappear(configuration: initialDetail)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let homeRegistration = RUMSwiftUINavigationOccurrenceRegistration()
        let detailRegistration = RUMSwiftUINavigationOccurrenceRegistration()
        homeRegistration.rebind(
            to: source,
            state: homeState,
            configuration: initialHome,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            _ = homeState.reconcile(
                configuration: configuration,
                attachment: .attached(sceneIdentifier),
                isAppeared: true
            )
        }
        detailRegistration.rebind(
            to: source,
            state: detailState,
            configuration: initialDetail,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            _ = detailState.reconcile(
                configuration: configuration,
                attachment: .attached(sceneIdentifier),
                isAppeared: true
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("detail"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(
            homeState.disappear(configuration: configuration(key: "home", generation: 2)),
            [.stop(identity: "home-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenRouteIsStillActive_revealDoesNotCreateSyntheticOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "unused"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertFalse(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(transitions, [])
        XCTAssertEqual(identities.invocationCount, 1)
        XCTAssertEqual(state.lifecycleGeneration, 1)
    }

    func testWhenRouteHasNeverStarted_revealDoesNotMaterializeIt() {
        let identities = RUMOccurrenceIdentityGenerator(["unused"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "detail", generation: 1)
        _ = state.update(configuration: initial, attachment: .attached(sceneA))
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertFalse(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("detail"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(transitions, [])
        XCTAssertEqual(identities.invocationCount, 0)
        XCTAssertEqual(state.lifecycleGeneration, 0)
    }

    func testWhenRetainedRouteDisconnected_revealWaitsForExplicitRemount() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "unused"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .detached)
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertFalse(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(transitions, [])
        XCTAssertEqual(identities.invocationCount, 1)
        XCTAssertTrue(state.needsReaderRemount)
    }

    func testWhenRetainedRouteReaderIsDetached_revealUsesLastProvenScene() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .detached)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenRetainedRouteReaderIsAttachedWithoutScene_revealStaysUnresolved() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "unused"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .attached(nil))
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .attached(nil)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertFalse(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(transitions, [])
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenRetainedRouteMovesToAnotherScene_revealUsesNewProvenScene() {
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .attached(sceneB))
        _ = state.update(configuration: initial, attachment: .detached)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneB)]
        )
    }

    func testWhenDisconnectedRouteRemountsInAnotherScene_laterRevealUsesNewScene() {
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .detached)
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))

        let remounted = configuration(key: "home", generation: 2)
        XCTAssertEqual(
            state.mountFromReader(in: sceneB, configuration: remounted),
            []
        )
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: remounted,
            attachment: .attached(sceneB)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 3
            )
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneB)]
        )
    }

    func testWhenRegistrationRebindsToAnotherSource_staleSourceCannotRevealRoute() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        let staleSource = RUMSwiftUINavigationOccurrenceSource()
        let currentSource = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: staleSource,
            state: state,
            configuration: initial,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }
        registration.rebind(
            to: currentSource,
            state: state,
            configuration: initial,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertFalse(
            staleSource.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertTrue(
            currentSource.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenTwoWindowsUseTheSameRouteKey_sourceRevealsOnlyItsOwnRegistration() {
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let stateA = RUMViewTrackingState(
            identity: "fallback-a",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(
                ["home-a1", "home-a2"]
            ).next
        )
        let stateB = RUMViewTrackingState(
            identity: "fallback-b",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(
                ["home-b1", "unused"]
            ).next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = stateA.mount(in: sceneA, configuration: initial)
        _ = stateA.disappear(configuration: initial)
        _ = stateA.update(configuration: initial, attachment: .detached)
        _ = stateB.mount(in: sceneB, configuration: initial)
        _ = stateB.disappear(configuration: initial)
        _ = stateB.update(configuration: initial, attachment: .detached)
        let sourceA = RUMSwiftUINavigationOccurrenceSource()
        let sourceB = RUMSwiftUINavigationOccurrenceSource()
        let registrationA = RUMSwiftUINavigationOccurrenceRegistration()
        let registrationB = RUMSwiftUINavigationOccurrenceRegistration()
        var transitionsA: [RUMViewTrackingState.Transition] = []
        var transitionsB: [RUMViewTrackingState.Transition] = []
        registrationA.rebind(
            to: sourceA,
            state: stateA,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            transitionsA.append(
                contentsOf: stateA.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }
        registrationB.rebind(
            to: sourceB,
            state: stateB,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            transitionsB.append(
                contentsOf: stateB.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        XCTAssertTrue(
            sourceA.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(
            transitionsA,
            [.start(identity: "home-a2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(transitionsB, [])
        XCTAssertFalse(stateB.isAppeared)
    }

    func testWhenStateAlreadyConsumedGeneration_duplicateRevealIsRejected() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2", "unused"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .detached)
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: state.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }
        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        guard let current = state.configuration else {
            return XCTFail("Expected the first reveal to update the configuration")
        }
        _ = state.disappear(configuration: current)
        _ = state.update(configuration: current, attachment: .detached)

        XCTAssertFalse(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(identities.invocationCount, 2)
    }

    func testWhenInteractiveRevealIsCancelled_arbiterCreatesNoOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "unused"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .detached)
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: NotificationCenter(),
            coordinatorProvider: { _, _ in coordinator }
        )
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            arbiter.process(
                .reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                ),
                state: state
            ) { transitions.append(contentsOf: $0) }
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(transitions, [])
        XCTAssertEqual(state.configuration, initial)

        coordinator.complete(isCancelled: true)

        XCTAssertEqual(transitions, [])
        XCTAssertEqual(state.configuration, initial)
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenInteractiveRevealCompletes_arbiterStartsReturnedOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        _ = state.update(configuration: initial, attachment: .detached)
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: NotificationCenter(),
            coordinatorProvider: { _, _ in coordinator }
        )
        let source = RUMSwiftUINavigationOccurrenceSource()
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initial,
            attachment: .detached
        ) { configuration, sceneIdentifier in
            arbiter.process(
                .reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                ),
                state: state
            ) { transitions.append(contentsOf: $0) }
        }

        XCTAssertTrue(
            source.revealRetainedRoute(
                occurrenceKey: RUMViewOccurrenceKey("home"),
                bindingGeneration: 2
            )
        )
        XCTAssertEqual(transitions, [])

        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.configuration?.bindingGeneration, 2)
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 2)
    }

    private func configuration(
        key: String,
        generation: UInt64
    ) -> RUMViewTrackingState.Configuration {
        RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey(key),
            bindingGeneration: generation,
            descriptor: .init(name: key, path: "/\(key)", attributes: [:])
        )
    }
}

private final class RUMSwiftUITransitionCoordinatorMock: RUMSwiftUITransitionCoordinating {
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
    var initiallyInteractive: Bool
    var acceptsRegistration: Bool
    private(set) var registrationCount = 0
    private var completions: [(_ isCancelled: Bool) -> Void] = []

    init(initiallyInteractive: Bool = true, acceptsRegistration: Bool = true) {
        self.initiallyInteractive = initiallyInteractive
        self.acceptsRegistration = acceptsRegistration
    }

    func registerCompletion(_ completion: @escaping (_ isCancelled: Bool) -> Void) -> Bool {
        registrationCount += 1
        guard acceptsRegistration else {
            return false
        }
        completions.append(completion)
        return true
    }

    func complete(isCancelled: Bool) {
        completions.last?(isCancelled)
    }

    func complete(registration: Int, isCancelled: Bool) {
        completions[registration](isCancelled)
    }
}

private final class RUMSwiftUITransitionRecorder {
    struct Entry: Equatable {
        let source: String
        let transition: RUMViewTrackingState.Transition
    }

    private(set) var entries: [Entry] = []

    func send(
        source: String,
        transitions: [RUMViewTrackingState.Transition]
    ) {
        entries.append(contentsOf: transitions.map { Entry(source: source, transition: $0) })
    }
}

class RUMSwiftUIInteractiveTransitionArbiterTests: XCTestCase {
    private let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
    private let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
    private let notificationCenter = NotificationCenter()
    private var coordinators: [RUMSceneIdentifier: RUMSwiftUITransitionCoordinatorMock] = [:]
    private lazy var arbiter = RUMSwiftUIInteractiveTransitionArbiter(
        notificationCenter: notificationCenter,
        coordinatorProvider: { [unowned self] sceneIdentifier, _ in
            coordinators[sceneIdentifier]
        }
    )

    func testWhenInteractiveAppearanceIsCancelled_itCreatesNoOccurrence() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(coordinator.registrationCount, 1)
        XCTAssertEqual(recorder.entries, [])
        XCTAssertFalse(state.isAppeared)

        coordinator.complete(isCancelled: true)
        coordinators[sceneA] = nil
        arbiter.process(.disappear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(recorder.entries, [])
        XCTAssertFalse(state.isAppeared)
    }

    func testWhenObserverReregisters_itReplacesRegistrationIdempotently() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        var observedCounts: [Int] = []
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            coordinatorProvider: { _, observers in
                observedCounts.append(observers.count)
                return coordinator
            }
        )
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()
        arbiter.register(observer: observer, for: state)
        arbiter.register(observer: observer, for: state)

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(observedCounts, [1])
        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
    }

    func testWhenCancellationReversalArrivesBeforeCompletion_itCreatesNoOccurrence() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.disappear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertFalse(state.isAppeared)
    }

    func testWhenInteractiveMountIsCancelled_itDoesNotMutateTrackingState() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = RUMViewTrackingState(identity: "candidate")
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.mount(sceneA), state: state) {
            recorder.send(source: "candidate", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
    }

    func testWhenKeyedInitialMountIsCancelled_itCanStartOnTheNextCommittedMount() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["home-1"])
        let state = RUMViewTrackingState(
            identity: "platform-home",
            occurrenceIdentityGenerator: identities.next
        )
        let configuration = keyedConfiguration("home", generation: 1)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .keyedInitialMount(
                configuration: configuration,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(recorder.entries, [])
        XCTAssertNil(state.configuration)
        XCTAssertEqual(identities.invocationCount, 0)

        coordinator.complete(isCancelled: true)
        coordinators[sceneA] = nil
        arbiter.process(
            .keyedInitialMount(
                configuration: configuration,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.configuration, configuration)
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenDisconnectedViewRemountIsDeferred_itStartsAfterSuccessfulCompletion() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = RUMViewTrackingState(identity: "home")
        let recorder = RUMSwiftUITransitionRecorder()
        _ = state.mountFromReader(in: sceneA)
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))

        arbiter.process(.mount(sceneA), state: state) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)

        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertTrue(state.isAppeared)
    }

    func testWhenDeferredReconnectIsCancelled_readerRearmsForNextResolvedMount() {
        let firstCoordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = firstCoordinator
        let state = RUMViewTrackingState(identity: "home")
        let recorder = RUMSwiftUITransitionRecorder()
        let observer = RUMSceneIdentifierReader.ObserverView(
            onChange: { _ in },
            applicationSupportsMultipleScenes: true
        )
        observer.notify(attachment: .attached(sceneA))
        arbiter.register(observer: observer, for: state)
        _ = state.mountFromReader(in: sceneA)
        arbiter.discard(sceneIdentifier: sceneA)
        arbiter.register(observer: observer, for: state)
        observer.onMount = { [unowned self] sceneIdentifier in
            arbiter.process(.mount(sceneIdentifier), state: state) {
                recorder.send(source: "home", transitions: $0)
            }
        }

        observer.notify(attachment: .attached(sceneA))
        firstCoordinator.complete(isCancelled: true)

        let secondCoordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = secondCoordinator
        observer.notify(attachment: .attached(sceneA))
        secondCoordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertTrue(state.isAppeared)
    }

    func testWhenDeferredReconnectDisappears_successLeavesStateReadyForLaterAppearance() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = RUMViewTrackingState(identity: "home")
        let recorder = RUMSwiftUITransitionRecorder()
        _ = state.mountFromReader(in: sceneA)
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))

        arbiter.process(.mount(sceneA), state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.disappear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertFalse(state.isAppeared)

        coordinators[sceneA] = nil
        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
    }

    func testWhenDeferredReconnectDisappearsAndCancels_readerRearms() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = RUMViewTrackingState(identity: "home")
        let recorder = RUMSwiftUITransitionRecorder()
        let observer = RUMSceneIdentifierReader.ObserverView(
            onChange: { _ in },
            applicationSupportsMultipleScenes: true
        )
        observer.notify(attachment: .attached(sceneA))
        arbiter.register(observer: observer, for: state)
        _ = state.mountFromReader(in: sceneA)
        arbiter.discard(sceneIdentifier: sceneA)
        arbiter.register(observer: observer, for: state)
        observer.notify(attachment: .attached(sceneA))

        arbiter.process(.mount(sceneA), state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.disappear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        coordinators[sceneA] = nil
        observer.onMount = { [unowned self] sceneIdentifier in
            arbiter.process(.mount(sceneIdentifier), state: state) {
                recorder.send(source: "home", transitions: $0)
            }
            arbiter.process(.appear, state: state) {
                recorder.send(source: "home", transitions: $0)
            }
        }
        observer.notify(attachment: .attached(sceneA))

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertTrue(state.isAppeared)
    }

    func testProviderUsesMatchingSceneHierarchyWhileNewReaderIsUnattached() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let sceneRootViewController = UIViewController()
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        let provider = RUMSwiftUITransitionCoordinatorProvider(
            sceneViewControllers: { [sceneA] sceneIdentifier in
                XCTAssertEqual(sceneIdentifier, sceneA)
                return [sceneRootViewController]
            },
            controllerCoordinator: { viewController in
                XCTAssertIdentical(viewController, sceneRootViewController)
                return coordinator
            }
        )

        let resolved = provider.coordinator(for: sceneA, observers: [observer])

        XCTAssertEqual(resolved?.identity, coordinator.identity)
    }

    func testProviderDoesNotBorrowSceneTransitionForAttachedUnrelatedReader() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let sceneRootViewController = UIViewController()
        let unrelatedViewController = UIViewController()
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        unrelatedViewController.view.addSubview(observer)
        var didRequestSceneHierarchy = false
        let provider = RUMSwiftUITransitionCoordinatorProvider(
            sceneViewControllers: { _ in
                didRequestSceneHierarchy = true
                return [sceneRootViewController]
            },
            controllerCoordinator: { viewController in
                viewController === sceneRootViewController ? coordinator : nil
            }
        )

        let resolved = provider.coordinator(for: sceneA, observers: [observer])

        XCTAssertNil(resolved)
        XCTAssertFalse(didRequestSceneHierarchy)
    }

    func testWhenAttachmentStartsInteractiveDeferral_followingAppearanceJoinsSameScene() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = RUMViewTrackingState(identity: "home")
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.update(.attached(sceneA)), state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(coordinator.registrationCount, 1)
        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
    }

    func testWhenInteractivePopCompletes_itStopsOutgoingBeforeStartingReturnedOccurrence() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let detail = startedState(identity: "detail", sceneIdentifier: sceneA)
        let home = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: home) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.disappear, state: detail) {
            recorder.send(source: "detail", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "detail",
                    transition: .stop(identity: "detail", sceneIdentifier: sceneA)
                ),
                .init(
                    source: "home",
                    transition: .start(identity: "home", sceneIdentifier: sceneA)
                )
            ]
        )
    }

    func testWhenRetainedViewCompletesTwoReturns_itCreatesANewOccurrenceForEachReturn() {
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.disappear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [
                .start(identity: "home", sceneIdentifier: sceneA),
                .stop(identity: "home", sceneIdentifier: sceneA),
                .start(identity: "home", sceneIdentifier: sceneA)
            ]
        )
    }

    func testWhenCoordinatorIsNotInteractive_itAppliesImmediately() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock(initiallyInteractive: false)
        coordinators[sceneA] = coordinator
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(coordinator.registrationCount, 0)
        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
    }

    func testWhenCoordinatorRejectsRegistration_itAppliesImmediately() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock(acceptsRegistration: false)
        coordinators[sceneA] = coordinator
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }

        XCTAssertEqual(coordinator.registrationCount, 1)
        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
    }

    func testWhenCallbacksRepeatDuringTransition_itCommitsOneOccurrence() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        for _ in 0..<3 {
            arbiter.process(.appear, state: state) {
                recorder.send(source: "home", transitions: $0)
            }
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(coordinator.registrationCount, 1)
        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "home", sceneIdentifier: sceneA)]
        )
    }

    func testWhenTwoScenesTransitionConcurrently_theyResolveIndependently() {
        let coordinatorA = RUMSwiftUITransitionCoordinatorMock()
        let coordinatorB = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinatorA
        coordinators[sceneB] = coordinatorB
        let stateA = attachedState(identity: "home-A", sceneIdentifier: sceneA)
        let stateB = attachedState(identity: "home-B", sceneIdentifier: sceneB)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: stateA) {
            recorder.send(source: "A", transitions: $0)
        }
        arbiter.process(.appear, state: stateB) {
            recorder.send(source: "B", transitions: $0)
        }
        coordinatorA.complete(isCancelled: true)
        coordinatorB.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "B",
                    transition: .start(identity: "home-B", sceneIdentifier: sceneB)
                )
            ]
        )
    }

    func testWhenTwoKeyedScenesTransitionConcurrently_cancelAndCommitRemainIndependent() {
        let coordinatorA = RUMSwiftUITransitionCoordinatorMock()
        let coordinatorB = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinatorA
        coordinators[sceneB] = coordinatorB
        let identitiesA = RUMOccurrenceIdentityGenerator(["A-1", "A-2"])
        let identitiesB = RUMOccurrenceIdentityGenerator(["B-1", "B-2"])
        let stateA = RUMViewTrackingState(
            identity: "platform-A",
            occurrenceIdentityGenerator: identitiesA.next
        )
        let stateB = RUMViewTrackingState(
            identity: "platform-B",
            occurrenceIdentityGenerator: identitiesB.next
        )
        let initialA = keyedConfiguration("A-1", generation: 1)
        let initialB = keyedConfiguration("B-1", generation: 1)
        let replacementA = keyedConfiguration("A-2", generation: 2)
        let replacementB = keyedConfiguration("B-2", generation: 2)
        _ = stateA.mount(in: sceneA, configuration: initialA)
        _ = stateB.mount(in: sceneB, configuration: initialB)
        let revisionA = stateA.revision
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: replacementA,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: stateA
        ) {
            recorder.send(source: "A-2", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: replacementB,
                attachment: .attached(sceneB),
                isAppeared: true
            ),
            state: stateB
        ) {
            recorder.send(source: "B-2", transitions: $0)
        }
        coordinatorA.complete(isCancelled: true)
        coordinatorB.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "B-2",
                    transition: .replace(
                        oldIdentity: "B-1",
                        newIdentity: "B-2",
                        sceneIdentifier: sceneB
                    )
                )
            ]
        )
        XCTAssertEqual(stateA.configuration, initialA)
        XCTAssertEqual(stateA.lifecycleGeneration, 1)
        XCTAssertEqual(stateA.revision, revisionA)
        XCTAssertEqual(stateA.descriptor(for: "A-1")?.name, "A-1")
        XCTAssertEqual(stateA.sceneIdentifier, sceneA)
        XCTAssertEqual(identitiesA.invocationCount, 1)
        XCTAssertEqual(stateB.configuration, replacementB)
        XCTAssertEqual(stateB.lifecycleGeneration, 2)
        XCTAssertEqual(stateB.descriptor(for: "B-2")?.name, "B-2")
        XCTAssertEqual(stateB.sceneIdentifier, sceneB)
        XCTAssertEqual(identitiesB.invocationCount, 2)
    }

    func testWhenTwoTransitionsRunInSameScene_theyResolveByCoordinatorIdentity() {
        let coordinatorA = RUMSwiftUITransitionCoordinatorMock()
        let coordinatorB = RUMSwiftUITransitionCoordinatorMock()
        let controllerA = UIViewController()
        let controllerB = UIViewController()
        let observerA = RUMSceneIdentifierReader.ObserverView { _ in }
        let observerB = RUMSceneIdentifierReader.ObserverView { _ in }
        controllerA.view.addSubview(observerA)
        controllerB.view.addSubview(observerB)
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            coordinatorProvider: { _, observers in
                if observers.contains(where: { $0 === observerA }) {
                    return coordinatorA
                }
                if observers.contains(where: { $0 === observerB }) {
                    return coordinatorB
                }
                return nil
            }
        )
        let stateA = attachedState(identity: "view-A", sceneIdentifier: sceneA)
        let stateB = attachedState(identity: "view-B", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()
        arbiter.register(observer: observerA, for: stateA)
        arbiter.register(observer: observerB, for: stateB)

        arbiter.process(.appear, state: stateA) {
            recorder.send(source: "A", transitions: $0)
        }
        arbiter.process(.appear, state: stateB) {
            recorder.send(source: "B", transitions: $0)
        }
        coordinatorB.complete(isCancelled: false)
        coordinatorA.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "B",
                    transition: .start(identity: "view-B", sceneIdentifier: sceneA)
                ),
                .init(
                    source: "A",
                    transition: .start(identity: "view-A", sceneIdentifier: sceneA)
                )
            ]
        )
    }

    func testWhenPopIsCancelled_unrelatedLifecycleInSameSceneCommitsImmediately() {
        let popCoordinator = RUMSwiftUITransitionCoordinatorMock()
        let sceneRootViewController = UIViewController()
        let unrelatedViewController = UIViewController()
        let returningObserver = RUMSceneIdentifierReader.ObserverView { _ in }
        let unrelatedObserver = RUMSceneIdentifierReader.ObserverView { _ in }
        unrelatedViewController.view.addSubview(unrelatedObserver)
        let provider = RUMSwiftUITransitionCoordinatorProvider(
            sceneViewControllers: { _ in [sceneRootViewController] },
            controllerCoordinator: { viewController in
                viewController === sceneRootViewController ? popCoordinator : nil
            }
        )
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            coordinatorProvider: { sceneIdentifier, observers in
                provider.coordinator(for: sceneIdentifier, observers: observers)
            }
        )
        let returningState = RUMViewTrackingState(identity: "home")
        let unrelatedState = attachedState(identity: "sheet", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()
        arbiter.register(observer: returningObserver, for: returningState)
        arbiter.register(observer: unrelatedObserver, for: unrelatedState)

        arbiter.process(.mount(sceneA), state: returningState) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.process(.appear, state: unrelatedState) {
            recorder.send(source: "sheet", transitions: $0)
        }
        popCoordinator.complete(isCancelled: true)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "sheet",
                    transition: .start(identity: "sheet", sceneIdentifier: sceneA)
                )
            ]
        )
        XCTAssertEqual(returningState.attachment, .detached)
        XCTAssertFalse(returningState.isAppeared)
    }

    func testWhenUnrelatedReaderAttachesDuringPop_itLeavesProvisionalTransaction() {
        let popCoordinator = RUMSwiftUITransitionCoordinatorMock()
        let sceneRootViewController = UIViewController()
        let unrelatedViewController = UIViewController()
        let unrelatedObserver = RUMSceneIdentifierReader.ObserverView { _ in }
        let provider = RUMSwiftUITransitionCoordinatorProvider(
            sceneViewControllers: { _ in [sceneRootViewController] },
            controllerCoordinator: { viewController in
                viewController === sceneRootViewController ? popCoordinator : nil
            }
        )
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            coordinatorProvider: { sceneIdentifier, observers in
                provider.coordinator(for: sceneIdentifier, observers: observers)
            }
        )
        let unrelatedState = RUMViewTrackingState(identity: "sheet")
        let recorder = RUMSwiftUITransitionRecorder()
        arbiter.register(observer: unrelatedObserver, for: unrelatedState)

        arbiter.process(.mount(sceneA), state: unrelatedState) {
            recorder.send(source: "sheet", transitions: $0)
        }
        arbiter.process(.update(.attached(sceneA)), state: unrelatedState) {
            recorder.send(source: "sheet", transitions: $0)
        }
        arbiter.process(.appear, state: unrelatedState) {
            recorder.send(source: "sheet", transitions: $0)
        }
        XCTAssertEqual(recorder.entries, [])

        unrelatedViewController.view.addSubview(unrelatedObserver)
        arbiter.process(.update(.attached(sceneA)), state: unrelatedState) {
            recorder.send(source: "sheet", transitions: $0)
        }
        popCoordinator.complete(isCancelled: true)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "sheet",
                    transition: .start(identity: "sheet", sceneIdentifier: sceneA)
                )
            ]
        )
        XCTAssertEqual(unrelatedState.attachment, .attached(sceneA))
        XCTAssertTrue(unrelatedState.isAppeared)
    }

    func testWhenPendingViewAttachesToAnotherScene_itMigratesOutsideCancelledTransition() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = RUMViewTrackingState(identity: "candidate")
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.mount(sceneA), state: state) {
            recorder.send(source: "candidate", transitions: $0)
        }
        arbiter.process(.update(.attached(sceneB)), state: state) {
            recorder.send(source: "candidate", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "candidate", sceneIdentifier: sceneB)]
        )
        XCTAssertEqual(state.attachment, .attached(sceneB))
        XCTAssertTrue(state.isAppeared)
    }

    func testWhenSceneDisconnects_itDiscardsPendingLifecycle() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        arbiter.discard(sceneIdentifier: sceneA)
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertFalse(state.isAppeared)
    }

    func testWhenSceneDisconnectsDuringConcurrentKeyedTransitions_itCancelsOnlyThatScene() {
        let coordinatorA = RUMSwiftUITransitionCoordinatorMock()
        let coordinatorB = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinatorA
        coordinators[sceneB] = coordinatorB
        let identitiesA = RUMOccurrenceIdentityGenerator(["A-1", "A-2"])
        let identitiesB = RUMOccurrenceIdentityGenerator(["B-1", "B-2"])
        let stateA = RUMViewTrackingState(
            identity: "platform-A",
            occurrenceIdentityGenerator: identitiesA.next
        )
        let stateB = RUMViewTrackingState(
            identity: "platform-B",
            occurrenceIdentityGenerator: identitiesB.next
        )
        let initialA = keyedConfiguration("A-1", generation: 1)
        let initialB = keyedConfiguration("B-1", generation: 1)
        let replacementA = keyedConfiguration("A-2", generation: 2)
        let replacementB = keyedConfiguration("B-2", generation: 2)
        _ = stateA.mount(in: sceneA, configuration: initialA)
        _ = stateB.mount(in: sceneB, configuration: initialB)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: replacementA,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: stateA
        ) {
            recorder.send(source: "A-2", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: replacementB,
                attachment: .attached(sceneB),
                isAppeared: true
            ),
            state: stateB
        ) {
            recorder.send(source: "B-2", transitions: $0)
        }

        arbiter.discard(sceneIdentifier: sceneA)
        coordinatorA.complete(isCancelled: false)
        coordinatorB.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "B-2",
                    transition: .replace(
                        oldIdentity: "B-1",
                        newIdentity: "B-2",
                        sceneIdentifier: sceneB
                    )
                )
            ]
        )
        XCTAssertEqual(stateA.configuration, initialA)
        XCTAssertEqual(stateA.attachment, .detached)
        XCTAssertFalse(stateA.isAppeared)
        XCTAssertNil(stateA.activeLifecycleGeneration)
        XCTAssertEqual(identitiesA.invocationCount, 1)
        XCTAssertEqual(stateB.configuration, replacementB)
        XCTAssertEqual(stateB.sceneIdentifier, sceneB)
        XCTAssertEqual(stateB.lifecycleGeneration, 2)
        XCTAssertEqual(identitiesB.invocationCount, 2)
    }

    func testWhenSourceSceneDisconnects_pendingDestinationMigrationCanStillCommit() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneB] = coordinator
        let state = startedState(identity: "thread", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()
        let observerA = RUMSceneIdentifierReader.ObserverView { _ in }
        let observerB = RUMSceneIdentifierReader.ObserverView { _ in }
        observerA.notify(attachment: .attached(sceneA))
        observerB.notify(attachment: .attached(sceneB))
        arbiter.register(observer: observerA, for: state)
        arbiter.register(observer: observerB, for: state)

        arbiter.process(.update(.attached(sceneB)), state: state) {
            recorder.send(source: "thread", transitions: $0)
        }
        arbiter.discard(sceneIdentifier: sceneA)
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "thread", sceneIdentifier: sceneB)]
        )
        XCTAssertEqual(state.attachment, .attached(sceneB))
        XCTAssertTrue(state.isAppeared)
    }

    func testWhenSourceSceneDisconnects_cancelledDestinationMigrationCreatesNoOccurrence() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneB] = coordinator
        let state = startedState(identity: "thread", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.update(.attached(sceneB)), state: state) {
            recorder.send(source: "thread", transitions: $0)
        }
        arbiter.discard(sceneIdentifier: sceneA)
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
    }

    func testWhenOldSceneObserverIsDiscarded_destinationIntentUsesOnlyDestinationObserver() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let state = startedState(identity: "thread", sceneIdentifier: sceneB)
        let observerA = RUMSceneIdentifierReader.ObserverView { _ in }
        let observerB = RUMSceneIdentifierReader.ObserverView { _ in }
        observerA.notify(attachment: .attached(sceneA))
        observerB.notify(attachment: .attached(sceneB))
        var capturedObservers: [RUMSceneIdentifierReader.ObserverView] = []
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            coordinatorProvider: { sceneIdentifier, observers in
                XCTAssertEqual(sceneIdentifier, self.sceneB)
                capturedObservers = observers
                return coordinator
            }
        )
        arbiter.register(observer: observerA, for: state)
        arbiter.register(observer: observerB, for: state)

        arbiter.discard(sceneIdentifier: sceneA)
        arbiter.process(.disappear, state: state) { _ in }

        XCTAssertEqual(capturedObservers.count, 1)
        XCTAssertIdentical(capturedObservers.first, observerB)
        coordinator.complete(isCancelled: true)
    }

    func testWhenDisconnectedObserverReregisters_itCannotBypassDestinationCancellation() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let rootViewController = UIViewController()
        let staleViewController = UIViewController()
        let staleObserver = RUMSceneIdentifierReader.ObserverView { _ in }
        staleViewController.view.addSubview(staleObserver)
        staleObserver.notify(attachment: .attached(sceneA))
        let state = startedState(identity: "thread", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()
        let provider = RUMSwiftUITransitionCoordinatorProvider(
            sceneViewControllers: { sceneIdentifier in
                XCTAssertEqual(sceneIdentifier, self.sceneB)
                return [rootViewController]
            },
            controllerCoordinator: { viewController in
                viewController === rootViewController ? coordinator : nil
            }
        )
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            coordinatorProvider: { sceneIdentifier, observers in
                provider.coordinator(for: sceneIdentifier, observers: observers)
            }
        )
        arbiter.register(observer: staleObserver, for: state)
        arbiter.discard(sceneIdentifier: sceneA)
        arbiter.register(observer: staleObserver, for: state)

        arbiter.process(.mount(sceneB), state: state) {
            recorder.send(source: "thread", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(coordinator.registrationCount, 1)
        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
    }

    func testWhenPendingMigrationTargetsDisconnectedScene_itKeepsCommittedPeerState() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["B-1", "A-2"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("B-1", generation: 1)
        let migration = keyedConfiguration("A-2", generation: 2)
        _ = state.mount(in: sceneB, configuration: initial)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: migration,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "A-2", transitions: $0)
        }
        arbiter.discard(sceneIdentifier: sceneA)
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, initial)
        XCTAssertEqual(state.attachment, .attached(sceneB))
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(state.lifecycleGeneration, 1)
        XCTAssertEqual(state.descriptor(for: "B-1")?.name, "B-1")
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenInteractiveKeyChangesMultipleTimes_itCommitsOnlyFinalCandidate() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-final"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail-1", generation: 1)
        let candidate = keyedConfiguration("detail-2", generation: 2)
        let final = keyedConfiguration("detail-3", generation: 3)
        _ = state.mount(in: sceneA, configuration: initial)
        coordinators[sceneA] = coordinator
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: candidate,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-2", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: final,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-3", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "detail-3",
                    transition: .replace(
                        oldIdentity: "detail-1",
                        newIdentity: "detail-final",
                        sceneIdentifier: sceneA
                    )
                )
            ]
        )
        XCTAssertEqual(state.configuration, final)
        XCTAssertEqual(state.lifecycleGeneration, 2)
        XCTAssertEqual(state.descriptor(for: "detail-final")?.name, "detail-3")
        XCTAssertEqual(state.descriptor(for: "detail-final")?.path, "/detail-3")
    }

    func testWhenInteractiveKeyChangeIsCancelled_itDoesNotMutateOrAllocateOccurrence() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "unused"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail-1", generation: 1)
        let candidate = keyedConfiguration("detail-2", generation: 2)
        _ = state.mount(in: sceneA, configuration: initial)
        let revision = state.revision
        coordinators[sceneA] = coordinator
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: candidate,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-2", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, initial)
        XCTAssertEqual(state.lifecycleGeneration, 1)
        XCTAssertEqual(state.revision, revision)
    }

    func testWhenInteractiveCandidatesReturnToOriginalKey_itCommitsNoReplacement() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "unused"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail-1", generation: 1)
        let candidate = keyedConfiguration("detail-2", generation: 2)
        let returned = keyedConfiguration("detail-1", generation: 3)
        _ = state.mount(in: sceneA, configuration: initial)
        coordinators[sceneA] = coordinator
        let recorder = RUMSwiftUITransitionRecorder()

        for configuration in [candidate, returned] {
            arbiter.process(
                .reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneA),
                    isAppeared: true
                ),
                state: state
            ) {
                recorder.send(source: "candidate", transitions: $0)
            }
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, returned)
        XCTAssertEqual(state.lifecycleGeneration, 1)
    }

    func testWhenStaleBindingIntentArrivesDuringInteractiveReplacement_itIsIgnored() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail-1", generation: 1)
        let replacement = keyedConfiguration("detail-2", generation: 2)
        _ = state.mount(in: sceneA, configuration: initial)
        coordinators[sceneA] = coordinator
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: replacement,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-2", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: initial,
                attachment: nil,
                isAppeared: false
            ),
            state: state
        ) {
            recorder.send(source: "stale-detail-1", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "detail-2",
                    transition: .replace(
                        oldIdentity: "detail-1",
                        newIdentity: "detail-2",
                        sceneIdentifier: sceneA
                    )
                )
            ]
        )
        XCTAssertTrue(state.isAppeared)
    }

    func testWhenUnversionedLifecycleArrivesDuringKeyedReplacement_itIsIgnored() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail-1", generation: 1)
        let replacement = keyedConfiguration("detail-2", generation: 2)
        _ = state.mount(in: sceneA, configuration: initial)
        coordinators[sceneA] = coordinator
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: replacement,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-2", transitions: $0)
        }
        arbiter.process(.disappear, state: state) {
            recorder.send(source: "unversioned", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "detail-2",
                    transition: .replace(
                        oldIdentity: "detail-1",
                        newIdentity: "detail-2",
                        sceneIdentifier: sceneA
                    )
                )
            ]
        )
        XCTAssertTrue(state.isAppeared)
    }

    func testWhenStaleBindingClaimsAnotherScene_itLeavesValidPendingReplacementIntact() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let identities = RUMOccurrenceIdentityGenerator(["detail-2", "detail-3"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let stale = keyedConfiguration("detail-1", generation: 1)
        let initial = keyedConfiguration("detail-2", generation: 2)
        let replacement = keyedConfiguration("detail-3", generation: 3)
        _ = state.mount(in: sceneA, configuration: initial)
        coordinators[sceneA] = coordinator
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: replacement,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-3", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: stale,
                attachment: .attached(sceneB),
                isAppeared: false
            ),
            state: state
        ) {
            recorder.send(source: "stale-detail-1", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries,
            [
                .init(
                    source: "detail-3",
                    transition: .replace(
                        oldIdentity: "detail-2",
                        newIdentity: "detail-3",
                        sceneIdentifier: sceneA
                    )
                )
            ]
        )
        XCTAssertEqual(state.configuration, replacement)
        XCTAssertEqual(state.attachment, .attached(sceneA))
    }

    func testWhenCoordinatorIdentityIsReused_oldCompletionCannotResolveNewTransition() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2", "detail-3"])
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = keyedConfiguration("detail-1", generation: 1)
        let second = keyedConfiguration("detail-2", generation: 2)
        let third = keyedConfiguration("detail-3", generation: 3)
        _ = state.mount(in: sceneA, configuration: initial)
        coordinators[sceneA] = coordinator
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .reconcile(
                configuration: second,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-2", transitions: $0)
        }
        coordinator.complete(registration: 0, isCancelled: false)

        arbiter.process(
            .reconcile(
                configuration: third,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "detail-3", transitions: $0)
        }
        coordinator.complete(registration: 0, isCancelled: true)

        XCTAssertEqual(recorder.entries.count, 1)
        XCTAssertEqual(state.configuration, second)

        coordinator.complete(registration: 1, isCancelled: false)

        XCTAssertEqual(recorder.entries.count, 2)
        XCTAssertEqual(state.configuration, third)
    }

    func testWhenOldCoordinatorCompletesAgain_itDoesNotResolveNewTransition() {
        let firstCoordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = firstCoordinator
        let state = attachedState(identity: "home", sceneIdentifier: sceneA)
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(.appear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        firstCoordinator.complete(isCancelled: false)

        let secondCoordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = secondCoordinator
        arbiter.process(.disappear, state: state) {
            recorder.send(source: "home", transitions: $0)
        }
        firstCoordinator.complete(isCancelled: true)
        secondCoordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [
                .start(identity: "home", sceneIdentifier: sceneA),
                .stop(identity: "home", sceneIdentifier: sceneA)
            ]
        )
    }

    func testObserverResolvesNearestViewController() {
        let viewController = UIViewController()
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }

        viewController.view.addSubview(observer)

        XCTAssertIdentical(observer.nearestViewController, viewController)
    }

    private func attachedState(
        identity: String,
        sceneIdentifier: RUMSceneIdentifier
    ) -> RUMViewTrackingState {
        let state = RUMViewTrackingState(identity: identity)
        _ = state.update(attachment: .attached(sceneIdentifier))
        return state
    }

    private func startedState(
        identity: String,
        sceneIdentifier: RUMSceneIdentifier
    ) -> RUMViewTrackingState {
        let state = attachedState(identity: identity, sceneIdentifier: sceneIdentifier)
        _ = state.appear()
        return state
    }

    private func keyedConfiguration(
        _ key: String,
        generation: UInt64
    ) -> RUMViewTrackingState.Configuration {
        RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey(key),
            bindingGeneration: generation,
            descriptor: .init(name: key, path: "/\(key)", attributes: [:])
        )
    }
}
#endif
#endif

#endif
