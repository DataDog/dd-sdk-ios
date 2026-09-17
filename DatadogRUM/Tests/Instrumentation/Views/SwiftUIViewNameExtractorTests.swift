/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import Combine
import XCTest
import SwiftUI
import TestUtilities
#if compiler(>=6.4)
import Observation
#endif
@_spi(Experimental)
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

    func testWhenSourcePromotesMountedDormantNavigationBoundary_itStartsWithoutAnotherAppear() {
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("detail"),
            bindingGeneration: 1,
            descriptor: .init(name: "Detail", path: "/detail", attributes: [:]),
            isCurrentDestination: false
        )
        let accepted = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("alternate"),
            bindingGeneration: 1,
            descriptor: .init(name: "Alternate", path: "/alternate", attributes: [:])
        )
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneA
            ),
            [.start(identity: "alternate-1", sceneIdentifier: sceneA)]
        )
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenDetachedDormantNavigationBoundaryBecomesCurrent_itWaitsForAttachment() {
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("detail"),
            bindingGeneration: 1,
            descriptor: .init(name: "Detail", path: "/detail", attributes: [:]),
            isCurrentDestination: false
        )
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .detached
            )
        )

        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneA
            ),
            []
        )
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 0)
    }

    func testWhenMountedDormantNavigationBoundaryRemainsNonCurrent_itDoesNotStart() {
        let identities = RUMOccurrenceIdentityGenerator(["unused"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("detail"),
            bindingGeneration: 1,
            descriptor: .init(name: "Detail", path: "/detail", attributes: [:]),
            isCurrentDestination: false
        )
        let stillHidden = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("alternate"),
            bindingGeneration: 2,
            descriptor: .init(name: "Alternate", path: "/alternate", attributes: [:]),
            isCurrentDestination: false
        )
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: proposed,
                to: stillHidden,
                in: sceneA
            ),
            []
        )
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 0)
    }

    func testDormantNavigationPromotionRequiresExactSceneAndDormantSnapshot() {
        let identities = RUMOccurrenceIdentityGenerator(["unused"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("detail"),
            bindingGeneration: 1,
            descriptor: .init(name: "Detail", path: "/detail", attributes: [:]),
            isCurrentDestination: false
        )
        let wrongSnapshot = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("other-proposal"),
            bindingGeneration: 1,
            descriptor: .init(name: "Other", path: "/other", attributes: [:]),
            isCurrentDestination: false
        )
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: wrongSnapshot,
                to: accepted,
                in: sceneA
            ),
            []
        )
        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneB
            ),
            []
        )
        XCTAssertEqual(state.configuration, proposed)
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 0)
    }

    func testSourceAuthorizedReaderCanMigrateDormantNavigationBoundaryToAnotherScene() {
        let identities = RUMOccurrenceIdentityGenerator(["alternate-B"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("detail"),
            bindingGeneration: 1,
            descriptor: .init(name: "Detail", path: "/detail", attributes: [:]),
            isCurrentDestination: false
        )
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneB,
                allowsSceneMigration: true
            ),
            [.start(identity: "alternate-B", sceneIdentifier: sceneB)]
        )
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .attached(sceneB))
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testSourceAuthorizedReaderCanPromoteDormantBoundaryAfterTransientDetach() {
        let cases: [(RUMViewTrackingState.Attachment, RUMSceneIdentifier)] = [
            (.attached(sceneA), sceneA),
            (.attached(sceneA), sceneB),
            (.detached, sceneB)
        ]

        for (index, testCase) in cases.enumerated() {
            let identity = "accepted-\(index)"
            let identities = RUMOccurrenceIdentityGenerator([identity])
            let state = RUMViewTrackingState(
                identity: self.identity,
                occurrenceIdentityGenerator: identities.next
            )
            let proposed = RUMViewTrackingState.Configuration(
                occurrenceKey: RUMViewOccurrenceKey("detail"),
                bindingGeneration: 1,
                descriptor: .init(name: "Detail", path: "/detail", attributes: [:]),
                isCurrentDestination: false
            )
            let accepted = keyedConfiguration("alternate", generation: 1)
            XCTAssertTrue(
                state.recordDormantNavigationBoundary(
                    configuration: proposed,
                    attachment: testCase.0
                )
            )
            if testCase.0 != .detached {
                XCTAssertEqual(
                    state.reconcile(
                        configuration: proposed,
                        attachment: .detached,
                        isAppeared: false
                    ),
                    []
                )
            }

            XCTAssertEqual(
                state.promoteDormantNavigationBoundary(
                    from: proposed,
                    to: accepted,
                    in: testCase.1
                ),
                []
            )
            XCTAssertEqual(
                state.promoteDormantNavigationBoundary(
                    from: proposed,
                    to: accepted,
                    in: testCase.1,
                    allowsSceneMigration: true
                ),
                [.start(identity: identity, sceneIdentifier: testCase.1)]
            )
            XCTAssertEqual(identities.invocationCount, 1)
        }
    }

    func testPreviouslyStartedBoundaryCanUseDormantPromotionForNewerGeneration() {
        let usedIdentities = RUMOccurrenceIdentityGenerator(["detail-1", "alternate-2"])
        let usedState = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: usedIdentities.next
        )
        let detail = keyedConfiguration("detail", generation: 1)
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("proposal"),
            bindingGeneration: 2,
            descriptor: .init(name: "Proposal", path: "/proposal", attributes: [:]),
            isCurrentDestination: false
        )
        let accepted = keyedConfiguration("alternate", generation: 2)
        _ = usedState.mount(in: sceneA, configuration: detail)
        _ = usedState.disappear(configuration: detail)
        XCTAssertTrue(
            usedState.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            usedState.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneA
            ),
            [.start(identity: "alternate-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(usedIdentities.invocationCount, 2)
    }

    func testPreviouslyStartedBoundaryCannotPromoteAnAlreadyStartedGeneration() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "unused"])
        let state = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: identities.next
        )
        let detail = keyedConfiguration("detail", generation: 1)
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("proposal"),
            bindingGeneration: 1,
            descriptor: .init(name: "Proposal", path: "/proposal", attributes: [:]),
            isCurrentDestination: false
        )
        let accepted = keyedConfiguration("alternate", generation: 1)
        _ = state.mount(in: sceneA, configuration: detail)
        _ = state.disappear(configuration: detail)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneA
            ),
            []
        )
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testDisconnectFencedBoundaryCanUseSourceAuthorizedDormantPromotion() {
        let proposed = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey("proposal"),
            bindingGeneration: 2,
            descriptor: .init(name: "Proposal", path: "/proposal", attributes: [:]),
            isCurrentDestination: false
        )
        let accepted = keyedConfiguration("alternate", generation: 2)
        let fencedIdentities = RUMOccurrenceIdentityGenerator(["accepted-1"])
        let fencedState = RUMViewTrackingState(
            identity: identity,
            occurrenceIdentityGenerator: fencedIdentities.next
        )
        XCTAssertTrue(
            fencedState.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertTrue(fencedState.invalidateAfterSceneDisconnect(sceneA))

        XCTAssertEqual(
            fencedState.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneA
            ),
            [.start(identity: "accepted-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(fencedState.attachment, .attached(sceneA))
        XCTAssertFalse(fencedState.needsReaderRemount)
        XCTAssertEqual(fencedIdentities.invocationCount, 1)
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
class RUMSwiftUIViewAuthorityRegistryTests: XCTestCase {
    private let scene = RUMSceneIdentifier(rawValue: "scene-A")

    func testActiveExplicitViewSuppressesOnlyContainingAutomaticController() {
        let registry = RUMSwiftUIViewAuthorityRegistry()
        let state = RUMViewTrackingState(identity: "semantic-view")
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        let root = UIViewController()
        let targeted = UIViewController()
        let unrelated = UIViewController()
        root.addChild(targeted)
        root.view.addSubview(targeted.view)
        targeted.didMove(toParent: root)
        root.addChild(unrelated)
        root.view.addSubview(unrelated.view)
        unrelated.didMove(toParent: root)
        targeted.view.addSubview(observer)
        let window = UIWindow()
        window.rootViewController = root
        window.isHidden = false
        registry.register(observer: observer, trackingState: state)

        _ = state.mount(in: scene)

        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: targeted))
        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: root))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: unrelated))

        _ = state.disappear()

        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: targeted))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: root))
    }

    func testDetachedOrNeverAppearedExplicitViewDoesNotSuppressAutomaticController() {
        let registry = RUMSwiftUIViewAuthorityRegistry()
        let state = RUMViewTrackingState(identity: "semantic-view")
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        let viewController = UIViewController()
        viewController.view.addSubview(observer)
        let window = UIWindow()
        window.rootViewController = viewController
        window.isHidden = false
        registry.register(observer: observer, trackingState: state)

        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: viewController))

        _ = state.mount(in: scene)
        observer.removeFromSuperview()

        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: viewController))
    }

    func testSemanticPresentationAuthoritySuppressesOnlyItsMountedSubtreeUntilDisappear() {
        let registry = RUMSwiftUIViewAuthorityRegistry()
        let state = RUMSwiftUIAutomaticViewSuppressionState()
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        let root = UIViewController()
        let presentation = UIViewController()
        let unrelated = UIViewController()
        root.addChild(presentation)
        root.view.addSubview(presentation.view)
        presentation.didMove(toParent: root)
        root.addChild(unrelated)
        root.view.addSubview(unrelated.view)
        unrelated.didMove(toParent: root)
        presentation.view.addSubview(observer)
        let window = UIWindow()
        window.rootViewController = root
        window.isHidden = false
        registry.register(observer: observer, suppressionState: state)

        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: presentation))

        state.appear()

        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: presentation))
        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: root))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: unrelated))

        state.disappear()

        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: presentation))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: root))
    }

    @available(iOS 27.0, *)
    func testSemanticHostFinalDetachReleasesOnlyItsAutomaticSuppressionSubtree() {
        let registry = RUMSwiftUIViewAuthorityRegistry()
        let hostA = RUMSemanticNavigationHostState()
        let hostB = RUMSemanticNavigationHostState()
        let sourceA = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Home A")
        )
        let sourceB = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Home B")
        )
        let observerA = RUMSceneIdentifierReader.ObserverView { _ in }
        let observerB = RUMSceneIdentifierReader.ObserverView { _ in }
        let controllerA = UIViewController()
        let controllerB = UIViewController()
        let unrelated = UIViewController()
        let root = UIViewController()
        root.addChild(controllerA)
        root.view.addSubview(controllerA.view)
        controllerA.didMove(toParent: root)
        root.addChild(controllerB)
        root.view.addSubview(controllerB.view)
        controllerB.didMove(toParent: root)
        root.addChild(unrelated)
        root.view.addSubview(unrelated.view)
        unrelated.didMove(toParent: root)
        controllerA.view.addSubview(observerA)
        controllerB.view.addSubview(observerB)
        let window = UIWindow()
        window.rootViewController = root
        window.isHidden = false

        let handler = RUMViewsHandler(
            dateProvider: SystemDateProvider(),
            uiKitPredicate: nil,
            swiftUIPredicate: nil,
            swiftUIViewNameExtractor: nil,
            notificationCenter: NotificationCenter(),
            isMultiSceneApplication: true
        )
        let subscriber = RUMCommandSubscriberMock()
        handler.publish(to: subscriber)
        hostA.reconcile(transitions: sourceA, viewsHandler: handler)
        hostB.reconcile(transitions: sourceB, viewsHandler: handler)
        hostA.reconcile(attachment: .attached(RUMSceneIdentifier(rawValue: "scene-A")))
        hostB.reconcile(attachment: .attached(RUMSceneIdentifier(rawValue: "scene-B")))
        XCTAssertEqual(subscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }.count, 2)
        registry.register(
            observer: observerA,
            suppressionState: hostA.suppressionState
        )
        registry.register(
            observer: observerB,
            suppressionState: hostB.suppressionState
        )

        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: controllerA))
        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: controllerB))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: unrelated))

        hostA.finalDetach()

        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: controllerA))
        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: controllerB))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: unrelated))
    }
}

@available(iOS 27.0, *)
@MainActor
final class RUMSemanticNavigationAuthorityTests: XCTestCase {
    private struct ProvidingContent: SwiftUI.View, RUMNavigationTransitionProviding {
        let source: RUMNavigationTransitions
        var rumNavigationTransitions: RUMNavigationTransitions { source }
        var body: some SwiftUI.View { Text("Content") }
    }

    func testEmptyExplicitSourceKeepsAutomaticTrackingUntilFirstDestination() throws {
        try assertPendingAuthority(capability: false)
    }

    func testEmptyCapabilitySourceKeepsAutomaticTrackingUntilFirstDestination() throws {
        try assertPendingAuthority(capability: true)
    }

    func testSourceWithoutInstrumentationHasNoAuthorityUntilHandlerIsAvailable() throws {
        try assertPendingAuthority(initiallyHasDestination: true, initiallyHasHandler: false)
    }

    func testSourceWithoutSceneHasNoAuthorityUntilAttachmentIsAvailable() throws {
        try assertPendingAuthority(initiallyHasDestination: true, initiallyHasAttachment: false)
    }

    private func assertPendingAuthority(
        capability: Bool = false,
        initiallyHasDestination: Bool = false,
        initiallyHasHandler: Bool = true,
        initiallyHasAttachment: Bool = true
    ) throws {
        let source = RUMNavigationTransitions()
        if initiallyHasDestination { source.setInitialDestination(RUMView(name: "Semantic")) }
        let content = ProvidingContent(source: source)
        let selected = RUMNavigationHost<ProvidingContent>.resolveTransitions(
            explicit: capability ? nil : source,
            content: content
        )
        XCTAssertTrue(selected === source)
        let host = RUMSemanticNavigationHostState()
        let registry = RUMSwiftUIViewAuthorityRegistry()
        let subscriber = RUMCommandSubscriberMock()
        let handler = RUMViewsHandler(
            dateProvider: SystemDateProvider(),
            uiKitPredicate: nil,
            swiftUIPredicate: nil,
            swiftUIViewNameExtractor: nil,
            notificationCenter: NotificationCenter(),
            isMultiSceneApplication: true
        )
        handler.publish(to: subscriber)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        let target = UIViewController()
        let peer = UIViewController()
        let root = UIViewController()
        for child in [target, peer] {
            root.addChild(child)
            root.view.addSubview(child.view)
            child.didMove(toParent: root)
        }
        target.view.addSubview(observer)
        let window = UIWindow()
        window.rootViewController = root
        window.isHidden = false
        registry.register(observer: observer, suppressionState: host.suppressionState)
        host.reconcile(transitions: selected, viewsHandler: initiallyHasHandler ? handler : nil)
        if initiallyHasAttachment { host.reconcile(attachment: .attached(scene)) }

        XCTAssertTrue(host.selectedTransitions === source)
        XCTAssertFalse(host.suppressionState.isActive)
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: target))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: peer))
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
        source.willNavigate(id: "cancelled", destination: RUMView(name: "Unaccepted"))
        source.cancel(id: "cancelled")
        source.commit(id: "cancelled")
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: target))
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)

        if !initiallyHasHandler { host.reconcile(transitions: selected, viewsHandler: handler) }
        if !initiallyHasAttachment { host.reconcile(attachment: .attached(scene)) }
        if !initiallyHasDestination { source.setInitialDestination(RUMView(name: "Semantic")) }
        XCTAssertTrue(registry.isAutomaticViewSuppressed(for: target))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: peer))
        let start = try XCTUnwrap(subscriber.receivedCommands.first as? RUMStartViewCommand)
        XCTAssertEqual(subscriber.receivedCommands.count, 1)
        XCTAssertEqual(start.name, "Semantic")
        XCTAssertEqual(start.target, .scene(scene))
        source.setInitialDestination(RUMView(name: "Ignored duplicate"))
        host.reconcile(transitions: RUMNavigationTransitions(currentDestination: RUMView(name: "Replacement source")), viewsHandler: handler)
        XCTAssertTrue(host.selectedTransitions === source)
        XCTAssertEqual(subscriber.receivedCommands.count, 1)
        host.finalDetach()
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: target))
        XCTAssertFalse(registry.isAutomaticViewSuppressed(for: peer))
        let stop = try XCTUnwrap(subscriber.receivedCommands.last as? RUMStopViewCommand)
        XCTAssertEqual(subscriber.receivedCommands.count, 2)
        XCTAssertEqual(stop.identity, start.identity)
    }
}

