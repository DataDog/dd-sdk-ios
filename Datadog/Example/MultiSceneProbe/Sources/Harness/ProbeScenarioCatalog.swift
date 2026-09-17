/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

enum ProbeScenarioCatalog {
    static let defaultIdentifier = "interactive.manual"

    private static let observableDriverIdentifiers: Set<String> = [
        "swiftui.stack.return",
        "operations.navigation.lifecycle",
        "operations.cross-scene.lifecycle",
        "operations.explicit-target.cross-scene-serial",
        "actions.explicit-target.cross-scene-serial",
        "actions.explicit-target.long-running-cross-scene-serial",
        "swiftui.stack.abort",
        "swiftui.stack.same-type-replacement",
        "swiftui.stack.different-type-replacement",
        "swiftui.coexistence.semantic-a-automatic-b",
        "swiftui.coexistence.automatic-manual-sheet",
        "swiftui.coexistence.automatic-scene-targeted-sheet",
        "swiftui.coexistence.automatic-scene-targeted-full-screen-cover",
        "swiftui.semantic-api.complete-destination",
        "swiftui.semantic-api.presentation-replacement",
        "swiftui.semantic-api.repeated-value-links",
        "swiftui.semantic-api.initial-repeated-path",
        "swiftui.semantic-api.external-replacements",
        "swiftui.semantic-api.rejected-link-write",
        "swiftui.semantic-api.canonicalized-link-write",
        "swiftui.semantic-api.sibling-container-isolation",
        "swiftui.semantic-host.explicit-source",
        "swiftui.semantic-host.explicit-precedence",
        "swiftui.semantic-host.optional-capability",
        "swiftui.semantic-host.capability-reconstruction",
        "swiftui.semantic-host.capability-replacement",
        "swiftui.semantic-host.transient-reader-reattach",
        "swiftui.semantic-host.final-removal-isolation",
        "swiftui.semantic-host.automatic-fallback",
        "swiftui.semantic-host.router-stream-adapter",
        "swiftui.semantic-host.observation-router-adapter",
        "swiftui.semantic-host.observation-router-two-scenes-serial",
        "swiftui.semantic-host.observation-native-dismiss-callbacks",
        "swiftui.semantic-host.third-party-callback-adapter",
        "swiftui.coexistence.automatic-keyed-manual-view",
        "swiftui.coexistence.nested-keyed-manual-view",
        "swiftui.coexistence.same-key-manual-two-scenes",
        "swiftui.coexistence.sibling-container-authority",
        "swiftui.split.automatic-baseline",
        "swiftui.split.same-type-selection",
        "swiftui.split.retained-return",
        "uikit.split.pop-cancel",
        "uikit.split.pop-finish",
        "actions.uikit-scroll-navigation-deceleration",
        "actions.swiftui-button-structured-task",
        "traces.urlsession-cross-scene",
        "traces.urlsession-shared-request",
        "traces.urlsession-reverse-completion",
        "windows.activation-sequence",
        "windows.close-with-resource"
    ]

    static let all: [ProbeScenario] = [
        interactiveManual,
        automaticSingleWindow,
        automaticTwoWindow,
        swiftUIStackOccurrencePush,
        swiftUIStackReturn,
        operationsNavigationLifecycle,
        operationsCrossSceneLifecycle,
        operationsExplicitTargetCrossSceneSerial,
        actionsExplicitTargetCrossSceneSerial,
        actionsExplicitTargetLongRunningCrossSceneSerial,
        swiftUIStackAbort,
        swiftUIStackSameTypeReplacement,
        swiftUIStackDifferentTypeReplacement,
        swiftUICoexistenceSemanticAAutomaticB,
        swiftUICoexistenceAutomaticManualSheet,
        swiftUICoexistenceAutomaticSceneTargetedSheet,
        swiftUICoexistenceAutomaticSceneTargetedFullScreenCover,
        swiftUISemanticAPICompleteDestination,
        swiftUISemanticAPIPresentationReplacement,
        swiftUISemanticAPIRepeatedValueLinks,
        swiftUISemanticAPIInitialRepeatedPath,
        swiftUISemanticAPIExternalReplacements,
        swiftUISemanticAPIRejectedLinkWrite,
        swiftUISemanticAPICanonicalizedLinkWrite,
        swiftUISemanticAPISiblingContainerIsolation,
        swiftUISemanticHostExplicitSource,
        swiftUISemanticHostExplicitPrecedence,
        swiftUISemanticHostOptionalCapability,
        swiftUISemanticHostCapabilityReconstruction,
        swiftUISemanticHostCapabilityReplacement,
        swiftUISemanticHostTransientReaderReattach,
        swiftUISemanticHostFinalRemovalIsolation,
        swiftUISemanticHostAutomaticFallback,
        swiftUISemanticHostRouterStreamAdapter,
        swiftUISemanticHostObservationRouterAdapter,
        swiftUISemanticHostObservationRouterTwoScenesSerial,
        swiftUISemanticHostObservationNativeDismissCallbacks,
        swiftUISemanticHostThirdPartyCallbackAdapter,
        swiftUICoexistenceAutomaticKeyedManualView,
        swiftUICoexistenceNestedKeyedManualView,
        swiftUICoexistenceSameKeyManualTwoScenes,
        swiftUICoexistenceSiblingContainerAuthority,
        swiftUIStackManualSheetReturn,
        swiftUIStackNativePopCancel,
        swiftUIStackNativePopFinish,
        swiftUISplitAutomaticBaseline,
        swiftUISplitSameTypeSelection,
        swiftUISplitSameTypeSelectionTwoScenes,
        swiftUISplitRetainedReturn,
        swiftUISplitEmptySelection,
        uikitSplitReplacement,
        uikitSplitSubclass,
        uikitSplitAutomaticPop,
        uikitSplitPopCancel,
        uikitSplitPopFinish,
        uikitSplitNativePopControl,
        uikitSplitNativePopCancel,
        uikitSplitNativePopFinish,
        uikitSplitConcurrentScenes,
        actionsUIKitScrollNavigationDeceleration,
        actionsSwiftUIButtonStructuredTask,
        tracesURLSessionCrossScene,
        tracesURLSessionSharedRequest,
        tracesURLSessionReverseCompletion,
        windowsParallelNavigation,
        windowsActivationSequence,
        windowsCloseWithResource,
        actionsExactSourceHandoff,
        retainedReaderReconnect,
        retainedReaderReconnectSceneB,
        sceneRestoration,
        diagnosticOffscreenTab,
        diagnosticNavigationPathSameTypeReplacement,
        diagnosticNavigationPathSplitSelection,
        regressionSingleScene
    ]

    private static let legacyCompatibleIdentifiers: Set<String> = [
        interactiveManual.identifier,
        automaticSingleWindow.identifier,
        automaticTwoWindow.identifier,
        swiftUIStackOccurrencePush.identifier,
        swiftUIStackAbort.identifier,
        swiftUIStackSameTypeReplacement.identifier,
        swiftUIStackDifferentTypeReplacement.identifier,
        swiftUISplitAutomaticBaseline.identifier,
        swiftUISplitSameTypeSelection.identifier,
        swiftUISplitSameTypeSelectionTwoScenes.identifier,
        swiftUISplitRetainedReturn.identifier,
        swiftUISplitEmptySelection.identifier,
        uikitSplitReplacement.identifier,
        uikitSplitSubclass.identifier,
        uikitSplitAutomaticPop.identifier,
        uikitSplitPopCancel.identifier,
        uikitSplitPopFinish.identifier,
        uikitSplitNativePopControl.identifier,
        uikitSplitConcurrentScenes.identifier,
        windowsCloseWithResource.identifier,
        actionsExactSourceHandoff.identifier,
        retainedReaderReconnect.identifier,
        retainedReaderReconnectSceneB.identifier,
        diagnosticOffscreenTab.identifier,
        diagnosticNavigationPathSameTypeReplacement.identifier,
        diagnosticNavigationPathSplitSelection.identifier,
        regressionSingleScene.identifier
    ]

    static func scenario(identifier: String) -> ProbeScenario? {
        all.first { $0.identifier == identifier }
    }

    static func usesObservableDriver(_ scenario: ProbeScenario) -> Bool {
        observableDriverIdentifiers.contains(scenario.identifier)
    }

    static func usesSceneTargetedPresentationAuthority(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier == swiftUICoexistenceAutomaticSceneTargetedSheet.identifier
            || scenario.identifier
                == swiftUICoexistenceAutomaticSceneTargetedFullScreenCover.identifier
    }

    static func usesExplicitOperationViewTargetSPI(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier == operationsExplicitTargetCrossSceneSerial.identifier
    }

    static func usesSemanticNavigationSPI(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier == swiftUISemanticAPICompleteDestination.identifier
            || scenario.identifier == swiftUISemanticAPIPresentationReplacement.identifier
            || scenario.identifier == swiftUISemanticAPIRepeatedValueLinks.identifier
            || scenario.identifier == swiftUISemanticAPIInitialRepeatedPath.identifier
            || scenario.identifier == swiftUISemanticAPIExternalReplacements.identifier
            || scenario.identifier == swiftUISemanticAPIRejectedLinkWrite.identifier
            || scenario.identifier == swiftUISemanticAPICanonicalizedLinkWrite.identifier
            || scenario.identifier == swiftUISemanticAPISiblingContainerIsolation.identifier
    }

    static func usesSemanticNavigationHostSPI(_ scenario: ProbeScenario) -> Bool {
        usesExplicitSemanticNavigationHostSPI(scenario)
            || usesCapabilitySemanticNavigationHostSPI(scenario)
            || usesAutomaticSemanticNavigationHostSPI(scenario)
            || usesEXP147RouterStreamAdapter(scenario)
            || usesEXP151ObservationRouterAdapter(scenario)
            || usesEXP153ThirdPartyCallbackAdapter(scenario)
    }

    static func usesExplicitSemanticNavigationHostSPI(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier == swiftUISemanticHostExplicitSource.identifier
            || usesExplicitSemanticNavigationPrecedenceSPI(scenario)
            || usesSemanticNavigationHostLifetimeTestingSPI(scenario)
    }

    static func usesExplicitSemanticNavigationPrecedenceSPI(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier == swiftUISemanticHostExplicitPrecedence.identifier
    }

    static func usesCapabilitySemanticNavigationHostSPI(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier == swiftUISemanticHostOptionalCapability.identifier
            || usesObservedSemanticNavigationCapabilitySPI(scenario)
    }

    static func usesObservedSemanticNavigationCapabilitySPI(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier == swiftUISemanticHostCapabilityReconstruction.identifier
            || scenario.identifier == swiftUISemanticHostCapabilityReplacement.identifier
    }

    static func replacesSemanticNavigationCapabilitySource(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier == swiftUISemanticHostCapabilityReplacement.identifier
    }

    static func usesSemanticNavigationHostFinalDetachSPI(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier == swiftUISemanticHostFinalRemovalIsolation.identifier
    }

    static func usesSemanticNavigationHostLifetimeTestingSPI(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier == swiftUISemanticHostTransientReaderReattach.identifier
            || usesSemanticNavigationHostFinalDetachSPI(scenario)
    }

    static func usesAutomaticSemanticNavigationHostSPI(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier == swiftUISemanticHostAutomaticFallback.identifier
    }

    static func usesEXP147RouterStreamAdapter(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier == swiftUISemanticHostRouterStreamAdapter.identifier
    }

    static func usesEXP151ObservationRouterAdapter(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier == swiftUISemanticHostObservationRouterAdapter.identifier
            || scenario.identifier
                == swiftUISemanticHostObservationRouterTwoScenesSerial.identifier
            || usesEXP152NativeDismissCallbacks(scenario)
    }

    static func usesEXP152NativeDismissCallbacks(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier
            == swiftUISemanticHostObservationNativeDismissCallbacks.identifier
    }

    static func usesEXP153ThirdPartyCallbackAdapter(
        _ scenario: ProbeScenario
    ) -> Bool {
        scenario.identifier
            == swiftUISemanticHostThirdPartyCallbackAdapter.identifier
    }

    static func usesEXP147NavigationFixture(_ scenario: ProbeScenario) -> Bool {
        usesEXP147RouterStreamAdapter(scenario)
            || usesEXP151ObservationRouterAdapter(scenario)
    }

    static func usesExactSemanticNavigationHostSPI(_ scenario: ProbeScenario) -> Bool {
        usesExplicitSemanticNavigationHostSPI(scenario)
            || usesCapabilitySemanticNavigationHostSPI(scenario)
    }

    static func usesSemanticNavigationValueLinks(_ scenario: ProbeScenario) -> Bool {
        scenario.identifier == swiftUISemanticAPIRepeatedValueLinks.identifier
            || scenario.identifier == swiftUISemanticAPIRejectedLinkWrite.identifier
            || scenario.identifier == swiftUISemanticAPICanonicalizedLinkWrite.identifier
    }

    static func scenario(
        matching runtimeOptions: ProbeRuntimeOptions,
        layout: ProbeLayout,
        trackingMode: ProbeTrackingMode
    ) -> ProbeScenario? {
        all.first {
            legacyCompatibleIdentifiers.contains($0.identifier)
                && $0.runtimeOptions == runtimeOptions
                && $0.layout == layout
                && $0.trackingMode == trackingMode
        }
    }

