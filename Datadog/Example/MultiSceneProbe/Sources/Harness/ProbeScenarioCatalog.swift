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
        "swiftui.stack.abort",
        "swiftui.stack.same-type-replacement",
        "swiftui.stack.different-type-replacement",
        "swiftui.coexistence.semantic-a-automatic-b",
        "swiftui.coexistence.automatic-manual-sheet",
        "swiftui.coexistence.automatic-scene-targeted-sheet",
        "swiftui.coexistence.automatic-scene-targeted-full-screen-cover",
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
        "traces.urlsession-cross-scene",
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
        swiftUIStackAbort,
        swiftUIStackSameTypeReplacement,
        swiftUIStackDifferentTypeReplacement,
        swiftUICoexistenceSemanticAAutomaticB,
        swiftUICoexistenceAutomaticManualSheet,
        swiftUICoexistenceAutomaticSceneTargetedSheet,
        swiftUICoexistenceAutomaticSceneTargetedFullScreenCover,
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
        tracesURLSessionCrossScene,
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
    /// two independent same-name identities completed in reverse order. Local
    /// signals prove exact call sites; raw and reduced backend Operation events
    /// remain the attribution oracle.
    private static let operationsCrossSceneLifecycle = ProbeScenario(
        identifier: "operations.cross-scene.lifecycle",
        trackingMode: .navigationOccurrence,
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