@MainActor
final class RUMSwiftUINavigationOccurrenceContextTests: XCTestCase {
    private let scene = RUMSceneIdentifier(rawValue: "scene-A")

    func testRetainedCallbackDoesNotOwnItsCollaborators() {
        var context: RUMSwiftUINavigationOccurrenceContext?
        weak var releasedState: RUMViewTrackingState?
        weak var releasedHandler: RUMViewsHandler?
        weak var releasedArbiter: RUMSwiftUIInteractiveTransitionArbiter?
        autoreleasepool {
            let state = RUMViewTrackingState()
            let handler = makeHandler()
            let arbiter = RUMSwiftUIInteractiveTransitionArbiter(notificationCenter: NotificationCenter())
            releasedState = state
            releasedHandler = handler
            releasedArbiter = arbiter
            context = RUMSwiftUINavigationOccurrenceContext(state: state, viewsHandler: handler, fallback: configuration().descriptor)
            context?.transitionArbiter = arbiter
        }
        XCTAssertNil(releasedState)
        XCTAssertNil(releasedHandler)
        XCTAssertNil(releasedArbiter)
        context?.process(configuration: configuration(), sceneIdentifier: scene)
        XCTAssertNotNil(context)
    }

    func testRegistrationReleaseDoesNotRequireSourceRelease() {
        let source = RUMSwiftUINavigationOccurrenceSource()
        weak var releasedRegistration: RUMSwiftUINavigationOccurrenceRegistration?
        weak var releasedContext: RUMSwiftUINavigationOccurrenceContext?
        weak var releasedState: RUMViewTrackingState?
        autoreleasepool {
            let state = RUMViewTrackingState()
            let context = RUMSwiftUINavigationOccurrenceContext(state: state, viewsHandler: nil, fallback: configuration().descriptor)
            let registration = RUMSwiftUINavigationOccurrenceRegistration()
            releasedRegistration = registration
            releasedContext = context
            releasedState = state
            registration.rebind(
                to: source,
                state: state,
                configuration: configuration(),
                attachment: .attached(scene),
                process: context.process
            )
        }
        XCTAssertNil(releasedRegistration)
        XCTAssertNil(releasedContext)
        XCTAssertNil(releasedState)
        XCTAssertFalse(source.revealRetainedRoute(occurrenceKey: configuration().occurrenceKey, bindingGeneration: 2))
    }

    func testCancellationClearsCallbackAndRejectsRetainedReveal() {
        let source = RUMSwiftUINavigationOccurrenceSource()
        let state = RUMViewTrackingState()
        _ = state.mount(in: scene, configuration: configuration())
        _ = state.disappear(configuration: configuration())
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        weak var releasedToken: NSObject?
        autoreleasepool {
            let token = NSObject()
            releasedToken = token
            registration.rebind(to: source, state: state, configuration: configuration(), attachment: .attached(scene)) { _, _ in
                withExtendedLifetime(token) { XCTFail("Cancelled callback must not be invoked") }
            }
        }
        XCTAssertNotNil(releasedToken)
        let epoch = registration.callbackEpoch
        registration.cancel()
        XCTAssertGreaterThan(registration.callbackEpoch, epoch)
        XCTAssertNil(releasedToken)
        XCTAssertFalse(source.revealRetainedRoute(occurrenceKey: configuration().occurrenceKey, bindingGeneration: 2))
        XCTAssertNil(state.activeLifecycleGeneration)
    }

    func testRebindingMovesSourceAndPublishesLatestDescriptorOnFreshOccurrence() throws {
        let oldSource = RUMSwiftUINavigationOccurrenceSource()
        let newSource = RUMSwiftUINavigationOccurrenceSource()
        let state = RUMViewTrackingState(occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["old", "fresh"]).next)
        _ = state.mount(in: scene, configuration: configuration())
        _ = state.disappear(configuration: configuration())
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        registration.rebind(to: oldSource, state: state, configuration: configuration(), attachment: .attached(scene)) { _, _ in
            XCTFail("The previous source cannot deliver after rebinding")
        }
        let handler = makeHandler()
        let subscriber = RUMCommandSubscriberMock()
        handler.publish(to: subscriber)
        let latest = configuration(generation: 2, name: "Updated")
        let context = RUMSwiftUINavigationOccurrenceContext(state: state, viewsHandler: handler, fallback: latest.descriptor)
        registration.rebind(
            to: newSource,
            state: state,
            configuration: latest,
            attachment: .attached(scene),
            process: context.process
        )

        XCTAssertFalse(oldSource.revealRetainedRoute(occurrenceKey: latest.occurrenceKey, bindingGeneration: 3))
        XCTAssertTrue(newSource.revealRetainedRoute(occurrenceKey: latest.occurrenceKey, bindingGeneration: 3))
        let starts = subscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        let start = try XCTUnwrap(starts.first)
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(start.identity, ViewIdentifier("fresh"))
        XCTAssertEqual(start.target, .scene(scene))
        XCTAssertEqual(start.name, "Updated")
        XCTAssertEqual(start.path, "/Updated")
        XCTAssertFalse(newSource.revealRetainedRoute(occurrenceKey: latest.occurrenceKey, bindingGeneration: 3))
    }

    func testContextPreservesInteractiveCancellationAndSingleCommit() {
        for cancelled in [true, false] {
            let coordinator = RUMSwiftUITransitionCoordinatorMock()
            let arbiter = RUMSwiftUIInteractiveTransitionArbiter(notificationCenter: NotificationCenter()) { _, _ in coordinator }
            let state = RUMViewTrackingState()
            _ = state.update(configuration: configuration(), attachment: .attached(scene))
            let handler = makeHandler()
            let subscriber = RUMCommandSubscriberMock()
            handler.publish(to: subscriber)
            let context = RUMSwiftUINavigationOccurrenceContext(state: state, viewsHandler: handler, fallback: configuration().descriptor)
            context.transitionArbiter = arbiter
            context.process(configuration: configuration(), sceneIdentifier: scene)
            XCTAssertEqual(coordinator.registrationCount, 1)
            XCTAssertTrue(subscriber.receivedCommands.isEmpty)
            coordinator.complete(isCancelled: cancelled)
            coordinator.complete(isCancelled: cancelled)
            XCTAssertEqual(subscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }.count, cancelled ? 0 : 1)
        }
    }

    private func configuration(generation: UInt64 = 1, name: String = "Home") -> RUMViewTrackingState.Configuration {
        .init(occurrenceKey: RUMViewOccurrenceKey("home"), bindingGeneration: generation, descriptor: .init(name: name, path: "/\(name)", attributes: [:]))
    }

    private func makeHandler() -> RUMViewsHandler {
        .init(
            dateProvider: SystemDateProvider(),
            uiKitPredicate: nil,
            swiftUIPredicate: nil,
            swiftUIViewNameExtractor: nil,
            notificationCenter: NotificationCenter(),
            isMultiSceneApplication: true
        )
    }
}

@MainActor
class RUMSwiftUINavigationOccurrenceSourceTests: XCTestCase {
    private let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
    private let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