    private static let interactiveManual = ProbeScenario(
        identifier: defaultIdentifier,
        trackingMode: .automatic,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A")
        ],
        completionConditions: [
            ProbeExpectation(.sceneReady, scene: "scene-A")
        ],
        expectedSemanticTimeline: []
    )

    private static let automaticSingleWindow = ProbeScenario(
        identifier: "swiftui.automatic.single-window",
        trackingMode: .automatic,
        layout: .stack,
        steps: stackPushSteps(),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "detail-1")
        ],
        expectedSemanticTimeline: stackPushTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
        }
    )

    private static let automaticTwoWindow = ProbeScenario(
        identifier: "swiftui.automatic.two-window",
        trackingMode: .automatic,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: parallelWindowSteps(),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-B", screen: "detail-1")
        ],
        expectedSemanticTimeline: parallelWindowTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
            $0.automaticallyOpensSecondWindow = true
        }
    )

    private static let swiftUIStackOccurrencePush = ProbeScenario(
        identifier: "swiftui.stack.occurrence-push",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: stackPushSteps(),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "detail-1")
        ],
        expectedSemanticTimeline: stackPushTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
        }
    )

    private static let swiftUIStackReturn = ProbeScenario(
        identifier: "swiftui.stack.return",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:detail-1"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "home"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#2"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "navigation-appearance-2")
        ],
        completionConditions: [
            ProbeExpectation(.action, scene: "scene-A", screen: "home", occurrence: 2, name: "navigation-appearance-2")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStopped, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-1", occurrence: 1),
            ProbeExpectation(.viewStopped, scene: "scene-A", screen: "detail-1", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 2),
            ProbeExpectation(.action, scene: "scene-A", screen: "home", occurrence: 2, name: "navigation-appearance-2")
        ]
    )

    /// Exercises application-wide Operation identities while the current RUM
    /// destination changes repeatedly in one scene. The local oracle proves
    /// each call-site destination and navigation occurrence; the exact vital
    /// start/end ownership remains a backend assertion because Operation
    /// vitals do not pass through a customer event mapper.
    private static let operationsNavigationLifecycle = ProbeScenario(
        identifier: "operations.navigation.lifecycle",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:home#1"
            ),
            ProbeStep(.startOperation, scene: "scene-A", value: "success"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-success-start-home"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:detail-1#1"
            ),
            ProbeStep(.succeedOperation, scene: "scene-A", value: "success"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-success-end-detail"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:home#2"
            ),
            ProbeStep(.startOperation, scene: "scene-A", value: "failure"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-failure-start-home"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:detail-1#2"
            ),
            ProbeStep(.failOperation, scene: "scene-A", value: "failure"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-failure-end-detail"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:home#3"
            ),
            ProbeStep(.startOperation, scene: "scene-A", value: "duplicate"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-duplicate-start-home"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:detail-1#3"
            ),
            ProbeStep(.startOperation, scene: "scene-A", value: "duplicate"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-duplicate-restart-detail"
            ),
            ProbeStep(.succeedOperation, scene: "scene-A", value: "duplicate"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-duplicate-end-detail"
            ),
        ],
        completionConditions: operationWorkExpectations(
            name: "operation-duplicate-end-detail",
            screen: "detail-1",
            occurrence: 3
        ),
        expectedSemanticTimeline:
            operationOccurrenceExpectations(
                screen: "home",
                occurrence: 1,
                marker: "operation-success-start-home",
                ends: true
            )
            + operationOccurrenceExpectations(
                screen: "detail-1",
                occurrence: 1,
                marker: "operation-success-end-detail",
                ends: true
            )
            + operationOccurrenceExpectations(
                screen: "home",
                occurrence: 2,
                marker: "operation-failure-start-home",
                ends: true
            )
            + operationOccurrenceExpectations(
                screen: "detail-1",
                occurrence: 2,
                marker: "operation-failure-end-detail",
                ends: true
            )
            + operationOccurrenceExpectations(
                screen: "home",
                occurrence: 3,
                marker: "operation-duplicate-start-home",
                ends: true
            )
            + [
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: "detail-1",
                    occurrence: 3
                )
            ]
            + operationWorkExpectations(
                name: "operation-duplicate-restart-detail",
                screen: "detail-1",
                occurrence: 3
            )
            + operationWorkExpectations(
                name: "operation-duplicate-end-detail",
                screen: "detail-1",
                occurrence: 3
            )
    )

    /// Exercises one application-wide Operation identity across two scenes and
    /// two independent same-name identities completed in reverse order. This
    /// scenario does not navigate, so explicit per-scene Home boundaries keep
    /// its view setup independent from the legacy occurrence-source probe. The
    /// Operation calls remain inferred: local signals prove exact call sites;
    /// raw and reduced backend Operation events remain the attribution oracle.
    private static let operationsCrossSceneLifecycle = ProbeScenario(
        identifier: "operations.cross-scene.lifecycle",
        trackingMode: .manual,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes, .simultaneousVisibleWindows],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-cross-home-a"
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "operation-cross-home-b"
            ),
            ProbeStep(.startOperation, scene: "scene-A", value: "cross-success"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-cross-success-start-a"
            ),
            ProbeStep(.succeedOperation, scene: "scene-B", value: "cross-success"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "operation-cross-success-end-b"
            ),
            ProbeStep(.startOperation, scene: "scene-A", value: "cross-failure"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-cross-failure-start-a"
            ),
            ProbeStep(.failOperation, scene: "scene-B", value: "cross-failure"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "operation-cross-failure-end-b"
            ),
            ProbeStep(.startOperation, scene: "scene-A", value: "parallel-alpha"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-parallel-alpha-start-a"
            ),
            ProbeStep(.startOperation, scene: "scene-B", value: "parallel-beta"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "operation-parallel-beta-start-b"
            ),
            ProbeStep(.succeedOperation, scene: "scene-B", value: "parallel-beta"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "operation-parallel-beta-end-b"
            ),
            ProbeStep(.succeedOperation, scene: "scene-A", value: "parallel-alpha"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "operation-parallel-alpha-end-a"
            ),
        ],
        completionConditions: operationCrossSceneWorkExpectations(
            name: "operation-parallel-alpha-end-a",
            scene: "scene-A",
            reference: "operation-cross-home-a"
        ),
        expectedSemanticTimeline: operationCrossSceneTimeline()
    )

    /// EXP-155 reuses the cross-scene Operation contract through the
    /// customer-shaped `.current(in:)` SPI. It uses explicit per-scene Home
    /// boundaries because this scenario does not navigate and its purpose is
    /// to discriminate Operation targeting, not the legacy occurrence-source
    /// probe. It intentionally requires only two native scenes, not simultaneous
    /// visibility: every call carries an explicit scene target while the
    /// preceding marker has made the other scene the process representative.
    private static let operationsExplicitTargetCrossSceneSerial = ProbeScenario(
        identifier: "operations.explicit-target.cross-scene-serial",
        trackingMode: .manual,
        layout: .stack,
        initialWindows: operationsCrossSceneLifecycle.initialWindows,
        requiredCapabilities: [.multipleScenes],
        steps: operationsCrossSceneLifecycle.steps,
        completionConditions: operationsCrossSceneLifecycle.completionConditions,
        expectedSemanticTimeline: operationsCrossSceneLifecycle.expectedSemanticTimeline
    )

    /// EXP-158 validates the first non-Operation consumer of the general RUM
    /// view target. Each explicit action is emitted after the opposite scene has
    /// become process representative. A final source-less marker deliberately
    /// executes from A and remains on last-interacted B for compatibility.
    private static let actionsExplicitTargetCrossSceneSerial = ProbeScenario(
        identifier: "actions.explicit-target.cross-scene-serial",
        trackingMode: .manual,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:home#1"
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "explicit-action-representative-b"
            ),
            ProbeStep(
                .emitExplicitTargetAction,
                scene: "scene-A",
                value: "explicit-action-a-overrides-b"
            ),
            ProbeStep(
                .emitExplicitTargetAction,
                scene: "scene-B",
                value: "explicit-action-b-overrides-a"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "explicit-action-legacy-fallback-to-b"
            ),
        ],
        completionConditions: [
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "explicit-action-legacy-fallback-to-b",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "explicit-action-representative-b",
                ownerViewRelation: .same
            )
        ],
        expectedSemanticTimeline: explicitActionTargetTimeline()
    )

    /// All native-scene and view readiness is consumed before either action
    /// starts. Final names and phase attributes require explicit stops, so the
    /// automatic timeout cannot accidentally satisfy this contract.
    private static let actionsExplicitTargetLongRunningCrossSceneSerial = ProbeScenario(
        identifier: "actions.explicit-target.long-running-cross-scene-serial",
        trackingMode: .manual,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "rum-view:home#1"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-B", value: "long-running-representative-b"),
            ProbeStep(.startExplicitTargetAction, scene: "scene-A", value: "long-running-shared"),
            ProbeStep(.startExplicitTargetAction, scene: "scene-B", value: "long-running-shared"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-A", value: "long-running-representative-a"),
            ProbeStep(.stopExplicitTargetAction, scene: "scene-B", value: "long-running-finished-b"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-A", value: "long-running-empty-b-representative-a"),
            ProbeStep(.stopExplicitTargetAction, scene: "scene-B", value: "long-running-empty-b"),
            ProbeStep(.stopExplicitTargetAction, scene: "scene-A", value: "long-running-finished-a"),
            ProbeStep(.emitSceneContextMarker, scene: "scene-B", value: "long-running-legacy-representative-b"),
            ProbeStep(.startLegacyAction, scene: "scene-A", value: "long-running-legacy-start"),
            ProbeStep(.stopLegacyAction, scene: "scene-A", value: "long-running-legacy-finished-b"),
        ],
        completionConditions: [
            continuousActionExpectation(name: "long-running-finished-b", scene: "scene-B"),
            continuousActionExpectation(name: "long-running-finished-a", scene: "scene-A"),
            continuousActionExpectation(name: "long-running-legacy-finished-b", scene: "scene-B", sourceScene: "scene-A"),
            ProbeExpectation(.noEvent, name: "long-running-shared"),
            ProbeExpectation(.noEvent, name: "long-running-empty-b"),
            ProbeExpectation(.noEvent, name: "long-running-legacy-start"),
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1, rumViewOrigin: .semantic),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "home", occurrence: 1, rumViewOrigin: .semantic),
            continuousActionExpectation(name: "long-running-representative-b", scene: "scene-B", finalName: false),
            continuousActionExpectation(name: "long-running-representative-a", scene: "scene-A", finalName: false),
            continuousActionExpectation(name: "long-running-finished-b", scene: "scene-B"),
            continuousActionExpectation(name: "long-running-empty-b-representative-a", scene: "scene-A", finalName: false),
            continuousActionExpectation(name: "long-running-finished-a", scene: "scene-A"),
            continuousActionExpectation(name: "long-running-legacy-representative-b", scene: "scene-B", finalName: false),
            continuousActionExpectation(name: "long-running-legacy-finished-b", scene: "scene-B", sourceScene: "scene-A"),
        ]
    )

    private static func continuousActionExpectation(
        name: String,
        scene: String,
        sourceScene: String? = nil,
        finalName: Bool = true
    ) -> ProbeExpectation {
        ProbeExpectation(
            .action,
            scene: scene,
            screen: "home",
            occurrence: 1,
            name: name,
            sourceScene: sourceScene ?? scene,
            sourceScreen: "home",
            rumViewOrigin: .semantic,
            actionType: "custom",
            actionTarget: finalName ? name : nil,
            expectedCount: 1
        )
    }

    private static let swiftUIStackAbort = ProbeScenario(
        identifier: "swiftui.stack.abort",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.pushAndRevertSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:post-aborted-navigation")
        ],
        completionConditions: [
            ProbeExpectation(.action, scene: "scene-A", screen: "home", occurrence: 1, name: "post-aborted-navigation")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "detail-1", interval: "aborted-navigation"),
            ProbeExpectation(.action, scene: "scene-A", screen: "home", occurrence: 1, name: "post-aborted-navigation"),
            ProbeExpectation(.resource, scene: "scene-A", screen: "home", occurrence: 1, name: "post-aborted-navigation")
        ],
        runtimeOptions: runtime {
            $0.automaticallyAbortsDetail = true
        }
    )

    private static let swiftUIStackSameTypeReplacement = ProbeScenario(
        identifier: "swiftui.stack.same-type-replacement",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: stackReplacementSteps(destination: "detail-2"),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "detail-2")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-1", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-2", occurrence: 1),
            ProbeExpectation(.action, scene: "scene-A", screen: "detail-2", occurrence: 1, name: "binding-update-2"),
            ProbeExpectation(.resource, scene: "scene-A", screen: "detail-2", occurrence: 1, name: "binding-update-2")
        ],
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
            $0.automaticallyReplacesDetailInstance = true
        }
    )

    private static let swiftUIStackDifferentTypeReplacement = ProbeScenario(
        identifier: "swiftui.stack.different-type-replacement",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: stackReplacementSteps(destination: "alternate"),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "alternate")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-1", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "alternate", occurrence: 1),
            ProbeExpectation(.action, scene: "scene-A", screen: "alternate", occurrence: 1, name: "on-appear"),
            ProbeExpectation(.resource, scene: "scene-A", screen: "alternate", occurrence: 1, name: "on-appear")
        ],
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
            $0.automaticallyReplacesDetail = true
        }
    )

    private static let swiftUICoexistenceSemanticAAutomaticB = ProbeScenario(
        identifier: "swiftui.coexistence.semantic-a-automatic-b",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-a-before-peer"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "marker:task-delayed"),
            ProbeStep(.emitMarker, scene: "scene-B", value: "automatic-b-after-ready")
        ],
        completionConditions: [
            ProbeExpectation(
                .action,
                name: "automatic-b-after-ready",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterSceneOpen: "scene-B"
            ),
            ProbeExpectation(
                .resource,
                name: "automatic-b-after-ready",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterSceneOpen: "scene-B"
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "semantic-a-before-peer",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "semantic-a-before-peer",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                name: "automatic-b-after-ready",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterSceneOpen: "scene-B"
            ),
            ProbeExpectation(
                .resource,
                name: "automatic-b-after-ready",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterSceneOpen: "scene-B"
            )
        ],
        runtimeOptions: runtime {
            $0.semanticNavigationSceneIDs = ["scene-A"]
        }
    )

    private static let swiftUIStackManualSheetReturn = ProbeScenario(
        identifier: "swiftui.stack.manual-sheet-return",
        trackingMode: .manual,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:sheet"),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "home"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:home#2")
        ],
        completionConditions: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 2)
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStopped, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "sheet", occurrence: 1),
            ProbeExpectation(.viewStopped, scene: "scene-A", screen: "sheet", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 2)
        ]
    )

    private static let swiftUICoexistenceAutomaticManualSheet = ProbeScenario(
        identifier: "swiftui.coexistence.automatic-manual-sheet",
        trackingMode: .automatic,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "automatic-home-before-sheet"),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "manual-sheet-active"),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "marker:sheet-dismissed-settled"
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                interval: "manual-sheet-active"
            ),
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                rumViewName: "ProbeSheetView",
                interval: "swiftui-presentation-subtree"
            ),
            ProbeExpectation(
                .action,
                name: "sheet-dismissed-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: "automatic-home-before-sheet",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                name: "sheet-dismissed-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: "sheet-dismissed-immediate",
                ownerViewRelation: .same
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .action,
                name: "automatic-home-before-sheet",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .resource,
                name: "automatic-home-before-sheet",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                name: "manual-sheet-active",
                sourceScene: "scene-A",
                sourceScreen: "sheet",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                name: "manual-sheet-active",
                sourceScene: "scene-A",
                sourceScreen: "sheet",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                name: "sheet-dismissed-immediate",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: "automatic-home-before-sheet",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                name: "sheet-dismissed-immediate",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: "automatic-home-before-sheet",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                name: "sheet-dismissed-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: "sheet-dismissed-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                name: "sheet-dismissed-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: "sheet-dismissed-immediate",
                ownerViewRelation: .same
            )
        ],
        runtimeOptions: runtime {
            $0.manualSwiftUIViewScreensByScene = ["scene-A": ["sheet"]]
        }
    )

    /// Positive successor to the lifecycle-modifier baseline above. It keeps the
    /// exact same oracle while moving presentation ownership to the centralized
    /// scene router and the handler-backed exact-scene manual stack. A separate
    /// UI-attached token suppresses automatic discovery only for the presented
    /// platform subtree while its native dismissal completes.
    private static let swiftUICoexistenceAutomaticSceneTargetedSheet = ProbeScenario(
        identifier: "swiftui.coexistence.automatic-scene-targeted-sheet",
        trackingMode: .automatic,
        layout: .stack,
        steps: swiftUICoexistenceAutomaticManualSheet.steps,
        completionConditions: swiftUICoexistenceAutomaticManualSheet.completionConditions,
        expectedSemanticTimeline: swiftUICoexistenceAutomaticManualSheet.expectedSemanticTimeline
    )

    private static let swiftUICoexistenceAutomaticSceneTargetedFullScreenCover =
        ProbeScenario(
            identifier: "swiftui.coexistence.automatic-scene-targeted-full-screen-cover",
            trackingMode: .automatic,
            layout: .stack,
            steps: sceneTargetedPresentationSteps(
                presentation: "full-screen-cover",
                activeMarker: "manual-full-screen-cover-active",
                dismissedSettledMarker: "full-screen-cover-dismissed-settled"
            ),
            completionConditions: sceneTargetedPresentationCompletionConditions(
                rumViewName: "ProbeFullScreenCoverView",
                activeInterval: "manual-full-screen-cover-active",
                subtreeInterval: "swiftui-full-screen-cover-subtree",
                beforeMarker: "automatic-home-before-full-screen-cover",
                dismissedImmediateMarker: "full-screen-cover-dismissed-immediate",
                dismissedSettledMarker: "full-screen-cover-dismissed-settled"
            ),
            expectedSemanticTimeline: sceneTargetedPresentationTimeline(
                presentation: "full-screen-cover",
                activeMarker: "manual-full-screen-cover-active",
                beforeMarker: "automatic-home-before-full-screen-cover",
                dismissedImmediateMarker: "full-screen-cover-dismissed-immediate",
                dismissedSettledMarker: "full-screen-cover-dismissed-settled"
            )
        )

    /// Exercises the actual experimental, once-per-container SwiftUI API while
    /// automatic tracking remains enabled. It covers push, pop, sheet
    /// presentation, sheet dismissal, full-screen presentation, and full-screen
    /// dismissal as one complete destination stream.
    private static let swiftUISemanticAPICompleteDestination = ProbeScenario(
        identifier: "swiftui.semantic-api.complete-destination",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-home-1"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-detail-1"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "home"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#2"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-home-2"),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:sheet#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-sheet-1"),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "marker:sheet-dismissed-settled"
            ),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#3"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-home-3"),
            ProbeStep(
                .setSwiftUIPresentation,
                scene: "scene-A",
                value: "full-screen-cover"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "destination:full-screen-cover"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:full-screen-cover#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-full-screen-cover-1"
            ),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "marker:full-screen-cover-dismissed-settled"
            ),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#4"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-home-4")
        ],
        completionConditions: [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 4,
                name: "semantic-home-4",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 4,
                name: "semantic-home-4",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            )
        ],
        expectedSemanticTimeline: semanticNavigationAPITimeline()
    )

    /// Replays the complete destination oracle through standard NavigationStack,
    /// sheet, and fullScreenCover code wrapped once by RUMNavigationHost. Exact
    /// destination commits arrive through the explicit type-erased source.
    private static let swiftUISemanticHostExplicitSource = ProbeScenario(
        identifier: "swiftui.semantic-host.explicit-source",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: swiftUISemanticAPICompleteDestination.steps,
        completionConditions: swiftUISemanticAPICompleteDestination.completionConditions,
        expectedSemanticTimeline: semanticNavigationAPITimeline(
            initialLifecycleMarkers: ["on-appear", "task-immediate"]
        )
    )

    /// EXP-147 replays the same exact-destination oracle through a realistic
    /// customer router observed once at the container boundary. The ordinary
    /// screens, navigation methods, NavigationStack, sheet, and cover remain
    /// unaware of Datadog. Automatic metadata is sufficient for correctness;
    /// sparse naming overrides are optional and not used by this runtime arm.
    private static let swiftUISemanticHostRouterStreamAdapter = ProbeScenario(
        identifier: "swiftui.semantic-host.router-stream-adapter",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: swiftUISemanticAPICompleteDestination.steps,
        completionConditions: swiftUISemanticAPICompleteDestination.completionConditions,
        expectedSemanticTimeline: semanticNavigationAPITimeline()
    )

    /// EXP-151 replays the router-stream oracle without requiring a Combine
    /// publisher. The host observes the existing `@Observable` router's accepted
    /// destination synchronously at `.didSet`.
    private static let swiftUISemanticHostObservationRouterAdapter = ProbeScenario(
        identifier: "swiftui.semantic-host.observation-router-adapter",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: swiftUISemanticAPICompleteDestination.steps,
        completionConditions: swiftUISemanticAPICompleteDestination.completionConditions,
        expectedSemanticTimeline: semanticNavigationAPITimeline()
    )

    /// EXP-154 mounts the Observation-backed host in two real WindowGroup
    /// scenes and navigates them serially. Serial execution isolates per-scene
    /// host and router ownership without claiming simultaneous visibility,
    /// focus handoff, or background-scene mutation support from the simulator.
    private static let swiftUISemanticHostObservationRouterTwoScenesSerial =
        ProbeScenario(
            identifier:
                "swiftui.semantic-host.observation-router-two-scenes-serial",
            trackingMode: .navigationOccurrence,
            layout: .stack,
            initialWindows: ["scene-A", "scene-B"],
            requiredCapabilities: [.multipleScenes],
            steps: observationRouterTwoScenesSerialSteps(),
            completionConditions: [
                ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic)
            ] + semanticMarkerExpectations(
                scene: "scene-B",
                screen: "home",
                occurrence: 2,
                name: "observation-b-home-2"
            ),
            expectedSemanticTimeline: observationRouterTwoScenesSerialTimeline()
        )

    private static func observationRouterTwoScenesSerialSteps() -> [ProbeStep] {
        [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "observation-a-home-1"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:detail-1#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "observation-a-detail-1"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:home#2"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "observation-a-home-2"
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "observation-b-home-1"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-B", value: "detail-1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:detail-1#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "observation-b-detail-1"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-B", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#2"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "observation-b-home-2"
            )
        ]
    }

    private static func observationRouterTwoScenesSerialTimeline()
        -> [ProbeExpectation] {
        observationRouterSerialTimeline(scene: "scene-A", markerPrefix: "a")
            + observationRouterSerialTimeline(scene: "scene-B", markerPrefix: "b")
    }

    private static func observationRouterSerialTimeline(
        scene: String,
        markerPrefix: String
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: scene,
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            scene: scene,
            screen: "home",
            occurrence: 1,
            name: "observation-\(markerPrefix)-home-1"
        ) + [
            ProbeExpectation(
                .viewStopped,
                scene: scene,
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: scene,
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            scene: scene,
            screen: "detail-1",
            occurrence: 1,
            name: "observation-\(markerPrefix)-detail-1"
        ) + [
            ProbeExpectation(
                .viewStopped,
                scene: scene,
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: scene,
                screen: "home",
                occurrence: 2,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            scene: scene,
            screen: "home",
            occurrence: 2,
            name: "observation-\(markerPrefix)-home-2"
        )
    }

    /// EXP-152 keeps the accepted Observation boundary but moves dismissal
    /// markers into SwiftUI's actual sheet and full-screen-cover `onDismiss`
    /// callbacks. The harness no longer emits those markers after mutating the
    /// router, so a passing result characterizes the native callback boundary.
    private static let swiftUISemanticHostObservationNativeDismissCallbacks =
        ProbeScenario(
            identifier: "swiftui.semantic-host.observation-native-dismiss-callbacks",
            trackingMode: .navigationOccurrence,
            layout: .stack,
            steps: swiftUISemanticAPICompleteDestination.steps.flatMap { step in
                switch step.signal {
                case "destination:sheet":
                    [
                        step,
                        ProbeStep(
                            .waitForSignal,
                            scene: step.scene,
                            signal: "assertion:\(ProbeNativeDismissCallbackContract.sheetContentAppeared)"
                        )
                    ]
                case "marker:sheet-dismissed-settled":
                    [
                        ProbeStep(
                            .waitForSignal,
                            scene: step.scene,
                            signal: "assertion:\(ProbeNativeDismissCallbackContract.sheetOnDismissEntered)"
                        ),
                        ProbeStep(
                            .waitForSignal,
                            scene: step.scene,
                            signal: "marker:sheet-native-on-dismiss-settled"
                        )
                    ]
                case "destination:full-screen-cover":
                    [
                        step,
                        ProbeStep(
                            .waitForSignal,
                            scene: step.scene,
                            signal: "assertion:\(ProbeNativeDismissCallbackContract.coverContentAppeared)"
                        )
                    ]
                case "marker:full-screen-cover-dismissed-settled":
                    [
                        ProbeStep(
                            .waitForSignal,
                            scene: step.scene,
                            signal: "assertion:\(ProbeNativeDismissCallbackContract.coverOnDismissEntered)"
                        ),
                        ProbeStep(
                            .waitForSignal,
                            scene: step.scene,
                            signal:
                                "marker:full-screen-cover-native-on-dismiss-settled"
                        )
                    ]
                default:
                    [step]
                }
            },
            completionConditions:
                swiftUISemanticAPICompleteDestination.completionConditions,
            expectedSemanticTimeline: semanticNavigationAPITimeline(
                sheetDismissedImmediateMarker: "sheet-native-on-dismiss-immediate",
                sheetDismissedSettledMarker: "sheet-native-on-dismiss-settled",
                coverDismissedImmediateMarker:
                    "full-screen-cover-native-on-dismiss-immediate",
                coverDismissedSettledMarker:
                    "full-screen-cover-native-on-dismiss-settled"
            )
        )

    /// EXP-153 wraps a callback-driven custom navigator once, bridges its
    /// synchronous accepted snapshots through a dedicated adapter, and reuses
    /// the SDK-owned publisher host without modifying the visual container or
    /// any navigation method.
    private static let swiftUISemanticHostThirdPartyCallbackAdapter =
        ProbeScenario(
            identifier: "swiftui.semantic-host.third-party-callback-adapter",
            trackingMode: .navigationOccurrence,
            layout: .stack,
            steps: swiftUISemanticAPICompleteDestination.steps + [
                ProbeStep(
                    .waitForSignal,
                    scene: "scene-A",
                    signal:
                        "assertion:"
                        + ProbeThirdPartyCallbackAdapterContract
                            .singleRegistrationAssertion
                )
            ],
            completionConditions:
                swiftUISemanticAPICompleteDestination.completionConditions,
            expectedSemanticTimeline: semanticNavigationAPITimeline(
                initialLifecycleMarkers: ["on-appear", "task-immediate"]
            )
        )

    /// Supplies a conflicting exact capability on the customer container while
    /// also passing the real source explicitly. The decoy source must never own
    /// a view, and the full explicit-source oracle must remain unchanged.
    private static let swiftUISemanticHostExplicitPrecedence = ProbeScenario(
        identifier: "swiftui.semantic-host.explicit-precedence",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: swiftUISemanticAPICompleteDestination.steps,
        completionConditions:
            swiftUISemanticAPICompleteDestination.completionConditions + [
                ProbeExpectation(
                    .noViewStarted,
                    scene: "scene-A",
                    screen: ProbeSemanticHostContract.conflictingCapabilityScreen,
                    rumViewOrigin: .semantic
                )
            ],
        expectedSemanticTimeline: semanticNavigationAPITimeline(
            initialLifecycleMarkers: ["on-appear", "task-immediate"]
        )
    )

    /// Uses the same customer-owned visual container as the automatic fallback
    /// arm, but conditionally conforms its exact-capability specialization. The
    /// host discovers the stable source without an explicit initializer argument.
    private static let swiftUISemanticHostOptionalCapability = ProbeScenario(
        identifier: "swiftui.semantic-host.optional-capability",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: swiftUISemanticAPICompleteDestination.steps,
        completionConditions: swiftUISemanticAPICompleteDestination.completionConditions,
        expectedSemanticTimeline: semanticNavigationAPITimeline(
            initialLifecycleMarkers: ["on-appear", "task-immediate"]
        )
    )

    /// Forces the customer container's capability property to resolve again
    /// after SwiftUI reconstruction while returning the same stable source. The
    /// repeated resolution must neither replay nor disconnect the occurrence.
    private static let swiftUISemanticHostCapabilityReconstruction = ProbeScenario(
        identifier: "swiftui.semantic-host.capability-reconstruction",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: swiftUISemanticAPICompleteDestination.steps + [
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:"
                    + ProbeSemanticHostContract.capabilityReconstructedAssertion
            )
        ],
        completionConditions:
            swiftUISemanticAPICompleteDestination.completionConditions + [
                ProbeExpectation(
                    .noViewStarted,
                    scene: "scene-A",
                    screen: ProbeSemanticHostContract.conflictingCapabilityScreen,
                    rumViewOrigin: .semantic
                )
            ],
        expectedSemanticTimeline: semanticNavigationAPITimeline(
            initialLifecycleMarkers: ["on-appear", "task-immediate"]
        )
    )

    /// Adversarially returns a different exact source after the first capability
    /// resolution. The host must pin the original source, reject the decoy, and
    /// continue the same complete destination stream without replay.
    private static let swiftUISemanticHostCapabilityReplacement = ProbeScenario(
        identifier: "swiftui.semantic-host.capability-replacement",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: swiftUISemanticAPICompleteDestination.steps + [
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:"
                    + ProbeSemanticHostContract.capabilityReplacedAssertion
            )
        ],
        completionConditions:
            swiftUISemanticAPICompleteDestination.completionConditions + [
                ProbeExpectation(
                    .noViewStarted,
                    scene: "scene-A",
                    screen: ProbeSemanticHostContract.conflictingCapabilityScreen,
                    rumViewOrigin: .semantic
                )
            ],
        expectedSemanticTimeline: semanticNavigationAPITimeline(
            initialLifecycleMarkers: ["on-appear", "task-immediate"]
        )
    )

    /// Detaches and reattaches the host's actual scene reader synchronously.
    /// The queued teardown must be cancelled, preserving Detail's occurrence
    /// and the original source subscription before a later Home commit.
    private static let swiftUISemanticHostTransientReaderReattach = ProbeScenario(
        identifier: "swiftui.semantic-host.transient-reader-reattach",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-host-before-transient-reattach"
            ),
            ProbeStep(.bounceSemanticNavigationHostReader, scene: "scene-A"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-host-after-transient-reattach"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "home"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:home"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#2"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-host-after-transient-commit"
            )
        ],
        completionConditions: [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "detail-1",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "detail-1",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                rumViewOrigin: .semantic,
                expectedCount: 2
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "detail-1",
                occurrence: 1,
                name: "semantic-host-after-transient-reattach",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-host-before-transient-reattach",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "detail-1",
                occurrence: 1,
                name: "semantic-host-after-transient-reattach",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-host-before-transient-reattach",
                ownerViewRelation: .same
            )
        ],
        expectedSemanticTimeline: semanticNavigationHostTransientReattachTimeline()
    )

    /// Removes scene A's host while scene B remains mounted. Scene A must stop
    /// its semantic occurrence, release automatic suppression, and unsubscribe
    /// from the exact source without disturbing scene B's current occurrence.
    private static let swiftUISemanticHostFinalRemovalIsolation = ProbeScenario(
        identifier: "swiftui.semantic-host.final-removal-isolation",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.waitForSceneReady, scene: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "rum-view:home#1"),
            ProbeStep(
                .emitMarker,
                scene: "scene-B",
                value: "semantic-host-peer-before-final-removal"
            ),
            ProbeStep(
                .removeSemanticNavigationHost,
                scene: "scene-A",
                value: "home#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-B",
                value: "semantic-host-peer-after-final-removal"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-B", value: "detail-1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "destination:detail-1"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:detail-1#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-B",
                value: "semantic-host-peer-transition-after-final-removal"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-host-after-final-removal"
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-A",
                screen: "detail-1",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-B",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "semantic-host-peer-after-final-removal",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-host-peer-before-final-removal",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "semantic-host-peer-after-final-removal",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-host-peer-before-final-removal",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "detail-1",
                occurrence: 1,
                name: "semantic-host-peer-transition-after-final-removal",
                sourceScene: "scene-B",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-host-peer-after-final-removal",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "detail-1",
                occurrence: 1,
                name: "semantic-host-peer-transition-after-final-removal",
                sourceScene: "scene-B",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-host-peer-after-final-removal",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                name: "semantic-host-after-final-removal",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .removeSemanticNavigationHost,
                ownerViewStartedAfterStepValue: "home#1"
            ),
            ProbeExpectation(
                .resource,
                name: "semantic-host-after-final-removal",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .removeSemanticNavigationHost,
                ownerViewStartedAfterStepValue: "home#1"
            )
        ],
        expectedSemanticTimeline: semanticNavigationHostFinalRemovalTimeline()
    )

    /// Leaves that customer-owned container opaque. The host must keep automatic
    /// discovery enabled, emit no semantic occurrence, and remain useful enough
    /// for ordinary downstream work to have a non-launch automatic owner.
    private static let swiftUISemanticHostAutomaticFallback = ProbeScenario(
        identifier: "swiftui.semantic-host.automatic-fallback",
        trackingMode: .automatic,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed")
        ],
        completionConditions: [
            ProbeExpectation(.viewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(.noViewStarted, rumViewOrigin: .semantic),
            ProbeExpectation(
                .action,
                name: "task-delayed",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .resource,
                name: "task-delayed",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic
            )
        ],
        // Home and Detail intentionally emit the same lifecycle marker names.
        // Keep only the automatic-view existence check ordered so an earlier
        // Home marker cannot fail before the completion oracle finds the exact
        // source-screen-qualified Detail action and Resource above.
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, rumViewOrigin: .automatic)
        ]
    )

    private static func semanticNavigationHostTransientReattachTimeline()
        -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            screen: "detail-1",
            occurrence: 1,
            name: "semantic-host-before-transient-reattach"
        ) + semanticMarkerExpectations(
            screen: "detail-1",
            occurrence: 1,
            name: "semantic-host-after-transient-reattach"
        ) + [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            screen: "home",
            occurrence: 2,
            name: "semantic-host-after-transient-commit"
        )
    }

    private static func semanticNavigationHostFinalRemovalTimeline()
        -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            scene: "scene-B",
            screen: "home",
            occurrence: 1,
            name: "semantic-host-peer-before-final-removal"
        ) + [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            scene: "scene-B",
            screen: "home",
            occurrence: 1,
            name: "semantic-host-peer-after-final-removal"
        ) + [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            scene: "scene-B",
            screen: "detail-1",
            occurrence: 1,
            name: "semantic-host-peer-transition-after-final-removal"
        ) + [
            ProbeExpectation(
                .action,
                name: "semantic-host-after-final-removal",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .removeSemanticNavigationHost,
                ownerViewStartedAfterStepValue: "home#1"
            ),
            ProbeExpectation(
                .resource,
                name: "semantic-host-after-final-removal",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .removeSemanticNavigationHost,
                ownerViewStartedAfterStepValue: "home#1"
            )
        ]
    }

    private static func semanticNavigationAPITimeline(
        initialLifecycleMarkers: [String] = [],
        sheetDismissedImmediateMarker: String = "sheet-dismissed-immediate",
        sheetDismissedSettledMarker: String = "sheet-dismissed-settled",
        coverDismissedImmediateMarker: String =
            "full-screen-cover-dismissed-immediate",
        coverDismissedSettledMarker: String =
            "full-screen-cover-dismissed-settled"
    ) -> [ProbeExpectation] {
        var timeline: [ProbeExpectation] = [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        for marker in initialLifecycleMarkers {
            timeline += semanticMarkerExpectations(
                screen: "home",
                occurrence: 1,
                name: marker
            )
        }
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 1,
            name: "semantic-home-1"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "detail-1",
            occurrence: 1,
            name: "semantic-detail-1"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "detail-1",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 2,
            name: "semantic-home-2"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "sheet",
            occurrence: 1,
            name: "semantic-sheet-1"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 3,
            name: sheetDismissedImmediateMarker
        )
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 3,
            name: sheetDismissedSettledMarker
        )
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 3,
            name: "semantic-home-3"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "full-screen-cover",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "full-screen-cover",
            occurrence: 1,
            name: "semantic-full-screen-cover-1"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "full-screen-cover",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 4,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 4,
            name: coverDismissedImmediateMarker
        )
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 4,
            name: coverDismissedSettledMarker
        )
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 4,
            name: "semantic-home-4"
        )
        return timeline
    }

    /// Replaces mounted semantic presentations in both directions without
    /// first clearing the customer's complete-destination binding. The
    /// underlying stack destination must remain hidden until the final
    /// presentation is dismissed.
    private static let swiftUISemanticAPIPresentationReplacement = ProbeScenario(
        identifier: "swiftui.semantic-api.presentation-replacement",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-presentation-home-1"
            ),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:sheet#1"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-presentation-sheet"
            ),
            ProbeStep(
                .setSwiftUIPresentation,
                scene: "scene-A",
                value: "full-screen-cover"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "destination:full-screen-cover"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:full-screen-cover#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-presentation-full-screen-cover"
            ),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:sheet"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:sheet#2"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-presentation-sheet-return"
            ),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "marker:sheet-dismissed-settled"
            ),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#2"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-presentation-home-2"
            )
        ],
        completionConditions: semanticPresentationReplacementCompletionConditions(),
        expectedSemanticTimeline: semanticPresentationReplacementTimeline()
    )

    private static func semanticPresentationReplacementCompletionConditions()
        -> [ProbeExpectation] {
        var expectations = [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                rumViewOrigin: .semantic,
                expectedCount: 2
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "sheet",
                rumViewOrigin: .semantic,
                expectedCount: 2
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "full-screen-cover",
                rumViewOrigin: .semantic,
                expectedCount: 1
            )
        ]
        for (screen, occurrence, phases) in [
            ("sheet", 1, ["on-appear", "task-immediate"]),
            ("full-screen-cover", 1, ["on-appear", "task-immediate"]),
            ("sheet", 2, ["on-appear", "task-immediate"]),
            ("home", 2, ["sheet-dismissed-immediate", "sheet-dismissed-settled"])
        ] {
            for phase in phases {
                expectations += semanticMarkerExpectations(
                    screen: screen,
                    occurrence: occurrence,
                    name: phase
                )
            }
        }
        return expectations
    }

    private static func semanticPresentationReplacementTimeline() -> [ProbeExpectation] {
        var timeline = [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 1,
            name: "semantic-presentation-home-1"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "sheet",
            occurrence: 1,
            name: "semantic-presentation-sheet"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "full-screen-cover",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "full-screen-cover",
            occurrence: 1,
            name: "semantic-presentation-full-screen-cover"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "full-screen-cover",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 2,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "sheet",
            occurrence: 2,
            name: "semantic-presentation-sheet-return"
        )
        timeline += [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "sheet",
                occurrence: 2,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                rumViewOrigin: .semantic
            )
        ]
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 2,
            name: "sheet-dismissed-immediate"
        )
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 2,
            name: "sheet-dismissed-settled"
        )
        timeline += semanticMarkerExpectations(
            screen: "home",
            occurrence: 2,
            name: "semantic-presentation-home-2"
        )
        return timeline
    }

    /// Drives the experimental container through native value links and native
    /// back buttons. The repeated `detail(1)` values prove that the integration
    /// preserves customer `NavigationLink(value:)` behavior and gives every
    /// committed path position, including a revealed prefix, a fresh RUM view.
    private static let swiftUISemanticAPIRepeatedValueLinks = ProbeScenario(
        identifier: "swiftui.semantic-api.repeated-value-links",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-link-home-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-link-detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#2"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-link-detail-2"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#3"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-link-detail-3"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#2"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-link-home-2")
        ],
        completionConditions: [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                name: "semantic-link-home-2",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                name: "semantic-link-home-2",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            )
        ] + semanticRepeatedValueLinkLifecycleExpectations(),
        expectedSemanticTimeline: semanticRepeatedValueLinksTimeline()
    )

    private static func semanticRepeatedValueLinkLifecycleExpectations()
        -> [ProbeExpectation] {
        var expectations: [ProbeExpectation] = []
        for (screen, occurrence, phases) in [
            ("home", 1, ["navigation-appearance-1", "on-appear", "task-immediate"]),
            (
                "detail-1",
                1,
                ["binding-update-1", "navigation-appearance-1", "on-appear", "task-immediate"]
            ),
            (
                "detail-1",
                2,
                ["binding-update-1", "navigation-appearance-1", "on-appear", "task-immediate"]
            ),
            ("detail-1", 3, ["navigation-appearance-2"]),
            ("home", 2, ["navigation-appearance-2"])
        ] {
            for phase in phases {
                expectations += semanticMarkerExpectations(
                    screen: screen,
                    occurrence: occurrence,
                    name: phase
                )
            }
        }
        return expectations
    }

    private static func semanticRepeatedValueLinksTimeline() -> [ProbeExpectation] {
        let occurrences: [(screen: String, occurrence: Int, marker: String)] = [
            ("home", 1, "semantic-link-home-1"),
            ("detail-1", 1, "semantic-link-detail-1"),
            ("detail-1", 2, "semantic-link-detail-2"),
            ("detail-1", 3, "semantic-link-detail-3"),
            ("home", 2, "semantic-link-home-2")
        ]
        var timeline: [ProbeExpectation] = []
        for (index, occurrence) in occurrences.enumerated() {
            if index > 0 {
                let previous = occurrences[index - 1]
                timeline.append(
                    ProbeExpectation(
                        .viewStopped,
                        scene: "scene-A",
                        screen: previous.screen,
                        occurrence: previous.occurrence,
                        rumViewOrigin: .semantic
                    )
                )
            }
            timeline.append(
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: occurrence.screen,
                    occurrence: occurrence.occurrence,
                    rumViewOrigin: .semantic
                )
            )
            timeline += semanticMarkerExpectations(
                screen: occurrence.screen,
                occurrence: occurrence.occurrence,
                name: occurrence.marker
            )
        }
        return timeline
    }

    /// Starts with the customer's router already restored to two equal route
    /// values. Only the top route may become a RUM view initially; each pop
    /// must reveal a fresh occurrence of the surviving destination.
    private static let swiftUISemanticAPIInitialRepeatedPath = ProbeScenario(
        identifier: "swiftui.semantic-api.initial-repeated-path",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#1"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-restored-detail-top"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#2"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-restored-detail-revealed"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "home"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "semantic-restored-home"
            )
        ],
        completionConditions: [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "semantic-restored-home",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "semantic-restored-home",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            )
        ],
        expectedSemanticTimeline: semanticInitialRepeatedPathTimeline(),
        runtimeOptions: runtime {
            $0.initialSwiftUIPath = ["detail-1", "detail-1"]
        }
    )

    private static func semanticInitialRepeatedPathTimeline() -> [ProbeExpectation] {
        let occurrences: [(screen: String, occurrence: Int, marker: String)] = [
            ("detail-1", 1, "semantic-restored-detail-top"),
            ("detail-1", 2, "semantic-restored-detail-revealed"),
            ("home", 1, "semantic-restored-home")
        ]
        var timeline: [ProbeExpectation] = []
        for (index, occurrence) in occurrences.enumerated() {
            if index > 0 {
                let previous = occurrences[index - 1]
                timeline.append(
                    ProbeExpectation(
                        .viewStopped,
                        scene: "scene-A",
                        screen: previous.screen,
                        occurrence: previous.occurrence,
                        rumViewOrigin: .semantic
                    )
                )
            }
            timeline.append(
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: occurrence.screen,
                    occurrence: occurrence.occurrence,
                    rumViewOrigin: .semantic
                )
            )
            if index == 0 {
                for phase in ["navigation-appearance-1", "on-appear", "task-immediate"] {
                    timeline.append(
                        ProbeExpectation(
                            .action,
                            scene: "scene-A",
                            screen: occurrence.screen,
                            occurrence: occurrence.occurrence,
                            name: phase,
                            sourceScene: "scene-A",
                            sourceScreen: "home",
                            rumViewOrigin: .semantic
                        )
                    )
                    timeline.append(
                        ProbeExpectation(
                            .resource,
                            scene: "scene-A",
                            screen: occurrence.screen,
                            occurrence: occurrence.occurrence,
                            name: phase,
                            sourceScene: "scene-A",
                            sourceScreen: "home",
                            rumViewOrigin: .semantic
                        )
                    )
                }
            }
            timeline += semanticMarkerExpectations(
                screen: occurrence.screen,
                occurrence: occurrence.occurrence,
                name: occurrence.marker
            )
        }
        return timeline
    }

    /// Mutates the customer's bound router directly, without going through a
    /// platform link. Same-type and different-type replacements must each
    /// become a fresh semantic destination occurrence.
    private static let swiftUISemanticAPIExternalReplacements = ProbeScenario(
        identifier: "swiftui.semantic-api.external-replacements",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-router-home"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-1#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-router-detail-1"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-2"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:detail-2#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-router-detail-2"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "alternate"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:alternate#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-router-alternate")
        ],
        completionConditions: [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "detail-2",
                occurrence: 1,
                name: "binding-update-2",
                sourceScene: "scene-A",
                sourceScreen: "detail-2",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "detail-2",
                occurrence: 1,
                name: "binding-update-2",
                sourceScene: "scene-A",
                sourceScreen: "detail-2",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "detail-1",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "detail-2",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "alternate",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "detail-1",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "detail-2",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "detail-2",
                occurrence: 1,
                name: "semantic-router-detail-2",
                sourceScene: "scene-A",
                sourceScreen: "detail-2",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-router-detail-1",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "alternate",
                occurrence: 1,
                name: "semantic-router-alternate",
                sourceScene: "scene-A",
                sourceScreen: "alternate",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-router-detail-2",
                ownerViewRelation: .different
            )
        ] + semanticMarkerExpectations(
            screen: "alternate",
            occurrence: 1,
            name: "on-appear"
        ) + semanticMarkerExpectations(
            screen: "alternate",
            occurrence: 1,
            name: "task-immediate"
        ),
        expectedSemanticTimeline: semanticExternalReplacementsTimeline()
    )

    private static func semanticExternalReplacementsTimeline() -> [ProbeExpectation] {
        let occurrences: [(screen: String, marker: String)] = [
            ("home", "semantic-router-home"),
            ("detail-1", "semantic-router-detail-1"),
            ("detail-2", "semantic-router-detail-2"),
            ("alternate", "semantic-router-alternate")
        ]
        var timeline: [ProbeExpectation] = []
        for (index, occurrence) in occurrences.enumerated() {
            if index > 0 {
                timeline.append(
                    ProbeExpectation(
                        .viewStopped,
                        scene: "scene-A",
                        screen: occurrences[index - 1].screen,
                        occurrence: 1,
                        rumViewOrigin: .semantic
                    )
                )
            }
            timeline.append(
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: occurrence.screen,
                    occurrence: 1,
                    rumViewOrigin: .semantic
                )
            )
            timeline += semanticMarkerExpectations(
                screen: occurrence.screen,
                occurrence: 1,
                name: occurrence.marker
            )
        }
        return timeline
    }

    /// Rejects the path proposed by a native value link. The customer's Home
    /// path stays authoritative and no proposed Detail occurrence may escape.
    private static let swiftUISemanticAPIRejectedLinkWrite = ProbeScenario(
        identifier: "swiftui.semantic-api.rejected-link-write",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-rejected-home-before"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:\(ProbeSemanticRouterContract.rejectedAssertion)"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:\(ProbeSemanticRouterContract.settledAssertion)"
            ),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-rejected-home-after")
        ],
        completionConditions: [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-A",
                screen: "detail-1"
            ),
            ProbeExpectation(
                .noEvent,
                scene: "scene-A",
                screen: "detail-1"
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                rumViewOrigin: .semantic,
                expectedCount: 0
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "semantic-rejected-home-after",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-rejected-home-before",
                ownerViewRelation: .same
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            screen: "home",
            occurrence: 1,
            name: "semantic-rejected-home-before"
        ) + semanticMarkerExpectations(
            screen: "home",
            occurrence: 1,
            name: "semantic-rejected-home-after"
        ),
        runtimeOptions: runtime {
            $0.swiftUIRouterWritePolicy = .reject
        }
    )

    /// Canonicalizes a native value-link proposal for Detail to Alternate. Only
    /// the accepted Alternate path may become visible to RUM or lifecycle work.
    private static let swiftUISemanticAPICanonicalizedLinkWrite = ProbeScenario(
        identifier: "swiftui.semantic-api.canonicalized-link-write",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-canonical-home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:\(ProbeSemanticRouterContract.canonicalizedAssertion)"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:\(ProbeSemanticRouterContract.settledAssertion)"
            ),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:alternate#1"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "semantic-canonical-alternate")
        ],
        completionConditions: [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-A",
                screen: "detail-1"
            ),
            ProbeExpectation(
                .noEvent,
                scene: "scene-A",
                screen: "detail-1"
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "alternate",
                rumViewOrigin: .semantic,
                expectedCount: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "alternate",
                occurrence: 1,
                name: "semantic-canonical-alternate",
                sourceScene: "scene-A",
                sourceScreen: "alternate",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "semantic-canonical-home",
                ownerViewRelation: .different
            )
        ] + semanticMarkerExpectations(
            screen: "alternate",
            occurrence: 1,
            name: "on-appear"
        ) + semanticMarkerExpectations(
            screen: "alternate",
            occurrence: 1,
            name: "task-immediate"
        ) + semanticMarkerExpectations(
            screen: "alternate",
            occurrence: 1,
            name: "task-delayed"
        ),
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            screen: "home",
            occurrence: 1,
            name: "semantic-canonical-home"
        ) + [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "alternate",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + semanticMarkerExpectations(
            screen: "alternate",
            occurrence: 1,
            name: "semantic-canonical-alternate"
        ),
        runtimeOptions: runtime {
            $0.swiftUIRouterWritePolicy = .canonicalizeToAlternate
        }
    )

    private static func semanticMarkerExpectations(
        scene: String = "scene-A",
        screen: String,
        occurrence: Int,
        name: String
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .action,
                scene: scene,
                screen: screen,
                occurrence: occurrence,
                name: name,
                sourceScene: scene,
                sourceScreen: screen,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: scene,
                screen: screen,
                occurrence: occurrence,
                name: name,
                sourceScene: scene,
                sourceScreen: screen,
                rumViewOrigin: .semantic
            )
        ]
    }

    private static func sceneTargetedPresentationSteps(
        presentation: String,
        activeMarker: String,
        dismissedSettledMarker: String
    ) -> [ProbeStep] {
        [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "automatic-home-before-\(presentation)"
            ),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: presentation),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "destination:\(presentation)"
            ),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(.emitMarker, scene: "scene-A", value: activeMarker),
            ProbeStep(.setSwiftUIPresentation, scene: "scene-A", value: "home"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "marker:\(dismissedSettledMarker)"
            )
        ]
    }

    private static func sceneTargetedPresentationCompletionConditions(
        rumViewName: String,
        activeInterval: String,
        subtreeInterval: String,
        beforeMarker: String,
        dismissedImmediateMarker: String,
        dismissedSettledMarker: String
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                interval: activeInterval
            ),
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                rumViewName: rumViewName,
                interval: subtreeInterval
            ),
            ProbeExpectation(
                .action,
                name: dismissedSettledMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: beforeMarker,
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                name: dismissedSettledMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: dismissedImmediateMarker,
                ownerViewRelation: .same
            )
        ]
    }

    private static func sceneTargetedPresentationTimeline(
        presentation: String,
        activeMarker: String,
        beforeMarker: String,
        dismissedImmediateMarker: String,
        dismissedSettledMarker: String
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .action,
                name: beforeMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .resource,
                name: beforeMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: presentation,
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: presentation,
                occurrence: 1,
                name: activeMarker,
                sourceScene: "scene-A",
                sourceScreen: presentation,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: presentation,
                occurrence: 1,
                name: activeMarker,
                sourceScene: "scene-A",
                sourceScreen: presentation,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: presentation,
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                name: dismissedImmediateMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: beforeMarker,
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                name: dismissedImmediateMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: beforeMarker,
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                name: dismissedSettledMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: dismissedImmediateMarker,
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                name: dismissedSettledMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .setSwiftUIPresentation,
                ownerViewStartedAfterStepValue: "home",
                ownerViewReferenceAction: dismissedImmediateMarker,
                ownerViewRelation: .same
            )
        ]
    }

    private static let swiftUICoexistenceAutomaticKeyedManualView = ProbeScenario(
        identifier: "swiftui.coexistence.automatic-keyed-manual-view",
        trackingMode: .automatic,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "automatic-home-before-keyed-manual"
            ),
            ProbeStep(.startKeyedManualView, scene: "scene-A", value: "compose"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "keyed-manual-active"),
            ProbeStep(.stopKeyedManualView, scene: "scene-A", value: "compose")
        ],
        completionConditions: keyedManualReturnExpectations,
        expectedSemanticTimeline: [
            ProbeExpectation(
                .action,
                name: "automatic-home-before-keyed-manual",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .resource,
                name: "automatic-home-before-keyed-manual",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .viewStopped,
                rumViewOrigin: .automatic,
                ownerViewReferenceAction: "automatic-home-before-keyed-manual",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                interval: "keyed-manual-authority-scene-A"
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                name: "keyed-manual-active",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                name: "keyed-manual-active",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ] + keyedManualReturnExpectations
    )

    private static let keyedManualReturnExpectations: [ProbeExpectation] = [
        ProbeExpectation(
            .action,
            name: "keyed-manual-stopped-immediate",
            sourceScene: "scene-A",
            sourceScreen: "home",
            rumViewOrigin: .automatic,
            ownerViewStartedAfterStep: .stopKeyedManualView,
            ownerViewStartedAfterStepValue: "compose",
            ownerViewReferenceAction: "automatic-home-before-keyed-manual",
            ownerViewRelation: .different
        ),
        ProbeExpectation(
            .resource,
            name: "keyed-manual-stopped-immediate",
            sourceScene: "scene-A",
            sourceScreen: "home",
            rumViewOrigin: .automatic,
            ownerViewStartedAfterStep: .stopKeyedManualView,
            ownerViewStartedAfterStepValue: "compose",
            ownerViewReferenceAction: "automatic-home-before-keyed-manual",
            ownerViewRelation: .different
        ),
        ProbeExpectation(
            .action,
            name: "keyed-manual-stopped-settled",
            sourceScene: "scene-A",
            sourceScreen: "home",
            rumViewOrigin: .automatic,
            ownerViewStartedAfterStep: .stopKeyedManualView,
            ownerViewStartedAfterStepValue: "compose",
            ownerViewReferenceAction: "keyed-manual-stopped-immediate",
            ownerViewRelation: .same
        ),
        ProbeExpectation(
            .resource,
            name: "keyed-manual-stopped-settled",
            sourceScene: "scene-A",
            sourceScreen: "home",
            rumViewOrigin: .automatic,
            ownerViewStartedAfterStep: .stopKeyedManualView,
            ownerViewStartedAfterStepValue: "compose",
            ownerViewReferenceAction: "keyed-manual-stopped-immediate",
            ownerViewRelation: .same
        )
    ]

    /// Exercises a real keyed manual destination stack and a duplicate active
    /// `(scene, key)` start. Returning from Preview must create a fresh Compose
    /// occurrence, while the duplicate Compose start must not create another
    /// view or disturb ownership before the final return to automatic Home.
    private static let swiftUICoexistenceNestedKeyedManualView = ProbeScenario(
        identifier: "swiftui.coexistence.nested-keyed-manual-view",
        trackingMode: .automatic,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "automatic-home-before-nested-keyed-manual"
            ),
            ProbeStep(.startKeyedManualView, scene: "scene-A", value: "compose"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:compose#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "nested-keyed-manual-compose-first-active"
            ),
            ProbeStep(.startKeyedManualView, scene: "scene-A", value: "preview"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:preview#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "nested-keyed-manual-preview-active"
            ),
            ProbeStep(.stopKeyedManualView, scene: "scene-A", value: "preview"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:compose#2"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "nested-keyed-manual-compose-resumed"
            ),
            ProbeStep(.startKeyedManualView, scene: "scene-A", value: "compose"),
            ProbeStep(.stopKeyedManualView, scene: "scene-A", value: "compose"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "marker:keyed-manual-stopped-settled"
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                interval: "keyed-manual-authority-scene-A"
            ),
            ProbeExpectation(
                .noViewStarted,
                interval: "duplicate-keyed-manual-start-compose-scene-A"
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "keyed-manual-preview-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "keyed-manual-preview-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "keyed-manual-preview-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "keyed-manual-preview-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .action,
                name: "keyed-manual-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "compose",
                ownerViewReferenceAction: "keyed-manual-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                name: "keyed-manual-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "compose",
                ownerViewReferenceAction: "keyed-manual-stopped-immediate",
                ownerViewRelation: .same
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .action,
                name: "automatic-home-before-nested-keyed-manual",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .resource,
                name: "automatic-home-before-nested-keyed-manual",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .viewStopped,
                rumViewOrigin: .automatic,
                ownerViewReferenceAction: "automatic-home-before-nested-keyed-manual",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                name: "nested-keyed-manual-compose-first-active",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                name: "nested-keyed-manual-compose-first-active",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "preview",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "preview",
                occurrence: 1,
                name: "nested-keyed-manual-preview-active",
                sourceScene: "scene-A",
                sourceScreen: "preview",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "preview",
                occurrence: 1,
                name: "nested-keyed-manual-preview-active",
                sourceScene: "scene-A",
                sourceScreen: "preview",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "preview",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "keyed-manual-preview-stopped-immediate",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "preview",
                ownerViewReferenceAction: "nested-keyed-manual-compose-first-active",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "keyed-manual-preview-stopped-immediate",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "preview",
                ownerViewReferenceAction: "nested-keyed-manual-compose-first-active",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "nested-keyed-manual-compose-resumed",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "keyed-manual-preview-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "nested-keyed-manual-compose-resumed",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "keyed-manual-preview-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "duplicate-keyed-manual-start-compose-scene-A",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "nested-keyed-manual-compose-resumed",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                name: "duplicate-keyed-manual-start-compose-scene-A",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "nested-keyed-manual-compose-resumed",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "compose",
                occurrence: 2,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                name: "keyed-manual-stopped-immediate",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "compose",
                ownerViewReferenceAction: "automatic-home-before-nested-keyed-manual",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                name: "keyed-manual-stopped-immediate",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "compose",
                ownerViewReferenceAction: "automatic-home-before-nested-keyed-manual",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                name: "keyed-manual-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "compose",
                ownerViewReferenceAction: "keyed-manual-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                name: "keyed-manual-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "compose",
                ownerViewReferenceAction: "keyed-manual-stopped-immediate",
                ownerViewRelation: .same
            )
        ]
    )

    /// Starts the same customer key in two live scenes, then stops scene B
    /// before scene A. Exact scene-context work must remain on each distinct
    /// Compose occurrence, and stopping B must neither stop nor reassign A.
    private static let swiftUICoexistenceSameKeyManualTwoScenes = ProbeScenario(
        identifier: "swiftui.coexistence.same-key-manual-two-scenes",
        trackingMode: .automatic,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes, .simultaneousVisibleWindows],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "same-key-home-a-before-manual"
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "marker:task-delayed"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "same-key-home-b-before-manual"
            ),
            ProbeStep(.startKeyedManualView, scene: "scene-A", value: "compose"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:compose#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "same-key-compose-a-active"
            ),
            ProbeStep(.startKeyedManualView, scene: "scene-B", value: "compose"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:compose#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "same-key-compose-b-active"
            ),
            ProbeStep(.stopKeyedManualView, scene: "scene-B", value: "compose"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "same-key-home-b-returned"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "same-key-compose-a-after-b-stop"
            ),
            ProbeStep(.stopKeyedManualView, scene: "scene-A", value: "compose"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "same-key-home-a-returned"
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                interval: "keyed-manual-authority-scene-B"
            ),
            ProbeExpectation(
                .action,
                name: "same-key-home-b-returned",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewReferenceAction: "same-key-home-b-before-manual",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                name: "same-key-compose-a-after-b-stop",
                sourceScene: "scene-A",
                sourceScreen: "compose",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "same-key-compose-a-active",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .action,
                name: "same-key-home-a-returned",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic,
                ownerViewReferenceAction: "same-key-home-a-before-manual",
                ownerViewRelation: .different
            )
        ],
        expectedSemanticTimeline: sameKeyManualTwoSceneTimeline()
    )

    /// Exercises UI-attached automatic-authority containment with two sibling
    /// NavigationStacks under one SwiftUI host. The left stack stays mounted as
    /// a suppression-only manual boundary while the right stack navigates from
    /// Home to Detail underneath an exact-scene manual RUM view. Stopping the
    /// manual view must reveal only the latest right-hand destination.
    private static let swiftUICoexistenceSiblingContainerAuthority = ProbeScenario(
        identifier: "swiftui.coexistence.sibling-container-authority",
        trackingMode: .automatic,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "sibling-home-before-authority"
            ),
            ProbeStep(
                .startKeyedManualView,
                scene: "scene-A",
                value: "sibling-authority"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "rum-view:sibling-authority#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "sibling-authority-active"
            ),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:sibling-controller-topology"
            ),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "marker:task-delayed"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "sibling-underlying-detail-active"
            ),
            ProbeStep(
                .stopKeyedManualView,
                scene: "scene-A",
                value: "sibling-authority"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "marker:sibling-authority-stopped-settled"
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                interval: "manual-sibling-authority"
            ),
            ProbeExpectation(
                .noViewStarted,
                rumViewOrigin: .automatic,
                rumViewName: "AutoTracked_HostingController_Fallback",
                interval: "sibling-container-observation"
            ),
            ProbeExpectation(
                .action,
                name: "sibling-authority-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "sibling-authority",
                ownerViewReferenceAction: "sibling-authority-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                name: "sibling-authority-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "sibling-authority",
                ownerViewReferenceAction: "sibling-authority-stopped-immediate",
                ownerViewRelation: .same
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .action,
                name: "sibling-home-before-authority",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .resource,
                name: "sibling-home-before-authority",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .automatic
            ),
            ProbeExpectation(
                .viewStopped,
                rumViewOrigin: .automatic,
                ownerViewReferenceAction: "sibling-home-before-authority",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                name: "sibling-authority-active",
                sourceScene: "scene-A",
                sourceScreen: "sibling-authority",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                name: "sibling-authority-active",
                sourceScene: "scene-A",
                sourceScreen: "sibling-authority",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                name: "task-delayed",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                name: "task-delayed",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                name: "sibling-underlying-detail-active",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                name: "sibling-underlying-detail-active",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "sibling-authority",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                name: "sibling-authority-stopped-immediate",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "sibling-authority",
                ownerViewReferenceAction: "sibling-home-before-authority",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .resource,
                name: "sibling-authority-stopped-immediate",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "sibling-authority",
                ownerViewReferenceAction: "sibling-home-before-authority",
                ownerViewRelation: .different
            ),
            ProbeExpectation(
                .action,
                name: "sibling-authority-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "sibling-authority",
                ownerViewReferenceAction: "sibling-authority-stopped-immediate",
                ownerViewRelation: .same
            ),
            ProbeExpectation(
                .resource,
                name: "sibling-authority-stopped-settled",
                sourceScene: "scene-A",
                sourceScreen: "detail-1",
                rumViewOrigin: .automatic,
                ownerViewStartedAfterStep: .stopKeyedManualView,
                ownerViewStartedAfterStepValue: "sibling-authority",
                ownerViewReferenceAction: "sibling-authority-stopped-immediate",
                ownerViewRelation: .same
            )
        ],
        runtimeOptions: runtime {
            $0.swiftUIStress = .siblingContainerAuthority
        }
    )

    /// Reuses the `EXP-127` controller topology and manual-authority driver,
    /// but replaces the right-hand probe wrapper with the customer-shaped
    /// semantic navigation SPI. The left manual boundary must remain local,
    /// while the right semantic container stages Detail and reveals it only
    /// after manual authority stops.
    private static let swiftUISemanticAPISiblingContainerIsolation = ProbeScenario(
        identifier: "swiftui.semantic-api.sibling-container-isolation",
        trackingMode: .automatic,
        layout: .stack,
        steps: semanticSiblingContainerSteps(),
        completionConditions: semanticSiblingContainerCompletionConditions(),
        expectedSemanticTimeline: semanticSiblingContainerTimeline(),
        runtimeOptions: swiftUICoexistenceSiblingContainerAuthority.runtimeOptions
    )

    private static func semanticSiblingContainerSteps() -> [ProbeStep] {
        var steps = swiftUICoexistenceSiblingContainerAuthority.steps
        guard let redundantWait = steps.lastIndex(where: {
            $0.kind == .waitForSignal && $0.signal == "marker:task-delayed"
        }) else {
            return steps
        }
        // Detail's delayed work may precede the controller-topology assertion.
        // The ordered oracle already requires its action and Resource, so a
        // later edge-triggered wait would turn valid evidence into a timeout.
        steps.remove(at: redundantWait)
        return steps
    }

    private static func semanticSiblingContainerCompletionConditions()
        -> [ProbeExpectation]
    {
        let ownerConditions = swiftUICoexistenceSiblingContainerAuthority
            .completionConditions
            .filter { $0.kind != .noViewStarted }
            .map(replacingAutomaticOrigin(in:))
        return [
            ProbeExpectation(.noViewStarted, rumViewOrigin: .automatic),
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-A",
                screen: "detail-1",
                rumViewOrigin: .semantic,
                interval: "manual-sibling-authority"
            )
        ] + ownerConditions
    }

    private static func semanticSiblingContainerTimeline() -> [ProbeExpectation] {
        var timeline = swiftUICoexistenceSiblingContainerAuthority
            .expectedSemanticTimeline
            .map(replacingAutomaticOrigin(in:))
            .filter {
                // This delayed callback may fire on either side of manual stop.
                // The explicit underlying-active and post-stop markers provide
                // deterministic ownership checks for both authority states.
                $0.name != "task-delayed"
            }
        timeline.insert(
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            at: 0
        )
        if let revealIndex = timeline.firstIndex(where: {
            $0.kind == .action
                && $0.name == "sibling-authority-stopped-immediate"
        }) {
            timeline.insert(
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: "detail-1",
                    occurrence: 1,
                    rumViewOrigin: .semantic
                ),
                at: revealIndex
            )
        }
        return timeline
    }

    private static func replacingAutomaticOrigin(
        in expectation: ProbeExpectation
    ) -> ProbeExpectation {
        ProbeExpectation(
            expectation.kind,
            scene: expectation.scene,
            screen: expectation.screen,
            occurrence: expectation.occurrence,
            name: expectation.name,
            sourceScene: expectation.sourceScene,
            sourceScreen: expectation.sourceScreen,
            rumViewOrigin: expectation.rumViewOrigin == .automatic
                ? .semantic
                : expectation.rumViewOrigin,
            rumViewName: expectation.rumViewName,
            ownerViewStartedAfterSceneOpen: expectation.ownerViewStartedAfterSceneOpen,
            ownerViewStartedAfterStep: expectation.ownerViewStartedAfterStep,
            ownerViewStartedAfterStepValue: expectation.ownerViewStartedAfterStepValue,
            ownerViewReferenceAction: expectation.ownerViewReferenceAction,
            ownerViewRelation: expectation.ownerViewRelation,
            interval: expectation.interval,
            outcome: expectation.outcome,
            actionType: expectation.actionType,
            expectedCount: expectation.expectedCount
        )
    }

    private static let swiftUIStackNativePopCancel = ProbeScenario(
        identifier: "swiftui.stack.native-pop-cancel",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        requiredCapabilities: [.nativeSwiftUIGesture],
        steps: nativeSwiftUIPopSteps(outcome: .cancel),
        completionConditions: [
            ProbeExpectation(.transitionResolved, scene: "scene-A", outcome: .cancel)
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-1", occurrence: 1),
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "home", occurrence: 2, interval: "cancelled-pop")
        ],
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
        }
    )

    private static let swiftUIStackNativePopFinish = ProbeScenario(
        identifier: "swiftui.stack.native-pop-finish",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        requiredCapabilities: [.nativeSwiftUIGesture],
        steps: nativeSwiftUIPopSteps(outcome: .finish),
        completionConditions: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 2)
        ],
        expectedSemanticTimeline: swiftUIStackReturn.expectedSemanticTimeline,
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
        }
    )

    private static let swiftUISplitAutomaticBaseline = ProbeScenario(
        identifier: "swiftui.split.automatic-baseline",
        trackingMode: .automatic,
        layout: .splitSelection,
        requiredCapabilities: [.regularWidth],
        steps: splitSelectionSteps(returnsToDetail: false),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "placeholder")
        ],
        expectedSemanticTimeline: splitTimeline(returnsToDetail: false)
    )

    private static let swiftUISplitSameTypeSelection = ProbeScenario(
        identifier: "swiftui.split.same-type-selection",
        trackingMode: .navigationOccurrence,
        layout: .splitSelection,
        requiredCapabilities: [.regularWidth],
        steps: splitSelectionSteps(returnsToDetail: false),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "placeholder")
        ],
        expectedSemanticTimeline: splitTimeline(returnsToDetail: false)
    )

    private static let swiftUISplitSameTypeSelectionTwoScenes = ProbeScenario(
        identifier: "swiftui.split.same-type-selection-two-scenes",
        trackingMode: .navigationOccurrence,
        layout: .splitSelection,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes, .regularWidth],
        steps: parallelSplitSelectionSteps(),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "placeholder"),
            ProbeExpectation(.destinationMaterialized, scene: "scene-B", screen: "placeholder")
        ],
        expectedSemanticTimeline: parallelSplitTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyOpensSecondWindow = true
        }
    )

    private static let swiftUISplitRetainedReturn = ProbeScenario(
        identifier: "swiftui.split.retained-return",
        trackingMode: .navigationOccurrence,
        layout: .splitSelection,
        requiredCapabilities: [.regularWidth],
        steps: splitSelectionSteps(returnsToDetail: true),
        completionConditions: [
            ProbeExpectation(.action, scene: "scene-A", screen: "detail-2", occurrence: 2, name: "selection-committed")
        ],
        expectedSemanticTimeline: splitTimeline(returnsToDetail: true),
        runtimeOptions: runtime {
            $0.automaticallyReturnsSplitToDetail = true
        }
    )

    private static let swiftUISplitEmptySelection = ProbeScenario(
        identifier: "swiftui.split.empty-selection",
        trackingMode: .navigationOccurrence,
        layout: .splitSelection,
        requiredCapabilities: [.regularWidth],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "split:empty")
        ],
        completionConditions: [
            ProbeExpectation(.sceneReady, scene: "scene-A")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "detail-1", interval: "empty-selection")
        ],
        runtimeOptions: runtime {
            $0.startsSplitWithoutSelection = true
            $0.automaticallyAdvancesSplitSelection = false
        }
    )

    private static let uikitSplitReplacement = ProbeScenario(
        identifier: "uikit.split.replacement",
        trackingMode: .automatic,
        layout: .uikitSplit,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "uikit-split:secondary-2")
        ],
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "secondary-2")
        ],
        expectedSemanticTimeline: uikitSplitTimeline()
    )

    private static let uikitSplitSubclass = ProbeScenario(
        identifier: "uikit.split.subclass",
        trackingMode: .automatic,
        layout: .uikitSplitSubclass,
        steps: uikitSplitReplacement.steps,
        completionConditions: uikitSplitReplacement.completionConditions,
        expectedSemanticTimeline: uikitSplitReplacement.expectedSemanticTimeline
    )

    private static let uikitSplitAutomaticPop = ProbeScenario(
        identifier: "uikit.split.pop-automatic",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "uikit-navigation:returned-secondary-1")
        ],
        completionConditions: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "secondary-1", occurrence: 2)
        ],
        expectedSemanticTimeline: uikitPopTimeline()
    )

    private static let uikitSplitPopCancel = ProbeScenario(
        identifier: "uikit.split.pop-cancel",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        steps: uikitInteractiveSteps(outcome: .cancel),
        completionConditions: [
            ProbeExpectation(.transitionResolved, scene: "scene-A", outcome: .cancel),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "secondary-2",
                occurrence: 1,
                name: "post-cancel-resolution"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "secondary-2",
                occurrence: 1,
                name: "post-cancel-resolution"
            )
        ],
        expectedSemanticTimeline:
            [
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "primary"),
            ]
            + uikitOccurrenceExpectations(
                screen: "secondary-1",
                occurrence: 1,
                marker: "post-materialization"
            )
            + uikitOccurrenceExpectations(
                screen: "secondary-2",
                occurrence: 1,
                marker: "post-materialization"
            )
            + [
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-A",
                screen: "secondary-1",
                occurrence: 2,
                interval: "cancelled-pop"
            )
        ],
        runtimeOptions: runtime {
            $0.automaticallyPopsUIKitSplitNavigation = false
            $0.uiKitSplitInteractivePopOutcome = .cancel
        }
    )

    private static let uikitSplitPopFinish = ProbeScenario(
        identifier: "uikit.split.pop-finish",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        steps: uikitInteractiveSteps(outcome: .finish),
        completionConditions: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "secondary-1", occurrence: 2),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "secondary-1",
                occurrence: 2,
                name: "post-finish-resolution"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "secondary-1",
                occurrence: 2,
                name: "post-finish-resolution"
            )
        ],
        expectedSemanticTimeline: uikitPopTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyPopsUIKitSplitNavigation = false
            $0.uiKitSplitInteractivePopOutcome = .finish
        }
    )

    private static let uikitSplitNativePopControl = ProbeScenario(
        identifier: "uikit.split.native-pop-control",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        requiredCapabilities: [.nativeUIKitGesture],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "uikit-navigation:secondary-2")
        ],
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "secondary-2")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "primary"),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "secondary-1", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "secondary-2", occurrence: 1)
        ],
        runtimeOptions: runtime {
            $0.automaticallyPopsUIKitSplitNavigation = false
        }
    )

    private static let uikitSplitNativePopCancel = ProbeScenario(
        identifier: "uikit.split.native-pop-cancel",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        requiredCapabilities: [.nativeUIKitGesture],
        steps: nativeUIKitPopSteps(outcome: .cancel),
        completionConditions: [
            ProbeExpectation(.transitionResolved, scene: "scene-A", outcome: .cancel)
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "primary"),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "secondary-2", occurrence: 1),
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-A",
                screen: "secondary-1",
                occurrence: 2,
                interval: "cancelled-pop"
            )
        ],
        runtimeOptions: uikitSplitNativePopControl.runtimeOptions
    )

    private static let uikitSplitNativePopFinish = ProbeScenario(
        identifier: "uikit.split.native-pop-finish",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        requiredCapabilities: [.nativeUIKitGesture],
        steps: nativeUIKitPopSteps(outcome: .finish),
        completionConditions: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "secondary-1", occurrence: 2)
        ],
        expectedSemanticTimeline: uikitPopTimeline(),
        runtimeOptions: uikitSplitNativePopControl.runtimeOptions
    )

    private static let uikitSplitConcurrentScenes = ProbeScenario(
        identifier: "uikit.split.concurrent-scenes",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "uikit-navigation:returned-secondary-1"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "uikit-navigation:returned-secondary-1"
            )
        ],
        completionConditions: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "secondary-1", occurrence: 2),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "secondary-1", occurrence: 2)
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "primary"),
            ProbeExpectation(.noViewStarted, scene: "scene-B", screen: "primary")
        ],
        runtimeOptions: runtime {
            $0.automaticallyOpensSecondWindow = true
        }
    )

    /// Begins a real UIKit scroll action on secondary-2, presents a fresh
    /// destination while the scroll view is decelerating, and waits for the
    /// original delegate's late deceleration callback. The action must be
    /// emitted exactly once on its originating view occurrence.
    private static let actionsUIKitScrollNavigationDeceleration = ProbeScenario(
        identifier: "actions.uikit-scroll-navigation-deceleration",
        trackingMode: .automatic,
        layout: .uikitSplitNavigation,
        requiredCapabilities: [.nativeUIKitGesture],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "uikit-navigation:secondary-2"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:uikit-scroll-ready"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:uikit-scroll-drag-began"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:uikit-scroll-drag-ended-decelerating"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:uikit-scroll-lift-classifies-as-swipe"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:uikit-scroll-navigation-during-deceleration"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "uikit-navigation:secondary-3"
            ),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:uikit-scroll-deceleration-ended"
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "secondary-2",
                occurrence: 1,
                name: "uikit-scroll-origin",
                sourceScene: "scene-A",
                sourceScreen: "secondary-2",
                actionType: "scroll",
                expectedCount: 1
            ),
            ProbeExpectation(
                .noEvent,
                scene: "scene-A",
                screen: "secondary-3",
                name: "uikit-scroll-origin",
                interval: "uikit-scroll-after-navigation"
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "secondary-2",
                occurrence: 1
            ),
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "secondary-2",
                occurrence: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "secondary-3",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "secondary-3",
                occurrence: 1,
                name: "post-scroll-navigation"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "secondary-3",
                occurrence: 1,
                name: "post-scroll-navigation"
            )
        ],
        runtimeOptions: runtime {
            $0.automaticallyPopsUIKitSplitNavigation = false
            $0.exercisesUIKitScrollOwnership = true
        }
    )

    /// Starts an automatically instrumented Trace-only URLSession request on
    /// scene A, opens scene B so it becomes the process representative, then
    /// releases the response from B. The completion-time span must retain A's
    /// request-time Home view.
    private static let actionsSwiftUIButtonStructuredTask = ProbeScenario(
        identifier: "actions.swiftui-button-structured-task",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "assertion:"
                    + ProbeSwiftUIButtonStructuredTaskContract.startedAssertion
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: ProbeSwiftUIButtonStructuredTaskContract.representativeMarker
            ),
            ProbeStep(.releaseSwiftUIButtonStructuredTask, scene: "scene-B")
        ],
        completionConditions: [
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeSwiftUIButtonStructuredTaskContract.automaticActionName,
                actionType: "tap",
                expectedCount: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeSwiftUIButtonStructuredTaskContract.resumedMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                expectedCount: 1
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeSwiftUIButtonStructuredTaskContract.resumedMarker,
                sourceScene: "scene-A",
                sourceScreen: "home",
                expectedCount: 1
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: ProbeSwiftUIButtonStructuredTaskContract.representativeMarker
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: ProbeSwiftUIButtonStructuredTaskContract.representativeMarker
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeSwiftUIButtonStructuredTaskContract.resumedMarker,
                sourceScene: "scene-A",
                sourceScreen: "home"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeSwiftUIButtonStructuredTaskContract.resumedMarker,
                sourceScene: "scene-A",
                sourceScreen: "home"
            )
        ],
        runtimeOptions: runtime {
            $0.exercisesSwiftUIButtonStructuredTask = true
        }
    )

    private static let tracesURLSessionCrossScene = ProbeScenario(
        identifier: "traces.urlsession-cross-scene",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(
                .emitMarker,
                scene: "scene-A",
                value: "trace-request-representative"
            ),
            ProbeStep(
                .startTraceOnlyURLSessionRequest,
                scene: "scene-A",
                value: ProbeTraceOnlyURLSessionContract.requestName
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitMarker,
                scene: "scene-B",
                value: "trace-completion-representative"
            ),
            ProbeStep(
                .completeTraceOnlyURLSessionRequest,
                scene: "scene-B",
                value: ProbeTraceOnlyURLSessionContract.requestName
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .trace,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.requestName,
                sourceScene: "scene-A",
                sourceScreen: "home",
                expectedCount: 1
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-request-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-request-representative"
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-completion-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-completion-representative"
            ),
            ProbeExpectation(
                .trace,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.requestName,
                sourceScene: "scene-A",
                sourceScreen: "home"
            )
        ],
        runtimeOptions: runtime {
            $0.exercisesTraceOnlyURLSessionOwnership = true
        }
    )

    /// Starts one Trace-only URLSession request in A, then lets B join that
    /// already-active request without creating or resuming another task. B is
    /// representative when it releases the response, but the single span must
    /// retain the trustworthy creator's A/Home view.
    private static let tracesURLSessionSharedRequest = ProbeScenario(
        identifier: "traces.urlsession-shared-request",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "trace-shared-creator-representative"
            ),
            ProbeStep(
                .startTraceOnlyURLSessionRequest,
                scene: "scene-A",
                value: ProbeTraceOnlyURLSessionContract.sharedRequestName
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "trace-shared-consumer-representative"
            ),
            ProbeStep(
                .joinTraceOnlyURLSessionRequest,
                scene: "scene-B",
                value: ProbeTraceOnlyURLSessionContract.sharedRequestName
            ),
            ProbeStep(
                .completeTraceOnlyURLSessionRequest,
                scene: "scene-B",
                value: ProbeTraceOnlyURLSessionContract.sharedRequestName
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .trace,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.sharedRequestName,
                sourceScene: "scene-A",
                sourceScreen: "home",
                expectedCount: 1
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-shared-creator-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-shared-creator-representative"
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-shared-consumer-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-shared-consumer-representative"
            ),
            ProbeExpectation(
                .trace,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.sharedRequestName,
                sourceScene: "scene-A",
                sourceScreen: "home"
            )
        ],
        runtimeOptions: runtime {
            $0.exercisesTraceOnlyURLSessionOwnership = true
        }
    )

    /// Starts independent Trace-only URLSession requests in A and B, then
    /// completes them B-before-A while the opposite scene is representative.
    /// Each completion-created span must retain its own request-time Home view.
    private static let tracesURLSessionReverseCompletion = ProbeScenario(
        identifier: "traces.urlsession-reverse-completion",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "rum-view:home#1"),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "trace-reverse-a-start-representative"
            ),
            ProbeStep(
                .startTraceOnlyURLSessionRequest,
                scene: "scene-A",
                value: ProbeTraceOnlyURLSessionContract.reverseSceneARequestName
            ),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "rum-view:home#1"
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "trace-reverse-b-start-representative"
            ),
            ProbeStep(
                .startTraceOnlyURLSessionRequest,
                scene: "scene-B",
                value: ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-A",
                value: "trace-reverse-b-completion-representative"
            ),
            ProbeStep(
                .completeTraceOnlyURLSessionRequest,
                scene: "scene-A",
                value: ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName
            ),
            ProbeStep(
                .emitSceneContextMarker,
                scene: "scene-B",
                value: "trace-reverse-a-completion-representative"
            ),
            ProbeStep(
                .completeTraceOnlyURLSessionRequest,
                scene: "scene-B",
                value: ProbeTraceOnlyURLSessionContract.reverseSceneARequestName
            )
        ],
        completionConditions: [
            ProbeExpectation(
                .trace,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName,
                sourceScene: "scene-B",
                sourceScreen: "home",
                expectedCount: 1
            ),
            ProbeExpectation(
                .trace,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.reverseSceneARequestName,
                sourceScene: "scene-A",
                sourceScreen: "home",
                expectedCount: 1
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-a-start-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-a-start-representative"
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "home",
                occurrence: 1
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-b-start-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-b-start-representative"
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-b-completion-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-b-completion-representative"
            ),
            ProbeExpectation(
                .trace,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName,
                sourceScene: "scene-B",
                sourceScreen: "home"
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-a-completion-representative"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "trace-reverse-a-completion-representative"
            ),
            ProbeExpectation(
                .trace,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: ProbeTraceOnlyURLSessionContract.reverseSceneARequestName,
                sourceScene: "scene-A",
                sourceScreen: "home"
            )
        ],
        runtimeOptions: runtime {
            $0.exercisesTraceOnlyURLSessionOwnership = true
        }
    )

    private static let windowsParallelNavigation = ProbeScenario(
        identifier: "windows.parallel-navigation",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes, .simultaneousVisibleWindows],
        steps: parallelWindowSteps(),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "detail-1"),
            ProbeExpectation(.destinationMaterialized, scene: "scene-B", screen: "detail-1")
        ],
        expectedSemanticTimeline: parallelWindowTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
            $0.automaticallyOpensSecondWindow = true
        }
    )

    private static let windowsCloseWithResource = ProbeScenario(
        identifier: "windows.close-with-resource",
        trackingMode: .manual,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.emitMarker, scene: "scene-B", value: "before-close"),
            ProbeStep(.closeWindow, scene: "scene-B"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "after-peer-close")
        ],
        completionConditions: [
            ProbeExpectation(.sceneDisconnected, scene: "scene-B"),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "after-peer-close"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "after-peer-close"
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "home", occurrence: 1),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "before-close"
            ),
            ProbeExpectation(.sceneDisconnected, scene: "scene-B"),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "after-peer-close"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "after-peer-close"
            )
        ]
    )

    private static let windowsActivationSequence = ProbeScenario(
        identifier: "windows.activation-sequence",
        trackingMode: .manual,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.activateWindow, scene: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "scene-state:background"
            ),
            ProbeStep(.emitMarker, scene: "scene-B", value: "after-initial-activate-B"),
            ProbeStep(.activateWindow, scene: "scene-A"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "scene-state:background"
            ),
            ProbeStep(.emitMarker, scene: "scene-A", value: "after-activate-A"),
            ProbeStep(.activateWindow, scene: "scene-B"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-A",
                signal: "scene-state:background"
            ),
            ProbeStep(.emitMarker, scene: "scene-B", value: "after-reactivate-B"),
            ProbeStep(.activateWindow, scene: "scene-A"),
            ProbeStep(
                .waitForSignal,
                scene: "scene-B",
                signal: "scene-state:background"
            ),
            ProbeStep(.emitMarker, scene: "scene-A", value: "after-reactivate-A"),
            ProbeStep(.closeWindow, scene: "scene-B"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "after-activated-peer-close")
        ],
        completionConditions: [
            ProbeExpectation(.sceneDisconnected, scene: "scene-B"),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                name: "after-activated-peer-close"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                name: "after-activated-peer-close"
            )
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "home", occurrence: 1),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "after-initial-activate-B"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "after-initial-activate-B"
            ),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 2),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                name: "after-activate-A"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 2,
                name: "after-activate-A"
            ),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "home", occurrence: 2),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 2,
                name: "after-reactivate-B"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-B",
                screen: "home",
                occurrence: 2,
                name: "after-reactivate-B"
            ),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 3),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                name: "after-reactivate-A"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                name: "after-reactivate-A"
            ),
            ProbeExpectation(.sceneDisconnected, scene: "scene-B"),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                name: "after-activated-peer-close"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: "home",
                occurrence: 3,
                name: "after-activated-peer-close"
            )
        ]
    )

    private static let actionsExactSourceHandoff = ProbeScenario(
        identifier: "actions.exact-source-handoff",
        trackingMode: .automatic,
        layout: .uikitSplit,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes, .simultaneousVisibleWindows],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.activateWindow, scene: "scene-B"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "scoped-manual")
        ],
        completionConditions: [
            ProbeExpectation(.resource, scene: "scene-A", name: "scoped-manual")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.action, scene: "scene-A", name: "scoped-manual"),
            ProbeExpectation(.resource, scene: "scene-A", name: "scoped-manual")
        ],
        runtimeOptions: runtime {
            $0.automaticallyOpensSecondWindow = true
            $0.exercisesUIEventContextHandoff = true
        }
    )

    private static let retainedReaderReconnect = ProbeScenario(
        identifier: "swiftui.reader.synthetic-reconnect",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.disconnectRetainedReader, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "reader:remounted")
        ],
        completionConditions: [
            ProbeExpectation(.action, scene: "scene-A", screen: "detail-1", name: "post-retained-reader-remount")
        ],
        expectedSemanticTimeline: stackPushTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
            $0.syntheticReaderDisconnectTarget = "scene-A"
        }
    )

    private static let retainedReaderReconnectSceneB = ProbeScenario(
        identifier: "swiftui.reader.synthetic-reconnect-scene-b",
        trackingMode: .navigationOccurrence,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        requiredCapabilities: [.multipleScenes],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.setSwiftUIPath, scene: "scene-B", value: "detail-1"),
            ProbeStep(.disconnectRetainedReader, scene: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "reader:remounted")
        ],
        completionConditions: [
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "detail-1",
                name: "post-retained-reader-remount"
            )
        ],
        expectedSemanticTimeline: parallelWindowTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
            $0.automaticallyOpensSecondWindow = true
            $0.syntheticReaderDisconnectTarget = "scene-B"
        }
    )

    private static let sceneRestoration = ProbeScenario(
        identifier: "windows.restoration",
        trackingMode: .manual,
        layout: .stack,
        initialWindows: ["scene-A", "scene-B"],
        defaultRunMode: .restoration,
        requiredCapabilities: [.multipleScenes, .restoration],
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSceneReady, scene: "scene-B"),
            ProbeStep(.emitMarker, scene: "scene-A", value: "post-restoration"),
            ProbeStep(.emitMarker, scene: "scene-B", value: "post-restoration")
        ],
        completionConditions: [
            ProbeExpectation(.action, scene: "scene-A", name: "post-restoration"),
            ProbeExpectation(.action, scene: "scene-B", name: "post-restoration")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "home", occurrence: 1)
        ]
    )

    private static let diagnosticOffscreenTab = ProbeScenario(
        identifier: "diagnostic.swiftui.offscreen-tab",
        trackingMode: .manual,
        layout: .stack,
        steps: [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "offscreen-tab:unselected")
        ],
        completionConditions: [
            ProbeExpectation(.sceneReady, scene: "scene-A")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(
                .noViewStarted,
                scene: "scene-A",
                screen: "offscreen-tab",
                interval: "unselected-tab"
            )
        ],
        runtimeOptions: runtime {
            $0.swiftUIStress = .tabPreload
        }
    )

    private static let diagnosticNavigationPathSameTypeReplacement = ProbeScenario(
        identifier: "diagnostic.swiftui.navigation-path.same-type-replacement",
        trackingMode: .navigationPath,
        layout: .stack,
        steps: stackReplacementSteps(destination: "detail-2"),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "detail-2")
        ],
        expectedSemanticTimeline: [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-1", occurrence: 1)
        ],
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
            $0.automaticallyReplacesDetailInstance = true
        }
    )

    private static let diagnosticNavigationPathSplitSelection = ProbeScenario(
        identifier: "diagnostic.swiftui.navigation-path.split-selection",
        trackingMode: .navigationPath,
        layout: .splitSelection,
        requiredCapabilities: [.regularWidth],
        steps: splitSelectionSteps(returnsToDetail: false),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "placeholder")
        ],
        expectedSemanticTimeline: splitTimeline(returnsToDetail: false)
    )

    private static let regressionSingleScene = ProbeScenario(
        identifier: "regression.single-scene",
        trackingMode: .manual,
        layout: .stack,
        steps: stackPushSteps(),
        completionConditions: [
            ProbeExpectation(.destinationMaterialized, scene: "scene-A", screen: "detail-1")
        ],
        expectedSemanticTimeline: stackPushTimeline(),
        runtimeOptions: runtime {
            $0.automaticallyNavigates = true
        }
    )

    private static func sameKeyManualTwoSceneTimeline() -> [ProbeExpectation] {
        sameKeyWorkExpectations(
            name: "same-key-home-a-before-manual",
            sourceScene: "scene-A",
            sourceScreen: "home",
            rumViewOrigin: .automatic
        )
        + sameKeyWorkExpectations(
            name: "same-key-home-b-before-manual",
            sourceScene: "scene-B",
            sourceScreen: "home",
            rumViewOrigin: .automatic,
            ownerViewStartedAfterSceneOpen: "scene-B",
            actionReference: "same-key-home-a-before-manual",
            actionRelation: .different
        )
        + [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        + sameKeyWorkExpectations(
            name: "same-key-compose-a-active",
            sourceScene: "scene-A",
            sourceScreen: "compose",
            scene: "scene-A",
            screen: "compose",
            occurrence: 1,
            rumViewOrigin: .semantic,
            actionReference: "same-key-home-a-before-manual",
            actionRelation: .different
        )
        + [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        + sameKeyWorkExpectations(
            name: "same-key-compose-b-active",
            sourceScene: "scene-B",
            sourceScreen: "compose",
            scene: "scene-B",
            screen: "compose",
            occurrence: 1,
            rumViewOrigin: .semantic,
            actionReference: "same-key-compose-a-active",
            actionRelation: .different
        )
        + [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-B",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        + sameKeyWorkExpectations(
            name: "same-key-home-b-returned",
            sourceScene: "scene-B",
            sourceScreen: "home",
            rumViewOrigin: .automatic,
            ownerViewStartedAfterStep: .stopKeyedManualView,
            ownerViewStartedAfterStepValue: "compose",
            actionReference: "same-key-compose-b-active",
            actionRelation: .different
        )
        + sameKeyWorkExpectations(
            name: "same-key-compose-a-after-b-stop",
            sourceScene: "scene-A",
            sourceScreen: "compose",
            scene: "scene-A",
            screen: "compose",
            occurrence: 1,
            rumViewOrigin: .semantic,
            actionReference: "same-key-compose-a-active",
            actionRelation: .same
        )
        + [
            ProbeExpectation(
                .viewStopped,
                scene: "scene-A",
                screen: "compose",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        + sameKeyWorkExpectations(
            name: "same-key-home-a-returned",
            sourceScene: "scene-A",
            sourceScreen: "home",
            rumViewOrigin: .automatic,
            ownerViewStartedAfterStep: .stopKeyedManualView,
            ownerViewStartedAfterStepValue: "compose",
            actionReference: "same-key-compose-a-after-b-stop",
            actionRelation: .different
        )
    }

    private static func sameKeyWorkExpectations(
        name: String,
        sourceScene: String,
        sourceScreen: String,
        scene: String? = nil,
        screen: String? = nil,
        occurrence: Int? = nil,
        rumViewOrigin: ProbeRUMViewOrigin,
        ownerViewStartedAfterSceneOpen: String? = nil,
        ownerViewStartedAfterStep: ProbeStepKind? = nil,
        ownerViewStartedAfterStepValue: String? = nil,
        actionReference: String? = nil,
        actionRelation: ProbeRUMViewOwnerRelation? = nil
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .action,
                scene: scene,
                screen: screen,
                occurrence: occurrence,
                name: name,
                sourceScene: sourceScene,
                sourceScreen: sourceScreen,
                rumViewOrigin: rumViewOrigin,
                ownerViewStartedAfterSceneOpen: ownerViewStartedAfterSceneOpen,
                ownerViewStartedAfterStep: ownerViewStartedAfterStep,
                ownerViewStartedAfterStepValue: ownerViewStartedAfterStepValue,
                ownerViewReferenceAction: actionReference,
                ownerViewRelation: actionRelation
            ),
            ProbeExpectation(
                .resource,
                scene: scene,
                screen: screen,
                occurrence: occurrence,
                name: name,
                sourceScene: sourceScene,
                sourceScreen: sourceScreen,
                rumViewOrigin: rumViewOrigin,
                ownerViewReferenceAction: name,
                ownerViewRelation: .same
            )
        ]
    }

    private static func runtime(
        _ configure: (inout ProbeRuntimeOptions) -> Void
    ) -> ProbeRuntimeOptions {
        var options = ProbeRuntimeOptions()
        configure(&options)
        return options
    }

    private static func operationOccurrenceExpectations(
        screen: String,
        occurrence: Int,
        marker: String,
        ends: Bool
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence
            )
        ]
        + operationWorkExpectations(
            name: marker,
            screen: screen,
            occurrence: occurrence
        )
        + (ends
            ? [
                ProbeExpectation(
                    .viewStopped,
                    scene: "scene-A",
                    screen: screen,
                    occurrence: occurrence
                )
            ]
            : [])
    }

    private static func operationWorkExpectations(
        name: String,
        screen: String,
        occurrence: Int
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence,
                name: name,
                sourceScene: "scene-A",
                sourceScreen: screen,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence,
                name: name,
                sourceScene: "scene-A",
                sourceScreen: screen,
                rumViewOrigin: .semantic
            )
        ]
    }

    private static func operationCrossSceneTimeline() -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        + operationCrossSceneWorkExpectations(
            name: "operation-cross-home-a",
            scene: "scene-A"
        )
        + [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            )
        ]
        + operationCrossSceneWorkExpectations(
            name: "operation-cross-home-b",
            scene: "scene-B",
            reference: "operation-cross-home-a",
            relation: .different
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-cross-success-start-a",
            scene: "scene-A",
            reference: "operation-cross-home-a"
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-cross-success-end-b",
            scene: "scene-B",
            reference: "operation-cross-home-b"
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-cross-failure-start-a",
            scene: "scene-A",
            reference: "operation-cross-home-a"
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-cross-failure-end-b",
            scene: "scene-B",
            reference: "operation-cross-home-b"
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-parallel-alpha-start-a",
            scene: "scene-A",
            reference: "operation-cross-home-a"
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-parallel-beta-start-b",
            scene: "scene-B",
            reference: "operation-cross-home-b"
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-parallel-beta-end-b",
            scene: "scene-B",
            reference: "operation-cross-home-b"
        )
        + operationCrossSceneWorkExpectations(
            name: "operation-parallel-alpha-end-a",
            scene: "scene-A",
            reference: "operation-cross-home-a"
        )
    }

    private static func explicitActionTargetTimeline() -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .viewStarted,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                rumViewOrigin: .semantic
            ),
        ]
        + sameKeyWorkExpectations(
            name: "explicit-action-representative-b",
            sourceScene: "scene-B",
            sourceScreen: "home",
            scene: "scene-B",
            screen: "home",
            occurrence: 1,
            rumViewOrigin: .semantic,
            ownerViewStartedAfterSceneOpen: "scene-B"
        )
        + [
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: "home",
                occurrence: 1,
                name: "explicit-action-a-overrides-b",
                sourceScene: "scene-A",
                sourceScreen: "home",
                rumViewOrigin: .semantic
            ),
            ProbeExpectation(
                .action,
                scene: "scene-B",
                screen: "home",
                occurrence: 1,
                name: "explicit-action-b-overrides-a",
                sourceScene: "scene-B",
                sourceScreen: "home",
                rumViewOrigin: .semantic,
                ownerViewReferenceAction: "explicit-action-representative-b",
                ownerViewRelation: .same
            ),
        ]
        + sameKeyWorkExpectations(
            name: "explicit-action-legacy-fallback-to-b",
            sourceScene: "scene-A",
            sourceScreen: "home",
            scene: "scene-B",
            screen: "home",
            occurrence: 1,
            rumViewOrigin: .semantic,
            ownerViewStartedAfterSceneOpen: "scene-B",
            actionReference: "explicit-action-representative-b",
            actionRelation: .same
        )
    }

    private static func operationCrossSceneWorkExpectations(
        name: String,
        scene: String,
        reference: String? = nil,
        relation: ProbeRUMViewOwnerRelation = .same
    ) -> [ProbeExpectation] {
        sameKeyWorkExpectations(
            name: name,
            sourceScene: scene,
            sourceScreen: "home",
            scene: scene,
            screen: "home",
            occurrence: 1,
            rumViewOrigin: .semantic,
            ownerViewStartedAfterSceneOpen: scene == "scene-B" ? "scene-B" : nil,
            actionReference: reference,
            actionRelation: reference == nil ? nil : relation
        )
    }

    private static func stackPushSteps() -> [ProbeStep] {
        [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:detail-1")
        ]
    }

    private static func stackPushTimeline() -> [ProbeExpectation] {
        [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-1", occurrence: 1)
        ]
    }

    private static func stackReplacementSteps(destination: String) -> [ProbeStep] {
        stackPushSteps() + [
            ProbeStep(.replaceSwiftUIDestination, scene: "scene-A", value: destination),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "destination:\(destination)")
        ]
    }

    private static func nativeSwiftUIPopSteps(outcome: ProbeTransitionOutcome) -> [ProbeStep] {
        stackPushSteps() + [
            ProbeStep(.armNativeSwiftUIGesture, scene: "scene-A", outcome: outcome),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "transition:\(outcome.rawValue)")
        ]
    }

    private static func nativeUIKitPopSteps(outcome: ProbeTransitionOutcome) -> [ProbeStep] {
        [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "uikit-navigation:secondary-2"),
            ProbeStep(.armNativeUIKitGesture, scene: "scene-A", outcome: outcome),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "transition:\(outcome.rawValue)")
        ]
    }

    private static func splitSelectionSteps(returnsToDetail: Bool) -> [ProbeStep] {
        var steps = [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "split:detail-1"),
            ProbeStep(.setSplitSelection, scene: "scene-A", value: "detail-2"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "split:detail-2"),
            ProbeStep(.setSplitSelection, scene: "scene-A", value: "placeholder"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "split:placeholder")
        ]
        if returnsToDetail {
            steps.append(ProbeStep(.setSplitSelection, scene: "scene-A", value: "detail-2"))
            steps.append(
                ProbeStep(.waitForSignal, scene: "scene-A", signal: "split:detail-2#2")
            )
        }
        return steps
    }

    private static func splitTimeline(returnsToDetail: Bool) -> [ProbeExpectation] {
        var timeline = splitOccurrenceExpectations(screen: "detail-1", occurrence: 1)
            + splitOccurrenceExpectations(screen: "detail-2", occurrence: 1)
            + splitOccurrenceExpectations(screen: "placeholder", occurrence: 1)
        if returnsToDetail {
            timeline += splitOccurrenceExpectations(screen: "detail-2", occurrence: 2)
        }
        return timeline
    }

    private static func splitOccurrenceExpectations(
        screen: String,
        occurrence: Int
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence,
                name: "selection-committed"
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence,
                name: "selection-committed"
            )
        ]
    }

    private static func parallelSplitSelectionSteps() -> [ProbeStep] {
        [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "split:placeholder"),
            ProbeStep(.waitForSignal, scene: "scene-B", signal: "split:placeholder")
        ]
    }

    private static func parallelSplitTimeline() -> [ProbeExpectation] {
        ["scene-A", "scene-B"].flatMap { scene in
            [
                ProbeExpectation(.viewStarted, scene: scene, screen: "detail-1", occurrence: 1),
                ProbeExpectation(.viewStarted, scene: scene, screen: "detail-2", occurrence: 1),
                ProbeExpectation(.viewStarted, scene: scene, screen: "placeholder", occurrence: 1)
            ]
        }
    }

    private static func uikitSplitTimeline() -> [ProbeExpectation] {
        [
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "primary"),
        ]
        + uikitOccurrenceExpectations(
            screen: "secondary-1",
            occurrence: 1,
            marker: "post-materialization"
        )
        + uikitOccurrenceExpectations(
            screen: "secondary-2",
            occurrence: 1,
            marker: "post-materialization"
        )
    }

    private static func uikitPopTimeline() -> [ProbeExpectation] {
        [
            ProbeExpectation(.noViewStarted, scene: "scene-A", screen: "primary"),
        ]
        + uikitOccurrenceExpectations(
            screen: "secondary-1",
            occurrence: 1,
            marker: "post-materialization"
        )
        + uikitOccurrenceExpectations(
            screen: "secondary-2",
            occurrence: 1,
            marker: "post-materialization"
        )
        + uikitOccurrenceExpectations(
            screen: "secondary-1",
            occurrence: 2,
            marker: "post-return-materialization"
        )
    }

    private static func uikitOccurrenceExpectations(
        screen: String,
        occurrence: Int,
        marker: String
    ) -> [ProbeExpectation] {
        [
            ProbeExpectation(
                .viewStarted,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence
            ),
            ProbeExpectation(
                .action,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence,
                name: marker
            ),
            ProbeExpectation(
                .resource,
                scene: "scene-A",
                screen: screen,
                occurrence: occurrence,
                name: marker
            )
        ]
    }

    private static func uikitInteractiveSteps(outcome: ProbeTransitionOutcome) -> [ProbeStep] {
        [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "uikit-navigation:secondary-2"),
            ProbeStep(
                .beginUIKitInteractiveTransition,
                scene: "scene-A",
                outcome: outcome
            ),
            ProbeStep(.updateUIKitInteractiveTransition, scene: "scene-A", percentage: 0.35),
            ProbeStep(.resolveUIKitInteractiveTransition, scene: "scene-A", outcome: outcome),
            ProbeStep(.waitForSignal, scene: "scene-A", signal: "transition:\(outcome.rawValue)")
        ]
    }

    private static func parallelWindowSteps() -> [ProbeStep] {
        [
            ProbeStep(.waitForSceneReady, scene: "scene-A"),
            ProbeStep(.setSwiftUIPath, scene: "scene-A", value: "detail-1"),
            ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
            ProbeStep(.setSwiftUIPath, scene: "scene-B", value: "detail-1")
        ]
    }

    private static func parallelWindowTimeline() -> [ProbeExpectation] {
        [
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-A", screen: "detail-1", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "home", occurrence: 1),
            ProbeExpectation(.viewStarted, scene: "scene-B", screen: "detail-1", occurrence: 1)
        ]
    }
}