    func testWhenInitialTopHasNotMounted_containerSceneStartsAndTransfersOccurrence() {
        let containerIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let destinationIdentities = RUMOccurrenceIdentityGenerator(["duplicate"])
        let containerState = RUMViewTrackingState(
            identity: "container-fallback",
            occurrenceIdentityGenerator: containerIdentities.next
        )
        let destinationState = RUMViewTrackingState(
            identity: "destination-fallback",
            occurrenceIdentityGenerator: destinationIdentities.next
        )
        let root = configuration(
            key: "root",
            generation: 1,
            isCurrentDestination: false
        )
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = containerState.update(configuration: root, attachment: .attached(sceneA))
        var transitions: [RUMViewTrackingState.Transition] = []

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: containerState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                transitions.append(
                    contentsOf: containerState.mountInitialNavigationDestination(
                        in: sceneIdentifier,
                        configuration: configuration
                    )
                )
            },
            .handled
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "detail-1", sceneIdentifier: sceneA)]
        )
        XCTAssertTrue(source.isInitialDestinationPending)
        XCTAssertEqual(destinationState.appear(configuration: detail), [])
        XCTAssertTrue(destinationState.isAppeared)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneA,
                state: destinationState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                transitions.append(
                    contentsOf: destinationState.mountInitialNavigationDestination(
                        in: sceneIdentifier,
                        configuration: configuration
                    )
                )
            },
            .handled
        )
        XCTAssertFalse(source.needsInitialDestinationReconciliation)
        XCTAssertNil(containerState.activeLifecycleGeneration)
        XCTAssertEqual(destinationIdentities.invocationCount, 0)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: containerState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The hidden root must only restore dormant bookkeeping")
            },
            .recordDormant
        )
        XCTAssertTrue(
            containerState.recordDormantNavigationBoundary(
                configuration: root,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertEqual(containerState.configuration, root)
        XCTAssertFalse(containerState.isAppeared)
        XCTAssertEqual(
            destinationState.disappear(configuration: detail),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
    }

    func testWhenInitialTopMountsFirst_itOwnsBootstrapWithoutDuplicateStart() {
        let firstIdentities = RUMOccurrenceIdentityGenerator(["detail-1", "duplicate"])
        let secondIdentities = RUMOccurrenceIdentityGenerator(["duplicate"])
        let firstState = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: firstIdentities.next
        )
        let secondState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: secondIdentities.next
        )
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        var transitions: [RUMViewTrackingState.Transition] = []

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneA,
                state: firstState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                transitions.append(
                    contentsOf: firstState.mountInitialNavigationDestination(
                        in: sceneIdentifier,
                        configuration: configuration
                    )
                )
            },
            .handled
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "detail-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneA,
                state: secondState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                transitions.append(
                    contentsOf: secondState.mountInitialNavigationDestination(
                        in: sceneIdentifier,
                        configuration: configuration
                    )
                )
            },
            .handled
        )
        XCTAssertNil(firstState.activeLifecycleGeneration)
        XCTAssertEqual(
            secondState.disappear(configuration: detail),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(firstIdentities.invocationCount, 1)
        XCTAssertEqual(secondIdentities.invocationCount, 0)
        XCTAssertFalse(source.needsInitialDestinationReconciliation)
    }

    func testWhenMaterializedInitialTopIsReplaced_laterNavigationUsesOrdinaryArbiter() {
        let initialState = RUMViewTrackingState(
            identity: "initial-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["detail-1"]).next
        )
        let replacementState = RUMViewTrackingState(identity: "replacement-fallback")
        let detail = configuration(key: "detail", generation: 1)
        let replacement = configuration(key: "replacement", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: detail,
            sceneIdentifier: sceneA,
            state: initialState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = initialState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        source.acceptDestination(
            occurrenceKey: replacement.occurrenceKey,
            bindingGeneration: replacement.bindingGeneration,
            change: .replacement
        )
        source.reconcileCurrentDestination(configuration: replacement, viewsHandler: nil)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: replacement,
                sceneIdentifier: sceneA,
                state: replacementState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("Post-bootstrap navigation must use the ordinary arbiter")
            },
            .allowOrdinaryMount
        )
        XCTAssertNotNil(initialState.activeLifecycleGeneration)
    }

    func testWhenAcceptedRouteReusesDormantProposal_readerReconciliationAuthorizesPromotion() {
        let state = RUMViewTrackingState(identity: "destination-fallback")
        let proposed = configuration(
            key: "detail",
            generation: 1,
            isCurrentDestination: false
        )
        let accepted = configuration(key: "alternate", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: accepted.occurrenceKey,
            bindingGeneration: accepted.bindingGeneration,
            change: .initial(requiresBootstrap: false)
        )
        source.reconcileCurrentDestination(configuration: accepted, viewsHandler: nil)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneA,
                state: state,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("Ordinary callbacks must not authorize promotion")
            },
            .allowOrdinaryMount
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneA,
                state: state,
                allowsDormantBoundaryPromotion: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A post-bootstrap promotion must use the ordinary arbiter")
            },
            .promoteDormantBoundary(expected: proposed, accepted: accepted)
        )
    }

    func testWhenAcceptedRouteReusesDormantProposal_environmentTraitAuthorizesSameScenePromotion() {
        let state = RUMViewTrackingState(identity: "destination-fallback")
        let proposed = configuration(
            key: "detail",
            generation: 1,
            isCurrentDestination: false
        )
        let accepted = configuration(key: "alternate", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: accepted.occurrenceKey,
            bindingGeneration: accepted.bindingGeneration,
            change: .initial(requiresBootstrap: false)
        )
        source.reconcileCurrentDestination(configuration: accepted, viewsHandler: nil)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            source.resolveDormantCandidateFromEnvironmentTrait(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneA,
                state: state
            ),
            .promoteDormantBoundary(expected: proposed, accepted: accepted)
        )
    }

    func testWhenAcceptedRouteReusesDormantProposal_environmentTraitCannotMoveOrRecoverScene() {
        let proposed = configuration(
            key: "detail",
            generation: 1,
            isCurrentDestination: false
        )
        let accepted = configuration(key: "alternate", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: accepted.occurrenceKey,
            bindingGeneration: accepted.bindingGeneration,
            change: .initial(requiresBootstrap: false)
        )
        source.reconcileCurrentDestination(configuration: accepted, viewsHandler: nil)

        let movedState = RUMViewTrackingState(identity: "moved-fallback")
        XCTAssertTrue(
            movedState.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertEqual(
            source.resolveDormantCandidateFromEnvironmentTrait(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneB,
                state: movedState
            ),
            .allowOrdinaryMount
        )

        let disconnectedState = RUMViewTrackingState(identity: "disconnected-fallback")
        XCTAssertTrue(
            disconnectedState.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertTrue(disconnectedState.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertEqual(
            source.resolveDormantCandidateFromEnvironmentTrait(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneA,
                state: disconnectedState
            ),
            .allowOrdinaryMount
        )
    }

    func testWhenAcceptedRouteAdvancesDuringPendingProposal_readerMountAuthorizesPromotion() {
        let state = RUMViewTrackingState(identity: "destination-fallback")
        let proposed = configuration(
            key: "detail",
            generation: 1,
            isCurrentDestination: false
        )
        let accepted = configuration(key: "later", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: accepted.occurrenceKey,
            bindingGeneration: accepted.bindingGeneration,
            change: .replacement
        )
        source.reconcileCurrentDestination(configuration: accepted, viewsHandler: nil)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneA,
                state: state,
                isReaderMount: true,
                allowsDormantBoundaryPromotion: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A post-bootstrap promotion must use the ordinary arbiter")
            },
            .promoteDormantBoundary(expected: proposed, accepted: accepted)
        )
    }

    func testWhenAcceptedRouteMovesToAnotherScene_onlyReaderMountAuthorizesMigration() {
        let state = RUMViewTrackingState(identity: "destination-fallback")
        let proposed = configuration(
            key: "detail",
            generation: 1,
            isCurrentDestination: false
        )
        let accepted = configuration(key: "alternate", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: accepted.occurrenceKey,
            bindingGeneration: accepted.bindingGeneration,
            change: .initial(requiresBootstrap: false)
        )
        source.reconcileCurrentDestination(configuration: accepted, viewsHandler: nil)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneB,
                state: state,
                isReaderMount: false,
                allowsDormantBoundaryPromotion: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A post-bootstrap migration must use the ordinary arbiter")
            },
            .allowOrdinaryMount
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneB,
                state: state,
                isReaderMount: true,
                allowsDormantBoundaryPromotion: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A post-bootstrap migration must use the ordinary arbiter")
            },
            .promoteDormantBoundary(expected: proposed, accepted: accepted)
        )

        let detachedState = RUMViewTrackingState(identity: "detached-fallback")
        XCTAssertTrue(
            detachedState.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .detached
            )
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneB,
                state: detachedState,
                isReaderMount: false,
                allowsDormantBoundaryPromotion: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A post-bootstrap migration must use the ordinary arbiter")
            },
            .allowOrdinaryMount
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneB,
                state: detachedState,
                isReaderMount: true,
                allowsDormantBoundaryPromotion: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A post-bootstrap migration must use the ordinary arbiter")
            },
            .promoteDormantBoundary(expected: proposed, accepted: accepted)
        )
    }

    func testWhenDormantProposalDisconnects_readerMountAuthorizesAcceptedRecovery() {
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: "destination-fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = configuration(
            key: "detail",
            generation: 1,
            isCurrentDestination: false
        )
        let accepted = configuration(key: "alternate", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: accepted.occurrenceKey,
            bindingGeneration: accepted.bindingGeneration,
            change: .initial(requiresBootstrap: false)
        )
        source.reconcileCurrentDestination(configuration: accepted, viewsHandler: nil)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: accepted,
                sceneIdentifier: sceneB,
                state: state,
                isReaderMount: true,
                allowsDormantBoundaryPromotion: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The accepted reader must recover through the ordinary arbiter")
            },
            .promoteDormantBoundary(expected: proposed, accepted: accepted)
        )
        XCTAssertEqual(
            state.promoteDormantNavigationBoundary(
                from: proposed,
                to: accepted,
                in: sceneB
            ),
            [.start(identity: "alternate-1", sceneIdentifier: sceneB)]
        )
        XCTAssertEqual(state.attachment, .attached(sceneB))
        XCTAssertFalse(state.needsReaderRemount)
    }

    func testWhenPendingInitialTopChanges_sourceWaitsForAcceptedBoundaryAndRejectsStaleTop() {
        let containerIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let destinationIdentities = RUMOccurrenceIdentityGenerator(["home-1"])
        let containerState = RUMViewTrackingState(
            identity: "container-fallback",
            occurrenceIdentityGenerator: containerIdentities.next
        )
        let destinationState = RUMViewTrackingState(
            identity: "destination-fallback",
            occurrenceIdentityGenerator: destinationIdentities.next
        )
        let root = configuration(
            key: "root",
            generation: 1,
            isCurrentDestination: false
        )
        let detail = configuration(key: "detail", generation: 1)
        let home = configuration(key: "home", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: containerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = containerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        source.acceptDestination(
            occurrenceKey: home.occurrenceKey,
            bindingGeneration: home.bindingGeneration,
            change: .replacement
        )
        source.reconcileCurrentDestination(configuration: home, viewsHandler: nil)

        XCTAssertEqual(containerIdentities.invocationCount, 1)
        XCTAssertEqual(containerState.configuration, detail)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneA,
                state: destinationState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A stale destination must not be mounted")
            },
            .rejectStale
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: home,
                sceneIdentifier: sceneA,
                state: destinationState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = destinationState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertEqual(
            destinationState.disappear(configuration: home),
            [.stop(identity: "home-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(destinationIdentities.invocationCount, 1)
    }

    func testWhenPendingInitialTopChanges_donorRefreshDoesNotCreateHiddenRoot() {
        let donorIdentities = RUMOccurrenceIdentityGenerator(
            ["detail-1", "unexpected-root"]
        )
        let destinationIdentities = RUMOccurrenceIdentityGenerator(["detail-2"])
        let donorState = RUMViewTrackingState(
            identity: "donor-fallback",
            occurrenceIdentityGenerator: donorIdentities.next
        )
        let destinationState = RUMViewTrackingState(
            identity: "destination-fallback",
            occurrenceIdentityGenerator: destinationIdentities.next
        )
        let root1 = configuration(
            key: "root",
            generation: 1,
            isCurrentDestination: false
        )
        let detail1 = configuration(key: "detail-1", generation: 1)
        let root2 = configuration(
            key: "root",
            generation: 2,
            isCurrentDestination: false
        )
        let detail2 = configuration(key: "detail-2", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail1.occurrenceKey,
            bindingGeneration: detail1.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail1, viewsHandler: nil)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root1,
                sceneIdentifier: sceneA,
                state: donorState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = donorState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )

        source.acceptDestination(
            occurrenceKey: detail2.occurrenceKey,
            bindingGeneration: detail2.bindingGeneration,
            change: .replacement
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root2,
                sceneIdentifier: sceneA,
                state: donorState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A donor refresh must not require the destination descriptor")
            },
            .handled
        )
        XCTAssertEqual(donorState.configuration, detail1)
        XCTAssertNotNil(donorState.activeLifecycleGeneration)
        source.reconcileCurrentDestination(configuration: detail2, viewsHandler: nil)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root2,
                sceneIdentifier: sceneA,
                state: donorState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A donor refresh must not mount the hidden root")
            },
            .handled
        )
        XCTAssertEqual(donorState.configuration, detail1)
        XCTAssertNotNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(donorIdentities.invocationCount, 1)
        XCTAssertTrue(
            source.retainsManagedInitialOccurrence(
                for: root2,
                state: donorState,
                attachment: .detached
            )
        )
        XCTAssertTrue(
            source.retainsManagedInitialOccurrence(
                for: root2,
                state: donorState
            )
        )
        XCTAssertEqual(donorState.configuration, detail1)
        XCTAssertNotNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(donorIdentities.invocationCount, 1)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail2,
                sceneIdentifier: sceneA,
                state: destinationState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = destinationState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(donorState.configuration, root2)
        XCTAssertEqual(donorState.attachment, .detached)
        XCTAssertFalse(donorState.isAppeared)
        XCTAssertNotNil(destinationState.activeLifecycleGeneration)
        XCTAssertEqual(destinationIdentities.invocationCount, 1)
        XCTAssertEqual(
            destinationState.disappear(configuration: detail2),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenDonorRefreshCallbacksArriveOutOfOrder_theyNeverReachLocalGenerationFence() {
        let donorIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let destinationIdentities = RUMOccurrenceIdentityGenerator(["detail-3"])
        let donorState = RUMViewTrackingState(
            identity: "donor-fallback",
            occurrenceIdentityGenerator: donorIdentities.next
        )
        let destinationState = RUMViewTrackingState(
            identity: "destination-fallback",
            occurrenceIdentityGenerator: destinationIdentities.next
        )
        let root1 = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail1 = configuration(key: "detail-1", generation: 1)
        let root2 = configuration(key: "root", generation: 2, isCurrentDestination: false)
        let detail2 = configuration(key: "detail-2", generation: 2)
        let root3 = configuration(key: "root", generation: 3, isCurrentDestination: false)
        let detail3 = configuration(key: "detail-3", generation: 3)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail1.occurrenceKey,
            bindingGeneration: detail1.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail1, viewsHandler: nil)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root1,
                sceneIdentifier: sceneA,
                state: donorState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = donorState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )

        for (root, detail) in [(root2, detail2), (root3, detail3)] {
            source.acceptDestination(
                occurrenceKey: detail.occurrenceKey,
                bindingGeneration: detail.bindingGeneration,
                change: .replacement
            )
            XCTAssertEqual(
                source.resolveCandidate(
                    candidateConfiguration: root,
                    sceneIdentifier: sceneA,
                    state: donorState,
                    viewsHandler: nil
                ) { _, _ in
                    XCTFail("A donor refresh must not mount without its destination")
                },
                .handled
            )
            source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        }

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root2,
                sceneIdentifier: sceneA,
                state: donorState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A delayed donor generation must stay source-owned")
            },
            .rejectStale
        )
        XCTAssertTrue(
            source.retainsManagedInitialOccurrence(
                for: root2,
                state: donorState,
                attachment: .detached
            )
        )
        XCTAssertTrue(
            source.retainsManagedInitialOccurrence(
                for: root3,
                state: donorState,
                attachment: .detached
            )
        )
        XCTAssertEqual(donorState.configuration, detail1)
        XCTAssertNotNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(donorIdentities.invocationCount, 1)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail3,
                sceneIdentifier: sceneA,
                state: destinationState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = destinationState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(donorState.configuration, root3)
        XCTAssertEqual(donorState.attachment, .detached)
        XCTAssertEqual(
            destinationState.disappear(configuration: detail3),
            [.stop(identity: "detail-3", sceneIdentifier: sceneA)]
        )
    }

    func testWhenDonorMovesScenesBeforeDescriptorReconciliation_visibleDestinationMigrates() {
        let donorIdentities = RUMOccurrenceIdentityGenerator(["detail-a", "detail-b"])
        let destinationIdentities = RUMOccurrenceIdentityGenerator(["detail-2"])
        let donorState = RUMViewTrackingState(
            identity: "donor-fallback",
            occurrenceIdentityGenerator: donorIdentities.next
        )
        let destinationState = RUMViewTrackingState(
            identity: "destination-fallback",
            occurrenceIdentityGenerator: destinationIdentities.next
        )
        let root = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail1 = configuration(key: "detail-1", generation: 1)
        let detail2 = configuration(key: "detail-2", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail1.occurrenceKey,
            bindingGeneration: detail1.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail1, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: donorState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = donorState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        source.acceptDestination(
            occurrenceKey: detail2.occurrenceKey,
            bindingGeneration: detail2.bindingGeneration,
            change: .replacement
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneB,
                state: donorState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = donorState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertEqual(donorState.sceneIdentifier, sceneB)
        XCTAssertEqual(donorIdentities.invocationCount, 2)

        source.reconcileCurrentDestination(configuration: detail2, viewsHandler: nil)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail2,
                sceneIdentifier: sceneB,
                state: destinationState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = destinationState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(donorState.configuration, root)
        XCTAssertEqual(donorState.attachment, .attached(sceneB))
        XCTAssertEqual(
            destinationState.disappear(configuration: detail2),
            [.stop(identity: "detail-2", sceneIdentifier: sceneB)]
        )
    }

    func testWhenDonorReaderStateIsReplaced_sameSceneAdoptsExistingOccurrence() {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["duplicate"])
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root,
                attachment: .attached(sceneA)
            )
        )

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: replacementState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("Replacing the donor state must transfer, not restart")
            },
            .handled
        )
        XCTAssertNil(ownerState.activeLifecycleGeneration)
        XCTAssertNotNil(replacementState.activeLifecycleGeneration)
        XCTAssertEqual(ownerIdentities.invocationCount, 1)
        XCTAssertEqual(replacementIdentities.invocationCount, 0)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
    }

    func testWhenPreviouslyUsedDonorReturns_sameSceneReclaimsExistingOccurrence() {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["duplicate"])
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: replacementState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The replacement must adopt the existing occurrence")
            },
            .handled
        )

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: ownerState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The returning donor must reclaim the existing occurrence")
            },
            .handled
        )
        XCTAssertNotNil(ownerState.activeLifecycleGeneration)
        XCTAssertNil(replacementState.activeLifecycleGeneration)
        XCTAssertEqual(ownerIdentities.invocationCount, 1)
        XCTAssertEqual(replacementIdentities.invocationCount, 0)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
    }

    func testWhenPreviouslyUsedDonorReturnsInAnotherScene_itStartsFreshOccurrence() {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["duplicate"])
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root,
                attachment: .attached(sceneA)
            )
        )
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: replacementState,
            viewsHandler: nil
        ) { _, _ in
            XCTFail("The replacement must adopt the existing occurrence")
        }

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneB,
                state: ownerState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The returning donor requires a guarded same-generation remount")
            },
            .handled
        )
        XCTAssertNotNil(ownerState.activeLifecycleGeneration)
        XCTAssertEqual(ownerState.sceneIdentifier, sceneB)
        XCTAssertNil(replacementState.activeLifecycleGeneration)
        XCTAssertEqual(ownerIdentities.invocationCount, 2)
        XCTAssertEqual(replacementIdentities.invocationCount, 0)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-2", sceneIdentifier: sceneB)]
        )
    }

    func testWhenAdvancedDonorReturns_sameSceneReclaimsExistingOccurrence() {
        let fixture = makeAdvancedProvisionalDonorTransfer(
            ownerIdentityValues: ["detail-1"],
            replacementIdentityValues: ["duplicate"]
        )

        XCTAssertEqual(
            fixture.source.resolveCandidate(
                candidateConfiguration: fixture.root2,
                sceneIdentifier: sceneA,
                state: fixture.ownerState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The returning donor must reclaim the existing occurrence")
            },
            .handled
        )
        XCTAssertEqual(fixture.ownerState.configuration, fixture.detail1)
        XCTAssertNotNil(fixture.ownerState.activeLifecycleGeneration)
        XCTAssertNil(fixture.replacementState.activeLifecycleGeneration)
        XCTAssertEqual(fixture.ownerIdentities.invocationCount, 1)
        XCTAssertEqual(fixture.replacementIdentities.invocationCount, 0)
        XCTAssertEqual(
            fixture.source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
    }

    func testWhenAdvancedDonorReturnsInAnotherScene_itStartsFreshOccurrence() {
        let fixture = makeAdvancedProvisionalDonorTransfer(
            ownerIdentityValues: ["detail-1", "detail-2"],
            replacementIdentityValues: ["duplicate"]
        )

        XCTAssertEqual(
            fixture.source.resolveCandidate(
                candidateConfiguration: fixture.root2,
                sceneIdentifier: sceneB,
                state: fixture.ownerState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The returning donor requires a guarded same-generation remount")
            },
            .handled
        )
        XCTAssertEqual(fixture.ownerState.configuration, fixture.detail1)
        XCTAssertEqual(fixture.ownerState.sceneIdentifier, sceneB)
        XCTAssertNotNil(fixture.ownerState.activeLifecycleGeneration)
        XCTAssertNil(fixture.replacementState.activeLifecycleGeneration)
        XCTAssertEqual(fixture.ownerIdentities.invocationCount, 2)
        XCTAssertEqual(fixture.replacementIdentities.invocationCount, 0)
        XCTAssertEqual(
            fixture.source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-2", sceneIdentifier: sceneB)]
        )
    }

    func testWhenAdvancedDonorReconnectsFirst_replacementAdoptsFreshOccurrence() {
        let fixture = makeAdvancedProvisionalDonorTransfer(
            ownerIdentityValues: ["detail-1", "detail-2"],
            replacementIdentityValues: ["duplicate"]
        )
        XCTAssertTrue(fixture.ownerState.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(fixture.replacementState.invalidateAfterSceneDisconnect(sceneA))

        _ = fixture.source.resolveCandidate(
            candidateConfiguration: fixture.root2,
            sceneIdentifier: sceneA,
            state: fixture.ownerState,
            isReaderMount: true,
            viewsHandler: nil
        ) { _, _ in
            XCTFail("The returning donor requires guarded disconnect recovery")
        }
        XCTAssertEqual(
            fixture.source.resolveCandidate(
                candidateConfiguration: fixture.root2,
                sceneIdentifier: sceneA,
                state: fixture.replacementState,
                isReaderMount: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The replacement must adopt the recovered occurrence")
            },
            .handled
        )
        XCTAssertNil(fixture.ownerState.activeLifecycleGeneration)
        XCTAssertNotNil(fixture.replacementState.activeLifecycleGeneration)
        XCTAssertEqual(fixture.replacementState.configuration, fixture.detail1)
        XCTAssertEqual(fixture.ownerIdentities.invocationCount, 2)
        XCTAssertEqual(fixture.replacementIdentities.invocationCount, 0)

        fixture.source.sceneDidDisconnect(sceneA)
        XCTAssertEqual(
            fixture.source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenAdvancedReplacementReconnectsFirst_donorAdoptsFreshOccurrence() {
        let fixture = makeAdvancedProvisionalDonorTransfer(
            ownerIdentityValues: ["detail-1"],
            replacementIdentityValues: ["detail-2"]
        )
        XCTAssertTrue(fixture.ownerState.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(fixture.replacementState.invalidateAfterSceneDisconnect(sceneA))

        _ = fixture.source.resolveCandidate(
            candidateConfiguration: fixture.root2,
            sceneIdentifier: sceneA,
            state: fixture.replacementState,
            isReaderMount: true,
            viewsHandler: nil
        ) { _, _ in
            XCTFail("The current owner must use guarded disconnect recovery")
        }
        XCTAssertEqual(
            fixture.source.resolveCandidate(
                candidateConfiguration: fixture.root2,
                sceneIdentifier: sceneA,
                state: fixture.ownerState,
                isReaderMount: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The returning donor must adopt the recovered occurrence")
            },
            .handled
        )
        XCTAssertNotNil(fixture.ownerState.activeLifecycleGeneration)
        XCTAssertNil(fixture.replacementState.activeLifecycleGeneration)
        XCTAssertEqual(fixture.ownerState.configuration, fixture.detail1)
        XCTAssertEqual(fixture.ownerIdentities.invocationCount, 1)
        XCTAssertEqual(fixture.replacementIdentities.invocationCount, 1)

        fixture.source.sceneDidDisconnect(sceneA)
        XCTAssertEqual(
            fixture.source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenProvisionalDonorReconnectsBeforeQueuedCleanup_freshOwnerSurvives() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let root = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: state,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = state.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(state.needsReaderRemount)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: state,
                isReaderMount: true,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = state.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertFalse(state.needsReaderRemount)
        XCTAssertNotNil(state.activeLifecycleGeneration)
        XCTAssertEqual(identities.invocationCount, 2)

        source.sceneDidDisconnect(sceneA)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenDormantReplacementReconnectsBeforeInactiveOwner_itStartsFreshOccurrence() {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["detail-2"])
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertTrue(ownerState.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(replacementState.invalidateAfterSceneDisconnect(sceneA))

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: replacementState,
                isReaderMount: true,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = replacementState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertNil(ownerState.activeLifecycleGeneration)
        XCTAssertNotNil(replacementState.activeLifecycleGeneration)
        XCTAssertFalse(replacementState.needsReaderRemount)
        XCTAssertEqual(ownerIdentities.invocationCount, 1)
        XCTAssertEqual(replacementIdentities.invocationCount, 1)

        source.sceneDidDisconnect(sceneA)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenOwnerReconnectsBeforeDormantReplacement_replacementAdoptsFreshOccurrence() {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(["detail-1", "detail-2"])
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["duplicate"])
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertTrue(ownerState.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(replacementState.invalidateAfterSceneDisconnect(sceneA))
        _ = source.resolveCandidate(
            candidateConfiguration: root,
            sceneIdentifier: sceneA,
            state: ownerState,
            isReaderMount: true,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root,
                sceneIdentifier: sceneA,
                state: replacementState,
                isReaderMount: true,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The replacement must adopt the freshly remounted occurrence")
            },
            .handled
        )
        XCTAssertNil(ownerState.activeLifecycleGeneration)
        XCTAssertNotNil(replacementState.activeLifecycleGeneration)
        XCTAssertFalse(replacementState.needsReaderRemount)
        XCTAssertEqual(ownerIdentities.invocationCount, 2)
        XCTAssertEqual(replacementIdentities.invocationCount, 0)

        source.sceneDidDisconnect(sceneA)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenNewerDonorReconnectsBeforeDescriptor_itRestartsLastProvenDestination() {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["detail-1-reconnected"])
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root1 = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let root2 = configuration(key: "root", generation: 2, isCurrentDestination: false)
        let detail1 = configuration(key: "detail-1", generation: 1)
        let detail2 = configuration(key: "detail-2", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail1.occurrenceKey,
            bindingGeneration: detail1.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail1, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root1,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        source.acceptDestination(
            occurrenceKey: detail2.occurrenceKey,
            bindingGeneration: detail2.bindingGeneration,
            change: .replacement
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root2,
                sceneIdentifier: sceneA,
                state: ownerState,
                isReaderMount: false,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A donor refresh must not create a destination")
            },
            .handled
        )
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root2,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertTrue(ownerState.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(replacementState.invalidateAfterSceneDisconnect(sceneA))

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root2,
                sceneIdentifier: sceneA,
                state: replacementState,
                isReaderMount: true,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = replacementState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertEqual(replacementState.configuration, detail1)
        XCTAssertNotNil(replacementState.activeLifecycleGeneration)
        XCTAssertEqual(ownerIdentities.invocationCount, 1)
        XCTAssertEqual(replacementIdentities.invocationCount, 1)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-1-reconnected", sceneIdentifier: sceneA)]
        )
    }

    func testWhenNewerDonorMovesScenesBeforeDescriptor_itStartsLastProvenDestination() {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let replacementIdentities = RUMOccurrenceIdentityGenerator(["detail-1-scene-b"])
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root1 = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let root2 = configuration(key: "root", generation: 2, isCurrentDestination: false)
        let detail1 = configuration(key: "detail-1", generation: 1)
        let detail2 = configuration(key: "detail-2", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail1.occurrenceKey,
            bindingGeneration: detail1.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail1, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root1,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        source.acceptDestination(
            occurrenceKey: detail2.occurrenceKey,
            bindingGeneration: detail2.bindingGeneration,
            change: .replacement
        )
        _ = source.resolveCandidate(
            candidateConfiguration: root2,
            sceneIdentifier: sceneA,
            state: ownerState,
            isReaderMount: false,
            viewsHandler: nil
        ) { _, _ in
            XCTFail("A donor refresh must not create a destination")
        }
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root2,
                attachment: .attached(sceneB)
            )
        )

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root2,
                sceneIdentifier: sceneB,
                state: replacementState,
                isReaderMount: true,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = replacementState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertNil(ownerState.activeLifecycleGeneration)
        XCTAssertEqual(replacementState.configuration, detail1)
        XCTAssertEqual(replacementState.sceneIdentifier, sceneB)
        XCTAssertNotNil(replacementState.activeLifecycleGeneration)
        XCTAssertEqual(ownerIdentities.invocationCount, 1)
        XCTAssertEqual(replacementIdentities.invocationCount, 1)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-1-scene-b", sceneIdentifier: sceneB)]
        )
    }

    func testWhenAcceptedIdentityChanges_staleDescriptorCannotAdoptBeforeReconciliation() {
        let donorState = RUMViewTrackingState(
            identity: "donor-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["detail-1"]).next
        )
        let candidateState = RUMViewTrackingState(
            identity: "candidate-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["detail-2"]).next
        )
        let hiddenRoot = configuration(
            key: "root",
            generation: 1,
            isCurrentDestination: false
        )
        let detail1 = configuration(key: "detail-1", generation: 1)
        let detail2 = configuration(key: "detail-2", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail1.occurrenceKey,
            bindingGeneration: detail1.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail1, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: hiddenRoot,
            sceneIdentifier: sceneA,
            state: donorState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = donorState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        source.acceptDestination(
            occurrenceKey: detail2.occurrenceKey,
            bindingGeneration: detail2.bindingGeneration,
            change: .replacement
        )

        for candidate in [detail1, detail2] {
            XCTAssertEqual(
                source.resolveCandidate(
                    candidateConfiguration: candidate,
                    sceneIdentifier: sceneA,
                    state: candidateState,
                    viewsHandler: nil
                ) { _, _ in
                    XCTFail("No destination may mount before the accepted descriptor is reconciled")
                },
                .rejectStale
            )
        }
        XCTAssertEqual(donorState.configuration, detail1)
        XCTAssertNotNil(donorState.activeLifecycleGeneration)

        source.reconcileCurrentDestination(configuration: detail2, viewsHandler: nil)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail2,
                sceneIdentifier: sceneA,
                state: candidateState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = candidateState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(
            candidateState.disappear(configuration: detail2),
            [.stop(identity: "detail-2", sceneIdentifier: sceneA)]
        )
    }

    func testWhenInitialPathIsEmpty_laterDestinationCannotBootstrap() {
        let identities = RUMOccurrenceIdentityGenerator(["unused"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let detail = configuration(key: "detail", generation: 1)
        let root = configuration(key: "root", generation: 0)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: root.occurrenceKey,
            bindingGeneration: root.bindingGeneration,
            change: .initial(requiresBootstrap: false)
        )
        source.reconcileCurrentDestination(configuration: root, viewsHandler: nil)
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .replacement
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        var transitions: [RUMViewTrackingState.Transition] = []

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneA,
                state: state,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                transitions.append(
                    contentsOf: state.mountInitialNavigationDestination(
                        in: sceneIdentifier,
                        configuration: configuration
                    )
                )
            },
            .allowOrdinaryMount
        )
        XCTAssertEqual(transitions, [])
        XCTAssertEqual(identities.invocationCount, 0)
    }

    func testWhenPendingInitialPathBecomesEmpty_revealsFreshRootAndRejectsStaleTop() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1", "home-1"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let hiddenRoot = configuration(
            key: "root",
            generation: 1,
            isCurrentDestination: false
        )
        let detail = configuration(key: "detail", generation: 1)
        let revealedRoot = configuration(key: "root", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: hiddenRoot,
            sceneIdentifier: sceneA,
            state: state,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = state.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        source.acceptDestination(
            occurrenceKey: revealedRoot.occurrenceKey,
            bindingGeneration: revealedRoot.bindingGeneration,
            change: .retainedReveal
        )
        let transitions = source.reconcileCurrentDestination(
            configuration: revealedRoot,
            viewsHandler: nil
        )

        XCTAssertEqual(
            transitions,
            [
                .replace(
                    oldIdentity: "detail-1",
                    newIdentity: "home-1",
                    sceneIdentifier: sceneA
                )
            ]
        )
        XCTAssertEqual(state.configuration, revealedRoot)
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneA,
                state: RUMViewTrackingState(),
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The removed destination must not restart")
            },
            .rejectStale
        )
        XCTAssertFalse(source.needsInitialDestinationReconciliation)
    }

    func testWhenContainerDetachesBeforeInitialAdoption_provisionalOccurrenceStops() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-1"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let hiddenRoot = configuration(
            key: "root",
            generation: 1,
            isCurrentDestination: false
        )
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: hiddenRoot,
            sceneIdentifier: sceneA,
            state: state,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = state.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-1", sceneIdentifier: sceneA)]
        )
        XCTAssertFalse(state.isAppeared)
        XCTAssertNil(state.activeLifecycleGeneration)
        XCTAssertFalse(source.isInitialDestinationPending)
    }

    func testWhenInitialOwnerMovesToAnotherScene_newSceneBecomesSoleOwner() {
        let firstIdentities = RUMOccurrenceIdentityGenerator(["detail-a"])
        let secondIdentities = RUMOccurrenceIdentityGenerator(["detail-b"])
        let stateA = RUMViewTrackingState(
            identity: "fallback-a",
            occurrenceIdentityGenerator: firstIdentities.next
        )
        let stateB = RUMViewTrackingState(
            identity: "fallback-b",
            occurrenceIdentityGenerator: secondIdentities.next
        )
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: detail,
            sceneIdentifier: sceneA,
            state: stateA,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = stateA.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneB,
                state: stateB,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = stateB.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )

        XCTAssertNil(stateA.activeLifecycleGeneration)
        XCTAssertEqual(firstIdentities.invocationCount, 1)
        XCTAssertEqual(secondIdentities.invocationCount, 1)
        XCTAssertEqual(
            stateB.disappear(configuration: detail),
            [.stop(identity: "detail-b", sceneIdentifier: sceneB)]
        )
    }

    func testWhenInitialOwnerSceneDisconnects_sameGenerationReaderRemountStartsFreshOccurrence() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-a", "detail-b"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: detail,
            sceneIdentifier: sceneA,
            state: state,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = state.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))
        source.sceneDidDisconnect(sceneA)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneB,
                state: state,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = state.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertEqual(identities.invocationCount, 2)
        XCTAssertEqual(
            state.disappear(configuration: detail),
            [.stop(identity: "detail-b", sceneIdentifier: sceneB)]
        )
    }

    func testWhenSameSceneReconnectsBeforeQueuedSourceCleanup_freshOwnerSurvivesCleanup() {
        let identities = RUMOccurrenceIdentityGenerator(["detail-a", "detail-b"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let detail = configuration(key: "detail", generation: 1)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: detail,
            sceneIdentifier: sceneA,
            state: state,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = state.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        observer.notify(attachment: .attached(sceneA))
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: NotificationCenter(),
            coordinatorProvider: { _, _ in nil }
        )
        arbiter.register(
            observer: observer,
            for: state,
            navigationOccurrenceSource: source
        )
        arbiter.discard(sceneIdentifier: sceneA)
        XCTAssertTrue(state.needsReaderRemount)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: detail,
                sceneIdentifier: sceneA,
                state: state,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = state.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertEqual(identities.invocationCount, 2)

        source.sceneDidDisconnect(sceneA)
        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "detail-b", sceneIdentifier: sceneA)]
        )
    }

    func testWhenRetainedRouteReconnectsBeforeQueuedSourceCleanup_itRequiresFreshMount() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2", "home-3"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initialHome = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initialHome)
        _ = state.disappear(configuration: initialHome)

        let source = RUMSwiftUINavigationOccurrenceSource()
        let detail = configuration(key: "detail", generation: 1)
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .initial(requiresBootstrap: false)
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        registration.rebind(
            to: source,
            state: state,
            configuration: initialHome,
            attachment: .attached(sceneA)
        ) { configuration, sceneIdentifier in
            _ = state.reconcile(
                configuration: configuration,
                attachment: .attached(sceneIdentifier),
                isAppeared: true
            )
        }

        let returnedHome = configuration(key: "home", generation: 2)
        source.acceptDestination(
            occurrenceKey: returnedHome.occurrenceKey,
            bindingGeneration: returnedHome.bindingGeneration,
            change: .retainedReveal
        )
        source.reconcileCurrentDestination(configuration: returnedHome, viewsHandler: nil)
        XCTAssertEqual(identities.invocationCount, 2)

        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        observer.notify(attachment: .attached(sceneA))
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: NotificationCenter(),
            coordinatorProvider: { _, _ in nil }
        )
        arbiter.register(
            observer: observer,
            for: state,
            navigationOccurrenceSource: source
        )
        arbiter.discard(sceneIdentifier: sceneA)
        XCTAssertTrue(state.needsReaderRemount)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: returnedHome,
                sceneIdentifier: sceneA,
                state: state,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The invalidated pending lease must not be consumed")
            },
            .allowOrdinaryMount
        )
        XCTAssertEqual(
            state.mountCurrentNavigationDestinationAfterSceneDisconnect(
                in: sceneA,
                configuration: returnedHome
            ),
            [.start(identity: "home-3", sceneIdentifier: sceneA)]
        )

        source.sceneDidDisconnect(sceneA)
        XCTAssertEqual(
            state.disappear(configuration: returnedHome),
            [.stop(identity: "home-3", sceneIdentifier: sceneA)]
        )
    }

    func testWhenTwoSourcesRestoreSameRoute_initialOwnershipRemainsWindowLocal() {
        let detail = configuration(key: "detail", generation: 1)
        let stateA = RUMViewTrackingState(
            identity: "fallback-a",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["detail-a"]).next
        )
        let stateB = RUMViewTrackingState(
            identity: "fallback-b",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["detail-b"]).next
        )
        let sourceA = RUMSwiftUINavigationOccurrenceSource()
        let sourceB = RUMSwiftUINavigationOccurrenceSource()

        for source in [sourceA, sourceB] {
            source.acceptDestination(
                occurrenceKey: detail.occurrenceKey,
                bindingGeneration: detail.bindingGeneration,
                change: .initial(requiresBootstrap: true)
            )
            source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        }
        _ = sourceA.resolveCandidate(
            candidateConfiguration: detail,
            sceneIdentifier: sceneA,
            state: stateA,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = stateA.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        _ = sourceB.resolveCandidate(
            candidateConfiguration: detail,
            sceneIdentifier: sceneB,
            state: stateB,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = stateB.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        XCTAssertEqual(
            stateA.disappear(configuration: detail),
            [.stop(identity: "detail-a", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(
            stateB.disappear(configuration: detail),
            [.stop(identity: "detail-b", sceneIdentifier: sceneB)]
        )
    }

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

        XCTAssertTrue(
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

    func testWhenPendingRevealedRouteMovesScenesWithSameState_itRemountsFreshInDestinationScene() {
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2", "home-3"])
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

        let detail = configuration(key: "detail", generation: 2)
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .replacement
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        let returned = configuration(key: "home", generation: 3)
        source.acceptDestination(
            occurrenceKey: returned.occurrenceKey,
            bindingGeneration: returned.bindingGeneration,
            change: .retainedReveal
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
        source.reconcileCurrentDestination(configuration: returned, viewsHandler: nil)

        var attemptedOrdinaryMount = false
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: returned,
                sceneIdentifier: sceneB,
                state: state,
                viewsHandler: nil
            ) { _, _ in
                attemptedOrdinaryMount = true
            },
            .handled
        )
        XCTAssertFalse(attemptedOrdinaryMount)
        XCTAssertEqual(identities.invocationCount, 3)
        XCTAssertEqual(state.sceneIdentifier, sceneB)
        XCTAssertNotNil(state.activeLifecycleGeneration)
        XCTAssertEqual(
            state.disappear(configuration: returned),
            [.stop(identity: "home-3", sceneIdentifier: sceneB)]
        )
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

    func testWhenOutgoingCurrentSnapshotDetaches_retainedPopUsesItsLastProvenScene() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initialRoot = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initialRoot)
        _ = state.disappear(configuration: initialRoot)

        let source = RUMSwiftUINavigationOccurrenceSource()
        let detail = configuration(key: "detail", generation: 2)
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .replacement
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)

        XCTAssertEqual(
            state.update(configuration: initialRoot, attachment: .detached),
            []
        )
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertEqual(state.retainedRouteSceneIdentifier, sceneA)

        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: initialRoot,
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

        let returnedRoot = configuration(key: "home", generation: 3)
        source.acceptDestination(
            occurrenceKey: returnedRoot.occurrenceKey,
            bindingGeneration: returnedRoot.bindingGeneration,
            change: .retainedReveal
        )

        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.configuration, returnedRoot)
        XCTAssertEqual(identities.invocationCount, 2)
    }

    func testWhenContainerDetachesDuringRetainedAdoption_pendingOccurrenceStops() {
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

        XCTAssertEqual(
            source.cancelNavigationOwnedOccurrences(viewsHandler: nil),
            [.stop(identity: "home-2", sceneIdentifier: sceneA)]
        )
        XCTAssertNil(state.activeLifecycleGeneration)
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(
            state.disappear(configuration: configuration(key: "home", generation: 2)),
            []
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

    func testWhenDormantRouteReconnects_readerRearmsSynchronousReveal() {
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let state = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initial = configuration(key: "home", generation: 1)
        _ = state.mount(in: sceneA, configuration: initial)
        _ = state.disappear(configuration: initial)
        let hiddenHome = configuration(
            key: "home",
            generation: 2,
            isCurrentDestination: false
        )
        _ = state.update(configuration: hiddenHome, attachment: .attached(sceneA))

        let source = RUMSwiftUINavigationOccurrenceSource()
        let detail = configuration(key: "detail", generation: 2)
        source.acceptDestination(
            occurrenceKey: detail.occurrenceKey,
            bindingGeneration: detail.bindingGeneration,
            change: .replacement
        )
        source.reconcileCurrentDestination(configuration: detail, viewsHandler: nil)
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: source,
            state: state,
            configuration: hiddenHome,
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
        XCTAssertTrue(state.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(state.needsReaderRemount)

        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: hiddenHome,
                sceneIdentifier: sceneA,
                state: state,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A hidden boundary must not mount while another route is current")
            },
            .recordDormant
        )
        XCTAssertTrue(
            state.rearmDormantNavigationBoundaryAfterSceneDisconnect(
                configuration: hiddenHome,
                attachment: .attached(sceneA)
            )
        )
        registration.rebind(
            to: source,
            state: state,
            configuration: hiddenHome,
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
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertFalse(state.isAppeared)
        XCTAssertNil(state.activeLifecycleGeneration)
        XCTAssertFalse(state.needsReaderRemount)
        XCTAssertEqual(identities.invocationCount, 1)

        let returned = configuration(key: "home", generation: 3)
        source.acceptDestination(
            occurrenceKey: returned.occurrenceKey,
            bindingGeneration: returned.bindingGeneration,
            change: .retainedReveal
        )
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: sceneA)]
        )
        source.reconcileCurrentDestination(configuration: returned, viewsHandler: nil)
        XCTAssertTrue(
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

    private struct AdvancedProvisionalDonorFixture {
        let source: RUMSwiftUINavigationOccurrenceSource
        let ownerState: RUMViewTrackingState
        let replacementState: RUMViewTrackingState
        let root2: RUMViewTrackingState.Configuration
        let detail1: RUMViewTrackingState.Configuration
        let ownerIdentities: RUMOccurrenceIdentityGenerator
        let replacementIdentities: RUMOccurrenceIdentityGenerator
    }

    private func makeAdvancedProvisionalDonorTransfer(
        ownerIdentityValues: [String],
        replacementIdentityValues: [String]
    ) -> AdvancedProvisionalDonorFixture {
        let ownerIdentities = RUMOccurrenceIdentityGenerator(ownerIdentityValues)
        let replacementIdentities = RUMOccurrenceIdentityGenerator(
            replacementIdentityValues
        )
        let ownerState = RUMViewTrackingState(
            identity: "owner-fallback",
            occurrenceIdentityGenerator: ownerIdentities.next
        )
        let replacementState = RUMViewTrackingState(
            identity: "replacement-fallback",
            occurrenceIdentityGenerator: replacementIdentities.next
        )
        let root1 = configuration(key: "root", generation: 1, isCurrentDestination: false)
        let root2 = configuration(key: "root", generation: 2, isCurrentDestination: false)
        let detail1 = configuration(key: "detail-1", generation: 1)
        let detail2 = configuration(key: "detail-2", generation: 2)
        let source = RUMSwiftUINavigationOccurrenceSource()
        source.acceptDestination(
            occurrenceKey: detail1.occurrenceKey,
            bindingGeneration: detail1.bindingGeneration,
            change: .initial(requiresBootstrap: true)
        )
        source.reconcileCurrentDestination(configuration: detail1, viewsHandler: nil)
        _ = source.resolveCandidate(
            candidateConfiguration: root1,
            sceneIdentifier: sceneA,
            state: ownerState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = ownerState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }
        XCTAssertTrue(
            replacementState.recordDormantNavigationBoundary(
                configuration: root1,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root1,
                sceneIdentifier: sceneA,
                state: replacementState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The replacement must adopt the provisional occurrence")
            },
            .handled
        )

        source.acceptDestination(
            occurrenceKey: detail2.occurrenceKey,
            bindingGeneration: detail2.bindingGeneration,
            change: .replacement
        )
        XCTAssertEqual(
            source.resolveCandidate(
                candidateConfiguration: root2,
                sceneIdentifier: sceneA,
                state: replacementState,
                isReaderMount: false,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("A donor refresh must not create a destination")
            },
            .handled
        )
        XCTAssertEqual(ownerState.disappear(configuration: root2), [])
        XCTAssertEqual(ownerState.configuration, root2)

        return AdvancedProvisionalDonorFixture(
            source: source,
            ownerState: ownerState,
            replacementState: replacementState,
            root2: root2,
            detail1: detail1,
            ownerIdentities: ownerIdentities,
            replacementIdentities: replacementIdentities
        )
    }

    private func configuration(
        key: String,
        generation: UInt64,
        isCurrentDestination: Bool = true
    ) -> RUMViewTrackingState.Configuration {
        RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey(key),
            bindingGeneration: generation,
            descriptor: .init(name: key, path: "/\(key)", attributes: [:]),
            isCurrentDestination: isCurrentDestination
        )
    }
}

@available(iOS 27.0, *)
@MainActor
final class RUMSwiftUISemanticNavigationEngineTests: XCTestCase {
    private struct SemanticSnapshot: Equatable {
        let generation: UInt64
        let name: String
        let path: String?
    }

    private enum ParityRoot: Hashable {
        case home
    }

    private enum ParityRoute: Hashable {
        case thread(Int)
    }

    private enum ParityPresentation: Hashable {
        case compose
        case attachmentPreview
    }

    private final class ObservationCounter {
        private(set) var subscriptions = 0
        private(set) var projections = 0
        private(set) var renderedSelections: [Bool] = []

        func recordSubscription() {
            subscriptions += 1
        }

        func recordProjection() {
            projections += 1
        }

        func recordRender(useSecondPublisher: Bool) {
            renderedSelections.append(useSecondPublisher)
        }
    }

    private final class ObservedHostReconstructionModel: ObservableObject {
        @Published var useSecondPublisher = false
    }

#if compiler(>=6.4)
    @Observable
    @MainActor
    final class ObservationNavigationModel {
        var destination: RUMNavigationDestination

        init(destination: RUMNavigationDestination) {
            self.destination = destination
        }
    }

    @Observable
    @MainActor
    final class MultiPropertyObservationNavigationModel {
        var route: Int?
        var presentation: String?
    }

    @Observable
    final class BackgroundObservationNavigationModel: @unchecked Sendable {
        var destination: RUMNavigationDestination

        init(destination: RUMNavigationDestination) {
            self.destination = destination
        }
    }

    private struct ObservationHostReconstructionHarness: SwiftUI.View {
        @ObservedObject var renderModel: ObservedHostReconstructionModel
        let navigationModel: ObservationNavigationModel
        let counter: ObservationCounter

        var body: some SwiftUI.View {
            let useSecondRendering = renderModel.useSecondPublisher
            counter.recordRender(useSecondPublisher: useSecondRendering)
            return RUMNavigationHost(
                observingCurrentDestination: {
                    counter.recordProjection()
                    return navigationModel.destination
                }
            ) {
                SwiftUI.Text(useSecondRendering ? "Second" : "First")
            }
        }
    }
#endif

    private struct Presentation: Identifiable {
        let id: String
    }

    private struct ProvidingContent: SwiftUI.View, RUMNavigationTransitionProviding {
        let source: RUMNavigationTransitions

        var rumNavigationTransitions: RUMNavigationTransitions { source }

        var body: some SwiftUI.View {
            SwiftUI.Text("Customer navigation")
        }
    }

    private struct ObservedHostReconstructionHarness: SwiftUI.View {
        @ObservedObject var model: ObservedHostReconstructionModel
        let first: AnyPublisher<Int, Never>
        let second: AnyPublisher<Int, Never>
        let renderCounter: ObservationCounter

        var body: some SwiftUI.View {
            let useSecondPublisher = model.useSecondPublisher
            let updates = useSecondPublisher ? second : first
            renderCounter.recordRender(useSecondPublisher: useSecondPublisher)
            return RUMNavigationHost(
                observing: updates,
                destination: { .root($0) }
            ) {
                SwiftUI.Text(useSecondPublisher ? "Second" : "First")
            }
        }
    }

    func testSceneAttachmentIsIndependentFromVisualContainer() {
        let engine = RUMSwiftUISemanticNavigationEngine()
        let scene = RUMSceneIdentifier(rawValue: "scene-A")

        XCTAssertNil(engine.sceneIdentifier)

        engine.reconcile(attachment: .attached(scene))
        XCTAssertEqual(engine.sceneIdentifier, scene)

        engine.reconcile(attachment: .detached)
        XCTAssertNil(engine.sceneIdentifier)
    }

    func testNativeAdapterUsesInjectedContainerIndependentEngine() {
        let engine = RUMSwiftUISemanticNavigationEngine()
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>(
            engine: engine
        )

        XCTAssertTrue(navigationState.engine === engine)
        XCTAssertTrue(navigationState.occurrenceSource === engine.occurrenceSource)
    }

    func testNavigationHostAcceptsArbitraryCustomerContent() {
        _ = RUMNavigationHost {
            SwiftUI.Text("Customer navigation")
        }
    }

#if compiler(>=6.4)
    func testObservationHostKeepsStandardSwiftUINavigation() {
        let model = ObservationNavigationModel(
            destination: .root(ParityRoot.home)
        )
        _ = RUMNavigationHost(
            observingCurrentDestination: { model.destination }
        ) {
            SwiftUI.NavigationStack {
                SwiftUI.Text("Customer navigation")
            }
            .sheet(isPresented: .constant(false)) {
                SwiftUI.Text("Customer sheet")
            }
            .fullScreenCover(isPresented: .constant(false)) {
                SwiftUI.Text("Customer cover")
            }
        }
    }
#endif

    func testTransitionSourcePublishesOnlyCommittedDestinationsAsFreshOccurrences() {
        let source = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Home")
        )
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observation = source.observe { snapshots.append($0) }

        source.willNavigate(
            id: "cancelled-detail",
            destination: RUMView(name: "Detail")
        )
        source.cancel(id: "cancelled-detail")
        source.commit(id: "cancelled-detail")

        XCTAssertEqual(snapshots.map(\.destination.name), ["Home"])

        source.willNavigate(id: "detail-1", destination: RUMView(name: "Detail"))
        source.commit(id: "detail-1")
        source.willNavigate(id: "detail-2", destination: RUMView(name: "Detail"))
        source.commit(id: "detail-2")

        XCTAssertEqual(snapshots.map(\.destination.name), ["Home", "Detail", "Detail"])
        XCTAssertEqual(snapshots.map(\.generation), [0, 1, 2])
        source.removeObserver(observation)
    }

    func testTransitionSourceNestedCommitDoesNotRegressAnyObserver() {
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        var generations = Array(repeating: [UInt64](), count: 3)
        var nested = false
        var observations: [UUID] = []
        for index in generations.indices {
            observations.append(source.observe { snapshot in
                generations[index].append(snapshot.generation)
                if snapshot.generation == 1, !nested {
                    nested = true
                    source.willNavigate(id: "nested", destination: RUMView(name: "Latest"))
                    source.commit(id: "nested")
                    XCTAssertTrue(generations.allSatisfy { $0.last == 2 })
                }
            })
        }

        source.willNavigate(id: "outer", destination: RUMView(name: "Outer"))
        source.commit(id: "outer")

        XCTAssertTrue(nested)
        for delivered in generations {
            XCTAssertEqual(delivered.last, 2)
            XCTAssertEqual(delivered, delivered.sorted())
            XCTAssertEqual(delivered.filter { $0 == 2 }.count, 1)
        }
        observations.forEach(source.removeObserver)
    }

    func testTransitionSourceNestedInitialPublicationDoesNotRegressAnyObserver() {
        let source = RUMNavigationTransitions()
        var generations = Array(repeating: [UInt64](), count: 3)
        var nested = false
        var observations: [UUID] = []
        for index in generations.indices {
            observations.append(source.observe { snapshot in
                generations[index].append(snapshot.generation)
                if snapshot.generation == 0, !nested {
                    nested = true
                    source.willNavigate(id: "nested", destination: RUMView(name: "Latest"))
                    source.commit(id: "nested")
                    XCTAssertTrue(generations.allSatisfy { $0.last == 1 })
                }
            })
        }

        source.setInitialDestination(RUMView(name: "Initial"))
        source.setInitialDestination(RUMView(name: "Ignored"))

        XCTAssertTrue(nested)
        for delivered in generations {
            XCTAssertEqual(delivered.last, 1)
            XCTAssertEqual(delivered, delivered.sorted())
            XCTAssertEqual(delivered.filter { $0 == 1 }.count, 1)
        }
        observations.forEach(source.removeObserver)
    }

    func testTransitionSourceRemovalCancelsPendingObserverDelivery() {
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        var observations: [UUID] = []
        var deliveries = 0
        for _ in 0..<3 {
            observations.append(source.observe { snapshot in
                guard snapshot.generation > 0 else {
                    return
                }
                deliveries += 1
                observations.forEach(source.removeObserver)
            })
        }

        source.willNavigate(id: "outer", destination: RUMView(name: "Outer"))
        source.commit(id: "outer")
        source.willNavigate(id: "later", destination: RUMView(name: "Later"))
        source.commit(id: "later")

        XCTAssertEqual(deliveries, 1)
    }

    func testTransitionSourceAddAndRemoveDuringNestedCommitUsesCurrentMembership() {
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        var observations: [UUID] = []
        var delivered = Array(repeating: [UInt64](), count: 3)
        var added: [UInt64] = []
        var removedIndex: Int?
        var addedObservation: UUID?
        for index in delivered.indices {
            observations.append(source.observe { snapshot in
                delivered[index].append(snapshot.generation)
                guard snapshot.generation == 1, removedIndex == nil else {
                    return
                }
                removedIndex = index
                source.removeObserver(observations[index])
                addedObservation = source.observe { added.append($0.generation) }
                source.willNavigate(id: "nested", destination: RUMView(name: "Latest"))
                source.commit(id: "nested")
                XCTAssertEqual(added, [1, 2])
                XCTAssertTrue(delivered.indices.allSatisfy { $0 == index || delivered[$0].last == 2 })
            })
        }

        source.willNavigate(id: "outer", destination: RUMView(name: "Outer"))
        source.commit(id: "outer")
        source.willNavigate(id: "cancelled", destination: RUMView(name: "Cancelled"))
        source.cancel(id: "cancelled")
        source.commit(id: "cancelled")

        XCTAssertNotNil(removedIndex)
        XCTAssertEqual(added, [1, 2])
        for index in delivered.indices {
            XCTAssertEqual(delivered[index].last, index == removedIndex ? 1 : 2)
            XCTAssertEqual(delivered[index], delivered[index].sorted())
        }
        observations.forEach(source.removeObserver)
        if let addedObservation { source.removeObserver(addedObservation) }
    }

    func testTransitionSourceNestedGenerationsStaySynchronousAtEveryReturn() {
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        var delivered = Array(repeating: [UInt64](), count: 3)
        var committed: Set<UInt64> = []
        var observations: [UUID] = []
        for index in delivered.indices {
            observations.append(source.observe { snapshot in
                delivered[index].append(snapshot.generation)
                guard (1..<4).contains(snapshot.generation), committed.insert(snapshot.generation).inserted else {
                    return
                }
                source.willNavigate(id: "nested", destination: RUMView(name: "Nested"))
                source.commit(id: "nested")
                XCTAssertTrue(delivered.allSatisfy { $0.last == 4 })
            })
        }

        source.willNavigate(id: "outer", destination: RUMView(name: "Outer"))
        source.commit(id: "outer")

        XCTAssertEqual(committed, [1, 2, 3])
        for generations in delivered {
            XCTAssertEqual(generations.last, 4)
            XCTAssertEqual(generations, generations.sorted())
            XCTAssertEqual(generations.filter { $0 == 4 }.count, 1)
        }
        observations.forEach(source.removeObserver)
    }

    func testObservedPublisherNestedCommitKeepsEveryObserverOnLatestDestination() throws {
        let updates = CurrentValueSubject<RUMNavigationDestination, Never>(.root(ParityRoot.home))
        let adapter = RUMNavigationObservedTransitions(
            updates: updates,
            destination: { $0 },
            metadata: .automatic
        )
        let source = try XCTUnwrap(adapter.transitions)
        var snapshots = Array(repeating: [SemanticSnapshot](), count: 3)
        var nested = false
        var observations: [UUID] = []
        for index in snapshots.indices {
            observations.append(source.observe { snapshot in
                snapshots[index].append(Self.semanticSnapshot(snapshot))
                if snapshot.generation == 1, !nested {
                    nested = true
                    updates.send(.presentation(ParityPresentation.compose))
                    XCTAssertTrue(snapshots.allSatisfy { $0.last?.name == "Compose" })
                }
            })
        }

        updates.send(.route(ParityRoute.thread(42)))

        XCTAssertTrue(nested)
        for delivered in snapshots {
            XCTAssertEqual(delivered.last?.name, "Compose")
            XCTAssertEqual(delivered.map(\.generation), delivered.map(\.generation).sorted())
            XCTAssertEqual(delivered.filter { $0.generation == 2 }.count, 1)
        }
        observations.forEach(source.removeObserver)
    }

    func testTransitionSourceCanWaitForSceneDependentInitialMetadata() {
        let source = RUMNavigationTransitions()
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observation = source.observe { snapshots.append($0) }

        XCTAssertTrue(snapshots.isEmpty)

        source.setInitialDestination(RUMView(name: "Resolved Home"))
        source.setInitialDestination(RUMView(name: "Ignored Duplicate"))

        XCTAssertEqual(snapshots.map(\.destination.name), ["Resolved Home"])
        XCTAssertEqual(snapshots.map(\.generation), [0])
        source.removeObserver(observation)
    }

    func testNavigationInputsProduceEquivalentAcceptedDestinationTimeline() throws {
        let destinations: [RUMNavigationDestination] = [
            .root(ParityRoot.home),
            .route(ParityRoute.thread(42), occurrence: 1),
            .route(ParityRoute.thread(42), occurrence: 2),
            .presentation(ParityPresentation.compose),
            .presentation(ParityPresentation.attachmentPreview),
            .root(ParityRoot.home)
        ]
        let metadata = RUMNavigationMetadata.automatic(in: "parity")
        let expected = destinations.enumerated().map { index, destination in
            let view = metadata.view(for: destination)
            return SemanticSnapshot(
                generation: UInt64(index),
                name: view.name,
                path: view.path
            )
        }

        let updates = CurrentValueSubject<RUMNavigationDestination, Never>(
            destinations[0]
        )
        let observedAdapter = RUMNavigationObservedTransitions(
            updates: updates,
            destination: { $0 },
            metadata: metadata
        )
        let observedSource = try XCTUnwrap(observedAdapter.transitions)
        var observedSnapshots: [SemanticSnapshot] = []
        let observedObservation = observedSource.observe {
            observedSnapshots.append(Self.semanticSnapshot($0))
        }
        updates.send(destinations[0])
        destinations.dropFirst().forEach(updates.send)
        observedSource.removeObserver(observedObservation)

        let explicitSource = RUMNavigationTransitions(
            currentDestination: metadata.view(for: destinations[0])
        )
        var explicitSnapshots: [SemanticSnapshot] = []
        let explicitObservation = explicitSource.observe {
            explicitSnapshots.append(Self.semanticSnapshot($0))
        }
        explicitSource.willNavigate(
            id: "cancelled-proposal",
            destination: RUMView(name: "Cancelled")
        )
        explicitSource.cancel(id: "cancelled-proposal")
        explicitSource.commit(id: "cancelled-proposal")
        Self.commit(
            destinations: destinations.dropFirst(),
            metadata: metadata,
            to: explicitSource
        )
        explicitSource.removeObserver(explicitObservation)

        let capabilitySource = RUMNavigationTransitions(
            currentDestination: metadata.view(for: destinations[0])
        )
        let capabilityContent = ProvidingContent(source: capabilitySource)
        let resolvedCapability = try XCTUnwrap(
            RUMNavigationHost<ProvidingContent>.resolveTransitions(
                explicit: nil,
                content: capabilityContent
            )
        )
        var capabilitySnapshots: [SemanticSnapshot] = []
        let capabilityObservation = resolvedCapability.observe {
            capabilitySnapshots.append(Self.semanticSnapshot($0))
        }
        Self.commit(
            destinations: destinations.dropFirst(),
            metadata: metadata,
            to: resolvedCapability
        )
        resolvedCapability.removeObserver(capabilityObservation)

        XCTAssertEqual(observedSnapshots, expected)
        XCTAssertEqual(explicitSnapshots, expected)
        XCTAssertEqual(capabilitySnapshots, expected)
        XCTAssertNil(
            RUMNavigationHost<SwiftUI.Text>.resolveTransitions(
                explicit: nil,
                content: SwiftUI.Text("Opaque")
            )
        )
    }

#if compiler(>=6.4)
    func testObservationAdapterRearmsSynchronouslyAfterEachDidSet() throws {
        let model = ObservationNavigationModel(
            destination: .root(ParityRoot.home)
        )
        let metadata = RUMNavigationMetadata.automatic(in: "observation")
        let adapter = RUMNavigationObservedTransitions(
            observingCurrentDestination: { model.destination },
            metadata: metadata
        )
        let source = try XCTUnwrap(adapter.transitions)
        var order: [String] = []
        var generations: [UInt64] = []
        let observation = source.observe { snapshot in
            generations.append(snapshot.generation)
            order.append(snapshot.destination.name)
        }

        model.destination = .route(ParityRoute.thread(42), occurrence: 1)
        order.append("after-route-1")
        model.destination = .route(ParityRoute.thread(42), occurrence: 2)
        order.append("after-route-2")
        model.destination = .presentation(ParityPresentation.compose)
        order.append("after-presentation")
        model.destination = .root(ParityRoot.home)
        order.append("after-root")

        XCTAssertEqual(
            order,
            [
                "Home",
                "Thread",
                "after-route-1",
                "Thread",
                "after-route-2",
                "Compose",
                "after-presentation",
                "Home",
                "after-root"
            ]
        )
        XCTAssertEqual(generations, [0, 1, 2, 3, 4])
        source.removeObserver(observation)
    }

    func testObservationAdapterRearmsBeforeNestedObserverMutation() throws {
        let model = ObservationNavigationModel(
            destination: .root(ParityRoot.home)
        )
        let adapter = RUMNavigationObservedTransitions(
            observingCurrentDestination: { model.destination },
            metadata: .automatic
        )
        let source = try XCTUnwrap(adapter.transitions)
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        var performedNestedMutation = false
        let observation = source.observe { snapshot in
            snapshots.append(snapshot)
            if snapshot.destination.name == "Thread",
               !performedNestedMutation {
                performedNestedMutation = true
                model.destination = .presentation(ParityPresentation.compose)
            }
        }

        model.destination = .route(ParityRoute.thread(42), occurrence: 1)
        model.destination = .root(ParityRoot.home)

        XCTAssertEqual(
            snapshots.map(\.destination.name),
            ["Home", "Thread", "Compose", "Home"]
        )
        XCTAssertEqual(snapshots.map(\.generation), [0, 1, 2, 3])
        source.removeObserver(observation)
    }

    func testObservationAdapterNestedMutationKeepsEveryObserverOnLatestDestination() throws {
        let model = ObservationNavigationModel(destination: .root(ParityRoot.home))
        let adapter = RUMNavigationObservedTransitions(
            observingCurrentDestination: { model.destination },
            metadata: .automatic
        )
        let source = try XCTUnwrap(adapter.transitions)
        var snapshots = Array(repeating: [SemanticSnapshot](), count: 3)
        var nested = false
        var observations: [UUID] = []
        for index in snapshots.indices {
            observations.append(source.observe { snapshot in
                snapshots[index].append(Self.semanticSnapshot(snapshot))
                if snapshot.generation == 1, !nested {
                    nested = true
                    model.destination = .presentation(ParityPresentation.compose)
                    XCTAssertTrue(snapshots.allSatisfy { $0.last?.name == "Compose" })
                }
            })
        }

        model.destination = .route(ParityRoute.thread(42))

        XCTAssertTrue(nested)
        for delivered in snapshots {
            XCTAssertEqual(delivered.last?.name, "Compose")
            XCTAssertEqual(delivered.map(\.generation), delivered.map(\.generation).sorted())
            XCTAssertEqual(delivered.filter { $0.generation == 2 }.count, 1)
        }
        observations.forEach(source.removeObserver)
    }

    func testObservationAdapterTreatsIndependentPropertyMutationsAsSeparateStates() throws {
        let model = MultiPropertyObservationNavigationModel()
        let adapter = RUMNavigationObservedTransitions(
            observingCurrentDestination: {
                if let presentation = model.presentation {
                    return .presentation(presentation)
                }
                if let route = model.route {
                    return .route(route)
                }
                return .root(ParityRoot.home)
            },
            metadata: .automatic
        )
        let source = try XCTUnwrap(adapter.transitions)
        var names: [String] = []
        let observation = source.observe { names.append($0.destination.name) }

        // Each independently observed property mutation is a committed signal.
        // Customers that need an atomic composite destination must expose one
        // accepted-state property rather than project sequential properties.
        model.route = 42
        model.presentation = "compose"

        XCTAssertEqual(names, ["Home", "Int", "String"])
        source.removeObserver(observation)
    }

    func testObservationAdapterStopsRearmingAfterDeallocation() throws {
        let model = ObservationNavigationModel(
            destination: .root(ParityRoot.home)
        )
        var adapter: RUMNavigationObservedTransitions? =
            RUMNavigationObservedTransitions(
                observingCurrentDestination: { model.destination },
                metadata: .automatic
            )
        weak var weakAdapter = adapter
        let source = try XCTUnwrap(adapter?.transitions)
        var names: [String] = []
        let observation = source.observe { names.append($0.destination.name) }

        adapter = nil
        XCTAssertNil(weakAdapter)
        model.destination = .route(ParityRoute.thread(42), occurrence: 1)

        XCTAssertEqual(names, ["Home"])
        source.removeObserver(observation)
    }

    func testObservationNavigationHostTracksOnceAcrossSwiftUIReconstruction() async {
        let renderModel = ObservedHostReconstructionModel()
        let navigationModel = ObservationNavigationModel(
            destination: .root(ParityRoot.home)
        )
        let counter = ObservationCounter()
        let hostingController = UIHostingController(
            rootView: ObservationHostReconstructionHarness(
                renderModel: renderModel,
                navigationModel: navigationModel,
                counter: counter
            )
        )
        let window = UIWindow()
        window.rootViewController = hostingController
        window.makeKeyAndVisible()

        hostingController.view.layoutIfNeeded()
        await drainMainQueue()

        XCTAssertEqual(counter.projections, 1)
        XCTAssertTrue(counter.renderedSelections.contains(false))

        renderModel.useSecondPublisher = true
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        await drainMainQueue()

        XCTAssertEqual(counter.projections, 1)
        XCTAssertTrue(counter.renderedSelections.contains(true))

        navigationModel.destination = .route(
            ParityRoute.thread(42),
            occurrence: 1
        )

        XCTAssertEqual(counter.projections, 2)
    }

    func testObservationAdapterRemainsCrashSafeForBackgroundMutation() async throws {
        let model = BackgroundObservationNavigationModel(
            destination: .root(ParityRoot.home)
        )
        let adapter = RUMNavigationObservedTransitions(
            observingCurrentDestination: { model.destination },
            metadata: .automatic
        )
        let source = try XCTUnwrap(adapter.transitions)
        var names: [String] = []
        let observation = source.observe { names.append($0.destination.name) }
        let mutationFinished = expectation(description: "background mutation finished")

        DispatchQueue.global().async {
            model.destination = .route(ParityRoute.thread(42), occurrence: 1)
            mutationFinished.fulfill()
        }
        await fulfillment(of: [mutationFinished], timeout: 1)
        await drainMainQueue()

        XCTAssertEqual(names, ["Home", "Thread"])
        source.removeObserver(observation)
    }
#endif

    func testNavigationHostResolvesOptionalCapability() {
        let source = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Home")
        )
        let content = ProvidingContent(source: source)

        let resolved = RUMNavigationHost<ProvidingContent>.resolveTransitions(
            explicit: nil,
            content: content
        )

        XCTAssertTrue(resolved === source)
    }

    func testExplicitTransitionSourceOverridesOptionalCapability() {
        let capabilitySource = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Capability")
        )
        let explicitSource = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Explicit")
        )
        let content = ProvidingContent(source: capabilitySource)

        let resolved = RUMNavigationHost<ProvidingContent>.resolveTransitions(
            explicit: explicitSource,
            content: content
        )

        XCTAssertTrue(resolved === explicitSource)
    }

    func testConfiguredObservedSourceDoesNotFallThroughToCapabilityWhilePending() {
        let capabilitySource = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Capability")
        )
        let content = ProvidingContent(source: capabilitySource)

        let resolved = RUMNavigationHost<ProvidingContent>.resolveTransitions(
            explicit: nil,
            content: content,
            allowsCapabilityFallback: false
        )

        XCTAssertNil(resolved)
    }

    func testHostStatePinsFirstSourceAcrossContainerReconstruction() {
        let first = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Home")
        )
        let reconstructed = RUMNavigationTransitions(
            currentDestination: RUMView(name: "Reconstructed")
        )
        let hostState = RUMSemanticNavigationHostState()

        hostState.reconcile(transitions: first, viewsHandler: nil)
        hostState.reconcile(transitions: reconstructed, viewsHandler: nil)

        XCTAssertTrue(hostState.selectedTransitions === first)
        XCTAssertFalse(hostState.suppressionState.isActive)

        hostState.finalDetach()

        XCTAssertNil(hostState.selectedTransitions)
        XCTAssertFalse(hostState.suppressionState.isActive)
    }

    func testObservedNavigationHostSubscribesOnceAcrossSwiftUIReconstruction() async {
        let model = ObservedHostReconstructionModel()
        let firstCounter = ObservationCounter()
        let secondCounter = ObservationCounter()
        let renderCounter = ObservationCounter()
        let first = CurrentValueSubject<Int, Never>(1)
            .handleEvents(receiveSubscription: { _ in
                firstCounter.recordSubscription()
            })
            .eraseToAnyPublisher()
        let second = CurrentValueSubject<Int, Never>(2)
            .handleEvents(receiveSubscription: { _ in
                secondCounter.recordSubscription()
            })
            .eraseToAnyPublisher()
        let hostingController = UIHostingController(
            rootView: ObservedHostReconstructionHarness(
                model: model,
                first: first,
                second: second,
                renderCounter: renderCounter
            )
        )
        let window = UIWindow()
        window.rootViewController = hostingController
        window.makeKeyAndVisible()

        hostingController.view.layoutIfNeeded()
        await drainMainQueue()

        XCTAssertEqual(firstCounter.subscriptions, 1)
        XCTAssertEqual(secondCounter.subscriptions, 0)
        XCTAssertTrue(renderCounter.renderedSelections.contains(false))

        model.useSecondPublisher = true
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        await drainMainQueue()

        XCTAssertEqual(firstCounter.subscriptions, 1)
        XCTAssertEqual(secondCounter.subscriptions, 0)
        XCTAssertTrue(renderCounter.renderedSelections.contains(true))
    }

    private func drainMainQueue() async {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 1)
    }

    private static func semanticSnapshot(
        _ snapshot: RUMNavigationTransitions.Snapshot
    ) -> SemanticSnapshot {
        SemanticSnapshot(
            generation: snapshot.generation,
            name: snapshot.destination.name,
            path: snapshot.destination.path
        )
    }

    private static func commit(
        destinations: ArraySlice<RUMNavigationDestination>,
        metadata: RUMNavigationMetadata,
        to source: RUMNavigationTransitions
    ) {
        for destination in destinations {
            let id = UUID().uuidString
            source.willNavigate(
                id: id,
                destination: metadata.view(for: destination)
            )
            source.commit(id: id)
        }
    }
}

@available(iOS 27.0, *)
@MainActor
final class RUMSemanticNavigationContainerLifetimeStateTests: XCTestCase {
    func testWhenDetachedStateIsReleased_queuedFinalDetachStillRuns() async {
        var state: RUMSemanticNavigationContainerLifetimeState? =
            RUMSemanticNavigationContainerLifetimeState()
        var didDetach = false
        let drained = expectation(description: "main queue drained")
        state?.reconcile(attachment: .detached) {
            didDetach = true
        }

        state = nil
        DispatchQueue.main.async {
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 1)

        XCTAssertTrue(didDetach)
    }

    func testWhenDetachedStateReattaches_queuedFinalDetachIsCancelled() async {
        let state = RUMSemanticNavigationContainerLifetimeState()
        var didDetach = false
        let drained = expectation(description: "main queue drained")
        state.reconcile(attachment: .detached) {
            didDetach = true
        }
        state.reconcile(attachment: .attached(RUMSceneIdentifier(rawValue: "scene-A"))) {
            XCTFail("An attachment must not schedule teardown")
        }

        DispatchQueue.main.async {
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 1)

        XCTAssertFalse(didDetach)
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

    func testWhenDormantBoundaryPromotionCommits_itStartsAcceptedDestinationOnce() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1", "duplicate"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, proposed)
        XCTAssertFalse(state.isAppeared)

        coordinator.complete(isCancelled: false)
        coordinators[sceneA] = nil
        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenDormantBoundaryPromotionIsCancelled_itLeavesDormantStateUntouched() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["unused"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        let revision = state.revision
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, proposed)
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(state.lifecycleGeneration, 0)
        XCTAssertEqual(state.revision, revision)
        XCTAssertEqual(identities.invocationCount, 0)
    }

    func testWhenSceneDisconnectsDuringDormantPromotion_readerRemountStartsAcceptedDestination() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.discard(sceneIdentifier: sceneA)
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertTrue(state.needsReaderRemount)

        coordinators[sceneA] = nil
        arbiter.process(
            .keyedMount(
                configuration: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenDormantPromotionDisappearsBeforeCommit_laterAcceptedAppearanceCanStart() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: accepted,
                attachment: nil,
                isAppeared: false
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(state.lifecycleGeneration, 0)

        coordinators[sceneA] = nil
        arbiter.process(
            .reconcile(
                configuration: accepted,
                attachment: .attached(sceneA),
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenStaleDetachedCallbackFollowsDormantPromotion_itCannotCancelPromotion() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        let staleDetached = keyedConfiguration("stale-detail", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: staleDetached,
                attachment: .detached,
                isAppeared: nil
            ),
            state: state
        ) {
            recorder.send(source: "stale-detail", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenGenericConfigurationAttemptsToSupersedeDormantPromotion_itIsIgnored() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        let later = keyedConfiguration("later", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: later,
                attachment: .attached(sceneA),
                isAppeared: nil
            ),
            state: state
        ) {
            recorder.send(source: "later", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(state.lifecycleGeneration, 1)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenUnscopedAppearanceAttemptsToSupersedeDormantPromotion_itIsIgnored() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposed = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        let later = keyedConfiguration("later", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposed,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposed,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: later,
                attachment: nil,
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "later", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-1", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(recorder.entries.map(\.source), ["alternate"])
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .attached(sceneA))
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenSourceAcceptedGenerationAdvances_itSupersedesPendingPromotion() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["later-2"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposal = nonCurrentConfiguration("detail", generation: 1)
        let firstAccepted = keyedConfiguration("alternate", generation: 1)
        let laterAccepted = keyedConfiguration("later", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposal,
                accepted: firstAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.process(
            .promoteDormantBoundary(
                expected: proposal,
                accepted: laterAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "later", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "later-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(recorder.entries.map(\.source), ["later"])
        XCTAssertEqual(state.configuration, laterAccepted)
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenDetachedSourceAcceptedGenerationAdvances_itSuppressesPendingPromotion() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["later-2"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposal = nonCurrentConfiguration("detail", generation: 1)
        let firstAccepted = keyedConfiguration("alternate", generation: 1)
        let laterAccepted = keyedConfiguration("later", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: proposal,
                accepted: firstAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.process(
            .settleDormantBoundary(
                expected: proposal,
                accepted: laterAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "later", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, laterAccepted)
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertTrue(state.needsReaderRemount)
        XCTAssertEqual(identities.invocationCount, 0)
        XCTAssertFalse(state.invalidateAfterSceneDisconnect(sceneA))
        XCTAssertTrue(state.needsReaderRemount)

        coordinators[sceneA] = nil
        arbiter.process(
            .keyedMount(
                configuration: laterAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "later", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "later-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenDetachedSettlementReceivesOrdinaryLifecycle_itRemainsNonStarting() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-1"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposal = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .settleDormantBoundary(
                expected: proposal,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: accepted,
                attachment: .attached(sceneA),
                isAppeared: nil
            ),
            state: state
        ) {
            recorder.send(source: "ordinary-attachment", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: accepted,
                attachment: nil,
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "ordinary-appearance", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertTrue(state.needsReaderRemount)
        XCTAssertEqual(identities.invocationCount, 0)

        coordinators[sceneA] = nil
        arbiter.process(
            .reconcile(
                configuration: accepted,
                attachment: nil,
                isAppeared: true
            ),
            state: state
        ) {
            recorder.send(source: "post-commit-appearance", transitions: $0)
        }

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertTrue(state.needsReaderRemount)
        XCTAssertEqual(identities.invocationCount, 0)
    }

    func testWhenAcceptedReaderMovesScenes_itReplacesPendingSettlementAndStartsThere() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-B"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposal = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .settleDormantBoundary(
                expected: proposal,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "settlement-A", transitions: $0)
        }
        arbiter.process(
            .migrateDormantBoundary(
                expected: proposal,
                accepted: accepted,
                sceneIdentifier: sceneB
            ),
            state: state
        ) {
            recorder.send(source: "reader-B", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-B", sceneIdentifier: sceneB)]
        )
        XCTAssertEqual(recorder.entries.map(\.source), ["reader-B"])
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .attached(sceneB))
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)

        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries.count, 1)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenGenericReconciliationMovesScenes_itCannotReplacePendingSettlement() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["unused"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let proposal = nonCurrentConfiguration("detail", generation: 1)
        let accepted = keyedConfiguration("alternate", generation: 1)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: proposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .settleDormantBoundary(
                expected: proposal,
                accepted: accepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "settlement-A", transitions: $0)
        }
        arbiter.process(
            .reconcile(
                configuration: accepted,
                attachment: .attached(sceneB),
                isAppeared: nil
            ),
            state: state
        ) {
            recorder.send(source: "generic-B", transitions: $0)
        }

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, proposal)
        XCTAssertEqual(state.attachment, .attached(sceneA))

        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, accepted)
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertTrue(state.needsReaderRemount)
        XCTAssertEqual(identities.invocationCount, 0)
    }

    func testWhenSourceAuthorizedPromotionAdvances_itRebasesToLatestDormantSnapshot() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-2"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let firstProposal = nonCurrentConfiguration("detail", generation: 1)
        let firstAccepted = keyedConfiguration("alternate", generation: 1)
        let secondProposal = nonCurrentConfiguration("later-proposal", generation: 2)
        let secondAccepted = keyedConfiguration("later-accepted", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: firstProposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: firstProposal,
                accepted: firstAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        let initialRevision = state.revision
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: secondProposal,
                attachment: .attached(sceneA)
            )
        )
        XCTAssertGreaterThan(state.revision, initialRevision)
        arbiter.process(
            .promoteDormantBoundary(
                expected: secondProposal,
                accepted: secondAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "later-accepted", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(recorder.entries.map(\.source), ["later-accepted"])
        XCTAssertEqual(state.configuration, secondAccepted)
        XCTAssertTrue(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenSourceAuthorizedDetachedSettlementAdvances_itWaitsForReaderMount() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["alternate-2"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let firstProposal = nonCurrentConfiguration("detail", generation: 1)
        let firstAccepted = keyedConfiguration("alternate", generation: 1)
        let secondProposal = nonCurrentConfiguration("later-proposal", generation: 2)
        let secondAccepted = keyedConfiguration("later-accepted", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: firstProposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: firstProposal,
                accepted: firstAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: secondProposal,
                attachment: .attached(sceneA)
            )
        )
        arbiter.process(
            .settleDormantBoundary(
                expected: secondProposal,
                accepted: secondAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "later-accepted", transitions: $0)
        }
        coordinator.complete(isCancelled: false)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, secondAccepted)
        XCTAssertEqual(state.attachment, .detached)
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 0)

        coordinators[sceneA] = nil
        arbiter.process(
            .keyedMount(
                configuration: secondAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "later-accepted", transitions: $0)
        }

        XCTAssertEqual(
            recorder.entries.map(\.transition),
            [.start(identity: "alternate-2", sceneIdentifier: sceneA)]
        )
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testWhenAdvancedDormantResolutionIsCancelled_itStartsNoDestination() {
        let coordinator = RUMSwiftUITransitionCoordinatorMock()
        coordinators[sceneA] = coordinator
        let identities = RUMOccurrenceIdentityGenerator(["unused"])
        let state = RUMViewTrackingState(
            identity: "platform-destination",
            occurrenceIdentityGenerator: identities.next
        )
        let firstProposal = nonCurrentConfiguration("detail", generation: 1)
        let firstAccepted = keyedConfiguration("alternate", generation: 1)
        let secondProposal = nonCurrentConfiguration("later-proposal", generation: 2)
        let secondAccepted = keyedConfiguration("later-accepted", generation: 2)
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: firstProposal,
                attachment: .attached(sceneA)
            )
        )
        let recorder = RUMSwiftUITransitionRecorder()

        arbiter.process(
            .promoteDormantBoundary(
                expected: firstProposal,
                accepted: firstAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "alternate", transitions: $0)
        }
        XCTAssertTrue(
            state.recordDormantNavigationBoundary(
                configuration: secondProposal,
                attachment: .attached(sceneA)
            )
        )
        arbiter.process(
            .promoteDormantBoundary(
                expected: secondProposal,
                accepted: secondAccepted,
                sceneIdentifier: sceneA
            ),
            state: state
        ) {
            recorder.send(source: "later-accepted", transitions: $0)
        }
        coordinator.complete(isCancelled: true)

        XCTAssertEqual(recorder.entries, [])
        XCTAssertEqual(state.configuration, secondProposal)
        XCTAssertFalse(state.isAppeared)
        XCTAssertEqual(identities.invocationCount, 0)
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

    private func nonCurrentConfiguration(
        _ key: String,
        generation: UInt64
    ) -> RUMViewTrackingState.Configuration {
        RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey(key),
            bindingGeneration: generation,
            descriptor: .init(name: key, path: "/\(key)", attributes: [:]),
            isCurrentDestination: false
        )
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

@available(iOS 27.0, *)
@MainActor
final class RUMSwiftUISemanticNavigationStateTests: XCTestCase {
    private struct Presentation: Identifiable {
        let id: String
    }

    private let scene = RUMSceneIdentifier(rawValue: "scene-A")

    func testCommittedPop_revealsHomeAsFreshOccurrenceBeforeRetainedContentRemounts() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: [])
        let initialHome = navigationState.rootOccurrence
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "home-2"])
        let viewState = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initialConfiguration = configuration(for: initialHome, name: "Home")
        _ = viewState.mount(in: scene, configuration: initialConfiguration)
        _ = viewState.disappear(configuration: initialConfiguration)
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: navigationState.occurrenceSource,
            state: viewState,
            configuration: initialConfiguration,
            attachment: .attached(scene)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: viewState.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        navigationState.reconcile(path: ["details"])
        navigationState.reconcile(path: [])

        let returnedHome = navigationState.rootOccurrence
        XCTAssertEqual(returnedHome.key, initialHome.key)
        XCTAssertGreaterThan(returnedHome.generation, initialHome.generation)
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-2", sceneIdentifier: scene)]
        )
        XCTAssertEqual(viewState.configuration?.bindingGeneration, returnedHome.generation)
        XCTAssertEqual(identities.invocationCount, 2)
    }

    func testInitialRestoredPath_revealsNeverStartedHiddenHomeBeforeRemount() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: ["details"])
        let hiddenHome = navigationState.rootOccurrence
        let identities = RUMOccurrenceIdentityGenerator(["home-1"])
        let viewState = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let hiddenConfiguration = configuration(for: hiddenHome, name: "Home")

        XCTAssertFalse(hiddenHome.isCurrentDestination)
        XCTAssertTrue(
            viewState.update(
                configuration: hiddenConfiguration,
                attachment: .attached(scene)
            ).isEmpty
        )
        XCTAssertEqual(viewState.lifecycleGeneration, 0)

        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: navigationState.occurrenceSource,
            state: viewState,
            configuration: hiddenConfiguration,
            attachment: .attached(scene)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: viewState.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        navigationState.reconcile(path: [])

        let revealedHome = navigationState.rootOccurrence
        XCTAssertTrue(revealedHome.isCurrentDestination)
        XCTAssertEqual(
            transitions,
            [.start(identity: "home-1", sceneIdentifier: scene)]
        )
        XCTAssertEqual(viewState.configuration?.bindingGeneration, revealedHome.generation)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testPathThatPushesAndRevertsBeforeRootDisappears_createsNoIntermediateOccurrence() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: [])
        let initialHome = navigationState.rootOccurrence
        let identities = RUMOccurrenceIdentityGenerator(["home-1", "unused"])
        let viewState = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initialConfiguration = configuration(for: initialHome, name: "Home")
        _ = viewState.mount(in: scene, configuration: initialConfiguration)
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: navigationState.occurrenceSource,
            state: viewState,
            configuration: initialConfiguration,
            attachment: .attached(scene)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: viewState.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        navigationState.reconcile(path: ["details"])
        navigationState.reconcile(path: [])

        XCTAssertTrue(transitions.isEmpty)
        XCTAssertTrue(viewState.isAppeared)
        XCTAssertEqual(identities.invocationCount, 1)
    }

    func testRepeatedEqualRoute_retainsEachMaterializedPathPositionAcrossPushAndPop() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: [])
        navigationState.reconcile(path: ["details"])

        let firstClaim = navigationState.makeOccurrenceClaim(for: "details")
        let firstOccurrence = navigationState.occurrence(
            for: "details",
            retaining: firstClaim
        )
        let identities = RUMOccurrenceIdentityGenerator(["details-1", "details-3"])
        let viewState = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let firstConfiguration = configuration(
            for: firstOccurrence,
            name: "Details"
        )
        _ = viewState.mount(in: scene, configuration: firstConfiguration)
        _ = viewState.disappear(configuration: firstConfiguration)
        let registration = RUMSwiftUINavigationOccurrenceRegistration()
        var transitions: [RUMViewTrackingState.Transition] = []
        registration.rebind(
            to: navigationState.occurrenceSource,
            state: viewState,
            configuration: firstConfiguration,
            attachment: .attached(scene)
        ) { configuration, sceneIdentifier in
            transitions.append(
                contentsOf: viewState.reconcile(
                    configuration: configuration,
                    attachment: .attached(sceneIdentifier),
                    isAppeared: true
                )
            )
        }

        navigationState.reconcile(path: ["details", "details"])
        let retainedFirstOccurrence = navigationState.occurrence(
            for: "details",
            retaining: firstClaim
        )
        let secondClaim = navigationState.makeOccurrenceClaim(for: "details")
        let secondOccurrence = navigationState.occurrence(
            for: "details",
            retaining: secondClaim
        )

        XCTAssertEqual(retainedFirstOccurrence.key, firstOccurrence.key)
        XCTAssertNotEqual(secondOccurrence.key, firstOccurrence.key)

        navigationState.reconcile(path: ["details"])

        let revealedFirstOccurrence = navigationState.occurrence(
            for: "details",
            retaining: firstClaim
        )
        XCTAssertEqual(revealedFirstOccurrence.key, firstOccurrence.key)
        XCTAssertGreaterThan(revealedFirstOccurrence.generation, firstOccurrence.generation)
        XCTAssertEqual(
            transitions,
            [.start(identity: "details-3", sceneIdentifier: scene)]
        )
        XCTAssertEqual(
            viewState.configuration?.bindingGeneration,
            revealedFirstOccurrence.generation
        )
        XCTAssertEqual(identities.invocationCount, 2)
    }

    func testRepeatedEqualRoute_restoredTogether_targetsOnlyMaterializedTopPosition() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: ["details", "details"])

        let materializedClaim = navigationState.makeOccurrenceClaim(for: "details")
        let initialTop = navigationState.occurrence(
            for: "details",
            retaining: materializedClaim
        )

        XCTAssertFalse(navigationState.rootOccurrence.isCurrentDestination)
        XCTAssertTrue(initialTop.isCurrentDestination)

        navigationState.reconcile(path: ["details"])
        let revealedDestination = navigationState.occurrence(
            for: "details",
            retaining: materializedClaim
        )

        XCTAssertTrue(revealedDestination.isCurrentDestination)
        XCTAssertNotEqual(revealedDestination.key, initialTop.key)
        XCTAssertGreaterThan(revealedDestination.generation, initialTop.generation)
    }

    func testRepeatedEqualRoute_restoredTogether_replacesTopWhenItsPositionIsRemoved() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: ["details", "details"])
        let materializedClaim = navigationState.makeOccurrenceClaim(for: "details")
        let initialTop = navigationState.occurrence(
            for: "details",
            retaining: materializedClaim
        )
        let identities = RUMOccurrenceIdentityGenerator(["details-1", "details-2"])
        let viewState = RUMViewTrackingState(
            identity: "fallback",
            occurrenceIdentityGenerator: identities.next
        )
        let initialConfiguration = configuration(for: initialTop, name: "Details")

        XCTAssertEqual(
            viewState.mount(in: scene, configuration: initialConfiguration),
            [.start(identity: "details-1", sceneIdentifier: scene)]
        )

        navigationState.reconcile(path: ["details"])
        let revealedDestination = navigationState.occurrence(
            for: "details",
            retaining: materializedClaim
        )
        let revealedConfiguration = configuration(
            for: revealedDestination,
            name: "Details"
        )

        XCTAssertEqual(
            viewState.reconcile(
                configuration: revealedConfiguration,
                attachment: .attached(scene),
                isAppeared: true
            ),
            [
                .replace(
                    oldIdentity: "details-1",
                    newIdentity: "details-2",
                    sceneIdentifier: scene
                )
            ]
        )
        XCTAssertEqual(identities.invocationCount, 2)
    }

    func testOccurrenceClaim_whenBoundaryRouteChanges_adoptsCurrentRoutePosition() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: ["details"])
        let claim = navigationState.makeOccurrenceClaim(for: "details")
        let detailsOccurrence = navigationState.occurrence(
            for: "details",
            retaining: claim
        )

        navigationState.reconcile(path: ["alternate"])
        let alternateOccurrence = navigationState.occurrence(
            for: "alternate",
            retaining: claim
        )

        XCTAssertNotEqual(alternateOccurrence.key, detailsOccurrence.key)
        XCTAssertEqual(
            alternateOccurrence.key,
            navigationState.occurrence(for: "alternate").key
        )
    }

    func testForward_whenCustomerBindingRejectsProposedPath_reconcilesAcceptedPath() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: [])
        let initialGeneration = navigationState.bindingGeneration
        let acceptedPath: [String] = []
        let rejectingBinding = Binding<[String]>(
            get: { acceptedPath },
            set: { _ in }
        )

        navigationState.forward(
            proposedPath: ["details"],
            to: rejectingBinding,
            transaction: Transaction()
        )

        XCTAssertTrue(acceptedPath.isEmpty)
        XCTAssertEqual(navigationState.bindingGeneration, initialGeneration)
    }

    func testForward_whenCustomerBindingCanonicalizesProposedPath_reconcilesCanonicalPath() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: [])
        var acceptedPath: [String] = []
        let canonicalizingBinding = Binding<[String]>(
            get: { acceptedPath },
            set: { acceptedPath = Array($0.prefix(1)) }
        )

        navigationState.forward(
            proposedPath: ["details", "ignored"],
            to: canonicalizingBinding,
            transaction: Transaction()
        )
        let acceptedGeneration = navigationState.bindingGeneration
        let acceptedOccurrence = navigationState.occurrence(for: "details")

        navigationState.forward(
            proposedPath: ["details", "still-ignored"],
            to: canonicalizingBinding,
            transaction: Transaction()
        )

        XCTAssertEqual(acceptedPath, ["details"])
        XCTAssertEqual(acceptedOccurrence.key, navigationState.occurrence(for: "details").key)
        XCTAssertEqual(navigationState.bindingGeneration, acceptedGeneration)
    }

    func testForward_whenPendingBootstrapIsCanonicalized_onlyAcceptedDestinationCanAdopt() {
        let navigationState = RUMSwiftUISemanticNavigationState<String, Presentation>()
        navigationState.reconcile(path: ["details"])
        let detailsConfiguration = configuration(
            for: navigationState.occurrence(for: "details"),
            name: "Details"
        )
        navigationState.occurrenceSource.reconcileCurrentDestination(
            configuration: detailsConfiguration,
            viewsHandler: nil
        )
        let donorState = RUMViewTrackingState(
            identity: "root-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["details-1"]).next
        )
        let hiddenRootConfiguration = configuration(
            for: navigationState.rootOccurrence,
            name: "Home"
        )
        _ = navigationState.occurrenceSource.resolveCandidate(
            candidateConfiguration: hiddenRootConfiguration,
            sceneIdentifier: scene,
            state: donorState,
            viewsHandler: nil
        ) { configuration, sceneIdentifier in
            _ = donorState.mountInitialNavigationDestination(
                in: sceneIdentifier,
                configuration: configuration
            )
        }

        var acceptedPath = ["details"]
        let canonicalizingBinding = Binding<[String]>(
            get: { acceptedPath },
            set: { acceptedPath = Array($0.prefix(1)) }
        )
        navigationState.forward(
            proposedPath: ["alternate", "ignored"],
            to: canonicalizingBinding,
            transaction: Transaction()
        )
        let alternateConfiguration = configuration(
            for: navigationState.occurrence(for: "alternate"),
            name: "Alternate"
        )
        navigationState.occurrenceSource.reconcileCurrentDestination(
            configuration: alternateConfiguration,
            viewsHandler: nil
        )
        let staleState = RUMViewTrackingState(identity: "stale-fallback")
        let alternateState = RUMViewTrackingState(
            identity: "alternate-fallback",
            occurrenceIdentityGenerator: RUMOccurrenceIdentityGenerator(["alternate-1"]).next
        )

        XCTAssertEqual(acceptedPath, ["alternate"])
        XCTAssertEqual(
            navigationState.occurrenceSource.resolveCandidate(
                candidateConfiguration: detailsConfiguration,
                sceneIdentifier: scene,
                state: staleState,
                viewsHandler: nil
            ) { _, _ in
                XCTFail("The pre-canonicalization destination must stay suppressed")
            },
            .rejectStale
        )
        XCTAssertEqual(
            navigationState.occurrenceSource.resolveCandidate(
                candidateConfiguration: alternateConfiguration,
                sceneIdentifier: scene,
                state: alternateState,
                viewsHandler: nil
            ) { configuration, sceneIdentifier in
                _ = alternateState.mountInitialNavigationDestination(
                    in: sceneIdentifier,
                    configuration: configuration
                )
            },
            .handled
        )
        XCTAssertNil(donorState.activeLifecycleGeneration)
        XCTAssertEqual(
            alternateState.disappear(configuration: alternateConfiguration),
            [.stop(identity: "alternate-1", sceneIdentifier: scene)]
        )
    }

    private func configuration(
        for occurrence: RUMSwiftUISemanticNavigationState<String, Presentation>.Occurrence,
        name: String
    ) -> RUMViewTrackingState.Configuration {
        RUMViewTrackingState.Configuration(
            occurrenceKey: occurrence.key,
            bindingGeneration: occurrence.generation,
            descriptor: .init(name: name, path: "/\(name)", attributes: [:]),
            isCurrentDestination: occurrence.isCurrentDestination
        )
    }
}
#endif
#endif

#endif
