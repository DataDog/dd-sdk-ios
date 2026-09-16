/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

final class ProbeScenarioRunnerTests: XCTestCase {
    func testPresentationSubtreeIntervalsRemainBalancedAcrossReplacement() {
        var intervals = ProbePresentationSubtreeIntervals()

        XCTAssertTrue(intervals.begin("sheet"))
        XCTAssertTrue(intervals.begin("cover"))
        XCTAssertFalse(intervals.begin("sheet"))
        XCTAssertFalse(
            intervals.end("sheet", whilePresentationIsActive: true)
        )
        XCTAssertTrue(intervals.end("sheet"))
        XCTAssertFalse(intervals.end("sheet"))
        XCTAssertTrue(intervals.end("cover"))
    }

    func testRestoredWindowUsesCurrentLaunchRunID() {
        let restoredWindow = ProbeWindow(
            runID: "previous-run",
            label: "scene-A",
            opensPeer: true
        )

        let normalizedWindow = restoredWindow.normalized(forRunID: "current-run")

        XCTAssertEqual(normalizedWindow.runID, "current-run")
        XCTAssertEqual(normalizedWindow.label, "scene-A")
        XCTAssertTrue(normalizedWindow.opensPeer)
    }

    func testCatalogHasUniqueIdentifiersAndRequiredScenarios() {
        let identifiers = ProbeScenarioCatalog.all.map(\.identifier)

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(
            Set([
                "swiftui.stack.return",
                "operations.navigation.lifecycle",
                "operations.cross-scene.lifecycle",
                "actions.explicit-target.cross-scene-serial",
                "swiftui.stack.abort",
                "swiftui.stack.same-type-replacement",
                "swiftui.coexistence.semantic-a-automatic-b",
                "swiftui.coexistence.automatic-manual-sheet",
                "swiftui.coexistence.automatic-scene-targeted-sheet",
                "swiftui.coexistence.automatic-scene-targeted-full-screen-cover",
                "swiftui.semantic-api.presentation-replacement",
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
                "swiftui.split.same-type-selection",
                "uikit.split.pop-cancel",
                "uikit.split.pop-finish",
                "actions.uikit-scroll-navigation-deceleration",
                "actions.swiftui-button-structured-task",
                "traces.urlsession-cross-scene",
                "traces.urlsession-shared-request",
                "traces.urlsession-reverse-completion",
                "windows.parallel-navigation",
                "windows.close-with-resource",
                "actions.exact-source-handoff",
                "regression.single-scene"
            ]).isSubset(of: Set(identifiers))
        )
    }

    func testUIKitScrollNavigationScenarioRequiresARealGestureAndExactOriginAction() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "actions.uikit-scroll-navigation-deceleration"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertEqual(scenario.layout, .uikitSplitNavigation)
        XCTAssertEqual(scenario.requiredCapabilities, [.nativeUIKitGesture])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(scenario.runtimeOptions.exercisesUIKitScrollOwnership)
        XCTAssertFalse(scenario.runtimeOptions.automaticallyPopsUIKitSplitNavigation)
        XCTAssertTrue(
            scenario.steps.contains {
                $0.signal == "assertion:uikit-scroll-drag-ended-decelerating"
            }
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.signal == "assertion:uikit-scroll-lift-classifies-as-swipe"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .viewStarted
                    && $0.screen == "secondary-3"
                    && $0.occurrence == 1
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .action
                    && $0.name == "uikit-scroll-origin"
                    && $0.screen == "secondary-2"
                    && $0.occurrence == 1
                    && $0.actionType == "scroll"
                    && $0.expectedCount == 1
            }
        )
    }

    func testUIKitScrollClassificationMatchesProductionSwipeThreshold() {
        XCTAssertFalse(
            ProbeUIKitScrollClassification.wouldClassifyAsSwipe(
                CGPoint(x: 0, y: 499)
            )
        )
        XCTAssertTrue(
            ProbeUIKitScrollClassification.wouldClassifyAsSwipe(
                CGPoint(x: 300, y: 400)
            )
        )
    }

    func testTraceOnlyURLSessionScenarioMovesRepresentativeWithoutMovingSpanOwner() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "traces.urlsession-cross-scene"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertEqual(scenario.layout, .stack)
        XCTAssertEqual(scenario.initialWindows, ["scene-A", "scene-B"])
        XCTAssertEqual(scenario.requiredCapabilities, [.multipleScenes])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(scenario.runtimeOptions.exercisesTraceOnlyURLSessionOwnership)
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .startTraceOnlyURLSessionRequest
                    || $0.kind == .completeTraceOnlyURLSessionRequest
            }.map(\.scene),
            ["scene-A", "scene-B"]
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .action
                    && $0.scene == "scene-B"
                    && $0.name == "trace-completion-representative"
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .trace
                    && $0.scene == "scene-A"
                    && $0.screen == "home"
                    && $0.occurrence == 1
                    && $0.expectedCount == 1
            }
        )
    }

    func testTraceOnlyURLSessionReverseCompletionUsesOppositeRepresentatives() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "traces.urlsession-reverse-completion"
            )
        )

        XCTAssertEqual(scenario.requiredCapabilities, [.multipleScenes])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(scenario.runtimeOptions.exercisesTraceOnlyURLSessionOwnership)
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .startTraceOnlyURLSessionRequest
            }.map { "\($0.scene ?? "nil"):\($0.value ?? "nil")" },
            [
                "scene-A:\(ProbeTraceOnlyURLSessionContract.reverseSceneARequestName)",
                "scene-B:\(ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName)"
            ]
        )
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .completeTraceOnlyURLSessionRequest
            }.map { "\($0.scene ?? "nil"):\($0.value ?? "nil")" },
            [
                "scene-A:\(ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName)",
                "scene-B:\(ProbeTraceOnlyURLSessionContract.reverseSceneARequestName)"
            ]
        )
        XCTAssertEqual(
            scenario.completionConditions.compactMap(\.name),
            [
                ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName,
                ProbeTraceOnlyURLSessionContract.reverseSceneARequestName
            ]
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .action
                    && $0.scene == "scene-A"
                    && $0.name == "trace-reverse-b-completion-representative"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .action
                    && $0.scene == "scene-B"
                    && $0.name == "trace-reverse-a-completion-representative"
            }
        )
    }

    func testTraceOnlySharedRequestHasOneCreatorAndOneJoiningConsumer() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "traces.urlsession-shared-request"
            )
        )

        XCTAssertEqual(scenario.requiredCapabilities, [.multipleScenes])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(scenario.runtimeOptions.exercisesTraceOnlyURLSessionOwnership)
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .startTraceOnlyURLSessionRequest
                    || $0.kind == .joinTraceOnlyURLSessionRequest
                    || $0.kind == .completeTraceOnlyURLSessionRequest
            }.map { "\($0.kind.rawValue):\($0.scene ?? "nil")" },
            [
                "start-trace-only-url-session-request:scene-A",
                "join-trace-only-url-session-request:scene-B",
                "complete-trace-only-url-session-request:scene-B"
            ]
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .trace
                    && $0.name == ProbeTraceOnlyURLSessionContract.sharedRequestName
                    && $0.scene == "scene-A"
                    && $0.screen == "home"
                    && $0.occurrence == 1
                    && $0.expectedCount == 1
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .action
                    && $0.scene == "scene-B"
                    && $0.name == "trace-shared-consumer-representative"
            }
        )
    }

    func testSwiftUIButtonStructuredTaskScenarioSuspendsBeforeSceneHandoff() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "actions.swiftui-button-structured-task"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertEqual(scenario.layout, .stack)
        XCTAssertEqual(scenario.requiredCapabilities, [.multipleScenes])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(scenario.runtimeOptions.exercisesSwiftUIButtonStructuredTask)
        XCTAssertTrue(
            scenario.steps.contains {
                $0.scene == "scene-A"
                    && $0.signal == "assertion:"
                        + ProbeSwiftUIButtonStructuredTaskContract.startedAssertion
            }
        )
        XCTAssertEqual(
            scenario.steps.first {
                $0.kind == .releaseSwiftUIButtonStructuredTask
            }?.scene,
            "scene-B"
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .action
                    && $0.name
                        == ProbeSwiftUIButtonStructuredTaskContract.automaticActionName
                    && $0.scene == "scene-A"
                    && $0.actionType == "tap"
                    && $0.expectedCount == 1
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .resource
                    && $0.name == ProbeSwiftUIButtonStructuredTaskContract.resumedMarker
                    && $0.scene == "scene-A"
                    && $0.occurrence == 1
                    && $0.expectedCount == 1
            }
        )
    }

    func testSemanticAutomaticCoexistenceTargetsOnlySceneA() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.semantic-a-automatic-b"
            )
        )

        XCTAssertEqual(scenario.runtimeOptions.semanticNavigationSceneIDs, ["scene-A"])
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.sourceScene == "scene-B"
                    && $0.rumViewOrigin == .automatic
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.scene == "scene-A"
                    && $0.rumViewOrigin == .semantic
            }
        )
        XCTAssertFalse(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "task-delayed"
            }
        )
    }

    func testOperationNavigationLifecycleCoversSuccessFailureAndDuplicateStart() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "operations.navigation.lifecycle"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .startOperation }.map(\.value),
            ["success", "failure", "duplicate", "duplicate"]
        )
        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .succeedOperation }.map(\.value),
            ["success", "duplicate"]
        )
        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .failOperation }.map(\.value),
            ["failure"]
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .waitForSignal
                    && $0.signal == "rum-view:detail-1#3"
            }
        )
        XCTAssertFalse(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .operationStep
            },
            "Operation vitals have no customer mapper; backend evidence is required"
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .action
                    && $0.name == "operation-duplicate-end-detail"
                    && $0.screen == "detail-1"
                    && $0.occurrence == 3
            }
        )
    }

    func testOperationCrossSceneLifecycleCoversSuccessFailureAndReverseCompletion() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "operations.cross-scene.lifecycle"
            )
        )
        let operationSteps = scenario.steps.filter {
            [.startOperation, .succeedOperation, .failOperation].contains($0.kind)
        }

        XCTAssertEqual(scenario.trackingMode, .manual)
        XCTAssertEqual(scenario.initialWindows, ["scene-A", "scene-B"])
        XCTAssertEqual(
            Set(scenario.requiredCapabilities),
            [.multipleScenes, .simultaneousVisibleWindows]
        )
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertEqual(
            operationSteps.map(\.kind),
            [
                .startOperation,
                .succeedOperation,
                .startOperation,
                .failOperation,
                .startOperation,
                .startOperation,
                .succeedOperation,
                .succeedOperation,
            ]
        )
        XCTAssertEqual(
            operationSteps.map(\.scene),
            [
                "scene-A",
                "scene-B",
                "scene-A",
                "scene-B",
                "scene-A",
                "scene-B",
                "scene-B",
                "scene-A",
            ]
        )
        XCTAssertEqual(
            operationSteps.map(\.value),
            [
                "cross-success",
                "cross-success",
                "cross-failure",
                "cross-failure",
                "parallel-alpha",
                "parallel-beta",
                "parallel-beta",
                "parallel-alpha",
            ]
        )
        XCTAssertEqual(Set(operationSteps.compactMap(\.value)).count, 4)
        XCTAssertFalse(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .operationStep
            },
            "Operation vitals have no customer mapper; backend evidence is required"
        )
    }

    func testExplicitOperationTargetReusesCrossSceneContractWithoutSimultaneousCapability() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "operations.explicit-target.cross-scene-serial"
            )
        )
        let inferredScenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "operations.cross-scene.lifecycle"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .manual)
        XCTAssertEqual(scenario.initialWindows, ["scene-A", "scene-B"])
        XCTAssertEqual(Set(scenario.requiredCapabilities), [.multipleScenes])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesExplicitOperationViewTargetSPI(scenario)
        )
        XCTAssertEqual(scenario.steps, inferredScenario.steps)
        XCTAssertEqual(
            scenario.expectedSemanticTimeline,
            inferredScenario.expectedSemanticTimeline
        )
        XCTAssertFalse(
            scenario.steps.contains {
                $0.kind == .waitForSceneReady && $0.scene == "scene-B"
            },
            "open-window already waits for and consumes scene B readiness"
        )
    }

    func testExplicitActionTargetOverridesOppositeRepresentativeAndPreservesLegacyFallback() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "actions.explicit-target.cross-scene-serial"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .manual)
        XCTAssertEqual(scenario.initialWindows, ["scene-A", "scene-B"])
        XCTAssertEqual(Set(scenario.requiredCapabilities), [.multipleScenes])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .emitExplicitTargetAction }.map(\.scene),
            ["scene-A", "scene-B"]
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .action
                    && $0.name == "explicit-action-a-overrides-b"
                    && $0.scene == "scene-A"
                    && $0.sourceScene == "scene-A"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .action
                    && $0.name == "explicit-action-legacy-fallback-to-b"
                    && $0.scene == "scene-B"
                    && $0.sourceScene == "scene-A"
                    && $0.ownerViewReferenceAction == "explicit-action-representative-b"
                    && $0.ownerViewRelation == .same
            }
        )
    }

    func testAutomaticManualSheetTargetsOnlyTheExceptionalScreen() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.automatic-manual-sheet"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertEqual(
            scenario.runtimeOptions.manualSwiftUIViewScreensByScene,
            ["scene-A": ["sheet"]]
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.screen == "sheet" && $0.rumViewOrigin == .semantic
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "sheet-dismissed-settled"
                    && $0.rumViewOrigin == .automatic
                    && $0.ownerViewRelation == .same
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == .automatic
                    && $0.rumViewName == nil
                    && $0.interval == "manual-sheet-active"
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == .automatic
                    && $0.rumViewName == "ProbeSheetView"
                    && $0.interval == "swiftui-presentation-subtree"
            }
        )
    }

    func testSceneTargetedSheetKeepsStrictOracleWithoutViewLifecycleModifier() throws {
        let baseline = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.automatic-manual-sheet"
            )
        )
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.automatic-scene-targeted-sheet"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesSceneTargetedPresentationAuthority(scenario)
        )
        XCTAssertEqual(scenario.steps, baseline.steps)
        XCTAssertEqual(scenario.completionConditions, baseline.completionConditions)
        XCTAssertEqual(scenario.expectedSemanticTimeline, baseline.expectedSemanticTimeline)
        XCTAssertTrue(scenario.runtimeOptions.manualSwiftUIViewScreensByScene.isEmpty)
    }

    func testSceneTargetedFullScreenCoverHasIndependentStrictOracle() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.automatic-scene-targeted-full-screen-cover"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesSceneTargetedPresentationAuthority(scenario)
        )
        XCTAssertTrue(scenario.runtimeOptions.manualSwiftUIViewScreensByScene.isEmpty)
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .setSwiftUIPresentation && $0.value == "full-screen-cover"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .viewStarted
                    && $0.screen == "full-screen-cover"
                    && $0.rumViewOrigin == .semantic
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == .automatic
                    && $0.rumViewName == "ProbeFullScreenCoverView"
                    && $0.interval == "swiftui-full-screen-cover-subtree"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "full-screen-cover-dismissed-immediate"
                    && $0.ownerViewReferenceAction
                        == "automatic-home-before-full-screen-cover"
                    && $0.ownerViewRelation == .different
            }
        )
    }

    func testSemanticNavigationAPICoversCompleteDestinationStream() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.complete-destination"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertFalse(
            ProbeScenarioCatalog.usesSceneTargetedPresentationAuthority(scenario)
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted && $0.rumViewOrigin == .automatic
            }
        )
        for (screen, occurrence) in [
            ("home", 1),
            ("detail-1", 1),
            ("home", 2),
            ("sheet", 1),
            ("home", 3),
            ("full-screen-cover", 1),
            ("home", 4)
        ] {
            XCTAssertTrue(
                scenario.expectedSemanticTimeline.contains {
                    $0.kind == .viewStarted
                        && $0.scene == "scene-A"
                        && $0.screen == screen
                        && $0.occurrence == occurrence
                        && $0.rumViewOrigin == .semantic
                },
                "Missing semantic view occurrence \(screen)#\(occurrence)"
            )
        }
    }

    func testSemanticNavigationHostUsesStandardNavigationWithExplicitSource() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.explicit-source"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesAutomaticSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertEqual(
            scenario.expectedSemanticTimeline.count,
            try XCTUnwrap(
                ProbeScenarioCatalog.scenario(
                    identifier: "swiftui.semantic-api.complete-destination"
                )
            ).expectedSemanticTimeline.count + 4
        )
        XCTAssertTrue(scenario.expectedSemanticTimeline.contains { expectation in
            expectation.kind == .action
                && expectation.name == "on-appear"
                && expectation.screen == "home"
                && expectation.occurrence == 1
        })
        XCTAssertTrue(scenario.expectedSemanticTimeline.contains { expectation in
            expectation.kind == .resource
                && expectation.name == "task-immediate"
                && expectation.screen == "home"
                && expectation.occurrence == 1
        })
    }

    func testEXP147RouterStreamAdapterUsesTheCompleteSemanticOracle() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.router-stream-adapter"
            )
        )
        let completeDestination = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.complete-destination"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesEXP147RouterStreamAdapter(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesAutomaticSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertEqual(scenario.steps, completeDestination.steps)
        XCTAssertEqual(
            scenario.completionConditions,
            completeDestination.completionConditions
        )
        XCTAssertEqual(
            scenario.expectedSemanticTimeline,
            completeDestination.expectedSemanticTimeline
        )
    }

    func testEXP151ObservationRouterAdapterUsesTheCompleteSemanticOracle() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.observation-router-adapter"
            )
        )
        let completeDestination = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.complete-destination"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesEXP151ObservationRouterAdapter(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesEXP147NavigationFixture(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesEXP147RouterStreamAdapter(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesAutomaticSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertEqual(scenario.steps, completeDestination.steps)
        XCTAssertEqual(
            scenario.completionConditions,
            completeDestination.completionConditions
        )
        XCTAssertEqual(
            scenario.expectedSemanticTimeline,
            completeDestination.expectedSemanticTimeline
        )
    }

    func testEXP152NativeDismissCallbacksUseActualCallbackSignals() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier:
                    "swiftui.semantic-host.observation-native-dismiss-callbacks"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesEXP151ObservationRouterAdapter(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesEXP152NativeDismissCallbacks(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesEXP147NavigationFixture(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesEXP147RouterStreamAdapter(scenario))

        let waitedSignals = Set(scenario.steps.compactMap(\.signal))
        let callbackAssertions = [
            ProbeNativeDismissCallbackContract.sheetContentAppeared,
            ProbeNativeDismissCallbackContract.sheetOnDismissEntered,
            ProbeNativeDismissCallbackContract.coverContentAppeared,
            ProbeNativeDismissCallbackContract.coverOnDismissEntered
        ]
        for assertion in callbackAssertions {
            XCTAssertTrue(waitedSignals.contains("assertion:\(assertion)"))
        }
        XCTAssertTrue(
            waitedSignals.contains("marker:sheet-native-on-dismiss-settled")
        )
        XCTAssertTrue(
            waitedSignals.contains(
                "marker:full-screen-cover-native-on-dismiss-settled"
            )
        )
        XCTAssertFalse(waitedSignals.contains("marker:sheet-dismissed-settled"))
        XCTAssertFalse(
            waitedSignals.contains("marker:full-screen-cover-dismissed-settled")
        )

        let callbackMarkers = [
            "sheet-native-on-dismiss-immediate",
            "sheet-native-on-dismiss-settled",
            "full-screen-cover-native-on-dismiss-immediate",
            "full-screen-cover-native-on-dismiss-settled"
        ]
        for marker in callbackMarkers {
            let matches = scenario.expectedSemanticTimeline.filter {
                $0.name == marker
            }
            XCTAssertEqual(matches.map(\.kind), [.action, .resource])
            XCTAssertTrue(matches.allSatisfy { $0.screen == "home" })
            XCTAssertTrue(matches.allSatisfy { $0.rumViewOrigin == .semantic })
        }
    }

    func testEXP154ObservationRouterUsesIndependentScenesSerially() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier:
                    "swiftui.semantic-host.observation-router-two-scenes-serial"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertEqual(scenario.layout, .stack)
        XCTAssertEqual(scenario.initialWindows, ["scene-A", "scene-B"])
        XCTAssertEqual(scenario.requiredCapabilities, [.multipleScenes])
        XCTAssertFalse(
            scenario.requiredCapabilities.contains(.simultaneousVisibleWindows)
        )
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario)
        )
        XCTAssertTrue(
            ProbeScenarioCatalog.usesEXP151ObservationRouterAdapter(scenario)
        )
        XCTAssertTrue(ProbeScenarioCatalog.usesEXP147NavigationFixture(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesEXP147RouterStreamAdapter(scenario))
        XCTAssertFalse(
            ProbeScenarioCatalog.usesEXP152NativeDismissCallbacks(scenario)
        )
        XCTAssertFalse(
            ProbeScenarioCatalog.usesEXP153ThirdPartyCallbackAdapter(scenario)
        )

        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .openWindow }.map {
                "\($0.scene ?? ""):\($0.value ?? "")"
            },
            ["scene-A:scene-B"]
        )
        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .waitForSceneReady }
                .compactMap(\.scene),
            ["scene-A"]
        )
        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .setSwiftUIPath }.map {
                "\($0.scene ?? ""):\($0.value ?? "")"
            },
            [
                "scene-A:detail-1",
                "scene-A:home",
                "scene-B:detail-1",
                "scene-B:home"
            ]
        )
        XCTAssertEqual(
            scenario.steps.filter { $0.kind == .emitSceneContextMarker }
                .compactMap(\.value),
            [
                "observation-a-home-1",
                "observation-a-detail-1",
                "observation-a-home-2",
                "observation-b-home-1",
                "observation-b-detail-1",
                "observation-b-home-2"
            ]
        )
        XCTAssertFalse(scenario.steps.contains { $0.kind == .emitMarker })
        XCTAssertEqual(scenario.expectedSemanticTimeline.count, 22)
        XCTAssertEqual(scenario.completionConditions.count, 3)
        XCTAssertEqual(
            scenario.expectedSemanticTimeline.filter {
                $0.kind == .viewStarted && $0.screen == "home"
            }.map { "\($0.scene ?? "")#\($0.occurrence ?? 0)" },
            [
                "scene-A#1",
                "scene-A#2",
                "scene-B#1",
                "scene-B#2"
            ]
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted && $0.rumViewOrigin == .automatic
            }
        )
        for kind in [ProbeExpectationKind.action, .resource] {
            XCTAssertTrue(
                scenario.completionConditions.contains {
                    $0.kind == kind
                        && $0.scene == "scene-B"
                        && $0.screen == "home"
                        && $0.occurrence == 2
                        && $0.name == "observation-b-home-2"
                        && $0.rumViewOrigin == .semantic
                }
            )
        }
    }

    func testEXP153ThirdPartyCallbackAdapterUsesCompleteSemanticOracle() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.third-party-callback-adapter"
            )
        )
        let completeDestination = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.complete-destination"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesEXP153ThirdPartyCallbackAdapter(scenario)
        )
        XCTAssertFalse(ProbeScenarioCatalog.usesEXP147NavigationFixture(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesEXP147RouterStreamAdapter(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesEXP151ObservationRouterAdapter(scenario))
        XCTAssertEqual(
            Array(scenario.steps.dropLast()),
            completeDestination.steps
        )
        XCTAssertEqual(
            scenario.steps.last?.signal,
            "assertion:"
                + ProbeThirdPartyCallbackAdapterContract.singleRegistrationAssertion
        )
        XCTAssertEqual(
            scenario.completionConditions,
            completeDestination.completionConditions
        )
        XCTAssertEqual(
            scenario.expectedSemanticTimeline.count,
            completeDestination.expectedSemanticTimeline.count + 4
        )
        for marker in ["on-appear", "task-immediate"] {
            let matches = scenario.expectedSemanticTimeline.filter {
                $0.name == marker
            }
            XCTAssertEqual(matches.map(\.kind), [.action, .resource])
            XCTAssertTrue(matches.allSatisfy { $0.screen == "home" })
            XCTAssertTrue(matches.allSatisfy { $0.occurrence == 1 })
        }
    }

    @MainActor
    func testEXP147RouterGrowthUsesGenericProbeSemantics() {
        let router = EXP147NavigationRouter(flow: .messages)

        router.push(.scheduledMessages)
        XCTAssertEqual(
            EXP147ProbeSemantics.route(for: router.state),
            ["home", "scheduled-messages"]
        )

        router.present(.compose)
        XCTAssertEqual(
            EXP147ProbeSemantics.route(for: router.state),
            ["home", "scheduled-messages", "sheet"]
        )

        router.dismissPresentation()
        XCTAssertEqual(
            EXP147ProbeSemantics.route(for: router.state),
            ["home", "scheduled-messages"]
        )
    }

    @MainActor
    func testEXP153ThirdPartyCallbackPublishesCurrentAndAcceptedStateSynchronously() {
        let navigator = EXP153ThirdPartyNavigator()
        var order: [String] = []
        let observation = navigator.observeAcceptedSnapshots { snapshot in
            order.append(
                "callback-\(EXP153ProbeSemantics.screen(for: snapshot))"
            )
        }
        order.append("registered")

        navigator.push(.thread(1))
        order.append("after-push")

        XCTAssertEqual(
            order,
            ["callback-home", "registered", "callback-detail-1", "after-push"]
        )
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testEXP153ThirdPartyCallbackDistinguishesEqualRouteOccurrences() {
        let navigator = EXP153ThirdPartyNavigator()
        var snapshots: [EXP153ThirdPartyNavigator.Snapshot] = []
        let observation = navigator.observeAcceptedSnapshots {
            snapshots.append($0)
        }

        navigator.push(.thread(1))
        navigator.push(.thread(1))

        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots[1].path.last?.route, .thread(1))
        XCTAssertEqual(snapshots[2].path.last?.route, .thread(1))
        XCTAssertNotEqual(
            snapshots[1].path.last?.id,
            snapshots[2].path.last?.id
        )
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testEXP153ThirdPartyCallbackPublishesOnlyCommittedInteractivePop() {
        let navigator = EXP153ThirdPartyNavigator()
        var screens: [String] = []
        let observation = navigator.observeAcceptedSnapshots {
            screens.append(EXP153ProbeSemantics.screen(for: $0))
        }
        navigator.push(.thread(1))

        navigator.beginInteractivePop()
        navigator.resolveInteractivePop(committed: false)
        XCTAssertEqual(screens, ["home", "detail-1"])

        navigator.beginInteractivePop()
        navigator.resolveInteractivePop(committed: true)
        XCTAssertEqual(screens, ["home", "detail-1", "home"])
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testEXP153ThirdPartyCallbackReplacesPresentationAtomically() {
        let navigator = EXP153ThirdPartyNavigator()
        var screens: [String] = []
        let observation = navigator.observeAcceptedSnapshots {
            screens.append(EXP153ProbeSemantics.screen(for: $0))
        }

        navigator.present(.compose)
        navigator.present(.attachment(1))
        navigator.dismissPresentation()

        XCTAssertEqual(
            screens,
            ["home", "sheet", "full-screen-cover", "home"]
        )
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testEXP153ThirdPartyObservationDeallocationReleasesRegistration() {
        let navigator = EXP153ThirdPartyNavigator()
        var observation: EXP153ThirdPartyNavigator.Observation? =
            navigator.observeAcceptedSnapshots { _ in }

        XCTAssertEqual(navigator.observerRegistrationCount, 1)
        XCTAssertEqual(navigator.activeObserverCount, 1)

        observation = nil

        XCTAssertNil(observation)
        XCTAssertEqual(navigator.activeObserverCount, 0)
    }

    func testEXP147MigrationFixtureKeepsCustomerNavigationUninstrumented() throws {
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = projectDirectory
            .appendingPathComponent("Sources/EXP147MigrationFixture")
        let customerFiles = [
            "EXP147NavigationModel.swift",
            "EXP147ScreenScaffold.swift",
            "EXP147MessagingScreens.swift",
            "EXP147NotesScreens.swift",
            "EXP147SettingsScreens.swift",
            "EXP147PresentationScreens.swift",
            "EXP147BaselineNavigation.swift"
        ]

        for file in customerFiles {
            let source = try String(
                contentsOf: fixtureDirectory.appendingPathComponent(file),
                encoding: .utf8
            )
            XCTAssertFalse(source.contains("import DatadogRUM"), file)
            XCTAssertFalse(source.contains("RUMNavigationHost"), file)
            XCTAssertFalse(source.contains("RUMNavigationTransitions"), file)
            XCTAssertFalse(source.contains("willNavigate("), file)
            XCTAssertFalse(source.contains("commit(id:"), file)
        }

        let routerSource = try String(
            contentsOf: fixtureDirectory
                .appendingPathComponent("EXP147NavigationModel.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(
            routerSource.components(separatedBy: "\n    func ").count - 1,
            12,
            "The fixture's twelve customer navigation methods must stay RUM-free"
        )

        let navigationSource = try String(
            contentsOf: fixtureDirectory
                .appendingPathComponent("EXP147BaselineNavigation.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(navigationSource.contains("NavigationStack(path: router.path)"))
        XCTAssertTrue(navigationSource.contains(".sheet(item: router.sheet)"))
        XCTAssertTrue(
            navigationSource.contains(
                ".fullScreenCover(item: router.fullScreenCover)"
            )
        )
        XCTAssertTrue(
            navigationSource.contains("struct EXP147NativeSwiftUIContainer")
        )
        XCTAssertTrue(
            navigationSource.contains("struct EXP147OpaqueThirdPartyContainer")
        )
        XCTAssertTrue(
            navigationSource.contains("struct EXP153ThirdPartyNavigationContainer")
        )
        let customContainerSource = try XCTUnwrap(
            navigationSource.components(
                separatedBy: "struct EXP153ThirdPartyNavigationContainer"
            ).last
        )
        XCTAssertFalse(customContainerSource.contains("NavigationStack"))
        XCTAssertFalse(customContainerSource.contains(".sheet("))
        XCTAssertFalse(customContainerSource.contains(".fullScreenCover("))

        let adapterSource = try String(
            contentsOf: fixtureDirectory
                .appendingPathComponent("EXP147RouterStreamAdapter.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            adapterSource.contains("scheduledMessages"),
            "Adding the growth route must not add adapter-specific code"
        )
        XCTAssertFalse(
            adapterSource.contains("shareThread"),
            "Adding the growth presentation must not add adapter-specific code"
        )
        XCTAssertFalse(adapterSource.contains("willNavigate("))
        XCTAssertFalse(adapterSource.contains("commit(id:"))
        XCTAssertTrue(
            adapterSource.contains("final class EXP153ThirdPartyRUMAdapter")
        )
        XCTAssertTrue(
            adapterSource.contains("navigator.observeAcceptedSnapshots")
        )
        XCTAssertTrue(
            adapterSource.contains("struct EXP153RUMThirdPartyBoundary")
        )
        XCTAssertFalse(
            adapterSource.contains(
                "extension EXP153ThirdPartyNavigationContainer: "
                    + "RUMNavigationTransitionProviding"
            )
        )
        XCTAssertTrue(adapterSource.contains("observing: router.statePublisher"))
        XCTAssertTrue(
            adapterSource.contains("observingCurrentDestination:"),
            "The Observation candidate must remain one boundary projection"
        )
        let compositionSource = try String(
            contentsOf: fixtureDirectory
                .appendingPathComponent("EXP147InstrumentedComposition.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(compositionSource.contains(".overriding("))
        XCTAssertTrue(compositionSource.contains("EXP147Route.preferences"))
        XCTAssertTrue(
            compositionSource.contains("name: \"Account preferences\""),
            "The sparse override must be observably different from automatic naming"
        )
        XCTAssertTrue(
            compositionSource.contains("EXP147FallbackInstrumentedApplication")
        )
        XCTAssertEqual(
            compositionSource
                .components(separatedBy: "EXP147RUMRouterBoundary(")
                .count - 1,
            3,
            "Exact tracking should add one boundary per observable router"
        )
        XCTAssertEqual(
            compositionSource
                .components(separatedBy: "RUMNavigationHost {")
                .count - 1,
            2,
            "Native and opaque arms should each use one automatic fallback boundary"
        )
    }

    func testSemanticNavigationHostCapabilityUsesTheExactSemanticOracle() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.optional-capability"
            )
        )
        let explicit = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.explicit-source"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesAutomaticSemanticNavigationHostSPI(scenario))
        XCTAssertEqual(scenario.steps, explicit.steps)
        XCTAssertEqual(scenario.completionConditions, explicit.completionConditions)
        XCTAssertEqual(scenario.expectedSemanticTimeline, explicit.expectedSemanticTimeline)
    }

    func testSemanticNavigationHostExplicitPrecedenceUsesTheExactSemanticOracle() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.explicit-precedence"
            )
        )
        let explicit = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.explicit-source"
            )
        )

        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesExplicitSemanticNavigationPrecedenceSPI(scenario)
        )
        XCTAssertFalse(ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI(scenario))
        XCTAssertEqual(scenario.steps, explicit.steps)
        XCTAssertEqual(scenario.expectedSemanticTimeline, explicit.expectedSemanticTimeline)
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .noViewStarted
                && expectation.screen
                    == ProbeSemanticHostContract.conflictingCapabilityScreen
                && expectation.rumViewOrigin == .semantic
        })
    }

    func testSemanticNavigationHostCapabilityLifetimeUsesTheExactSemanticOracle() throws {
        let explicit = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.explicit-source"
            )
        )
        let scenarios = try [
            (
                XCTUnwrap(
                    ProbeScenarioCatalog.scenario(
                        identifier: "swiftui.semantic-host.capability-reconstruction"
                    )
                ),
                ProbeSemanticHostContract.capabilityReconstructedAssertion,
                false
            ),
            (
                XCTUnwrap(
                    ProbeScenarioCatalog.scenario(
                        identifier: "swiftui.semantic-host.capability-replacement"
                    )
                ),
                ProbeSemanticHostContract.capabilityReplacedAssertion,
                true
            )
        ]

        for (scenario, assertion, replacesSource) in scenarios {
            XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
            XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
            XCTAssertFalse(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
            XCTAssertTrue(ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI(scenario))
            XCTAssertTrue(
                ProbeScenarioCatalog.usesObservedSemanticNavigationCapabilitySPI(scenario)
            )
            XCTAssertEqual(
                ProbeScenarioCatalog.replacesSemanticNavigationCapabilitySource(scenario),
                replacesSource
            )
            XCTAssertTrue(ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI(scenario))
            XCTAssertEqual(scenario.expectedSemanticTimeline, explicit.expectedSemanticTimeline)
            XCTAssertTrue(scenario.steps.contains { step in
                step.kind == .waitForSignal
                    && step.signal == "assertion:" + assertion
            })
            XCTAssertTrue(scenario.completionConditions.contains { expectation in
                expectation.kind == .noViewStarted
                    && expectation.screen
                        == ProbeSemanticHostContract.conflictingCapabilityScreen
                    && expectation.rumViewOrigin == .semantic
            })
        }
    }

    func testSemanticNavigationHostTransientReaderReattachPreservesOccurrenceAndSource()
        throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.transient-reader-reattach"
            )
        )

        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesSemanticNavigationHostLifetimeTestingSPI(scenario)
        )
        XCTAssertFalse(ProbeScenarioCatalog.usesSemanticNavigationHostFinalDetachSPI(scenario))
        XCTAssertTrue(scenario.steps.contains { step in
            step.kind == .bounceSemanticNavigationHostReader
                && step.scene == "scene-A"
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .viewStarted
                && expectation.scene == "scene-A"
                && expectation.screen == "detail-1"
                && expectation.expectedCount == 1
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .action
                && expectation.name == "semantic-host-after-transient-reattach"
                && expectation.ownerViewReferenceAction
                    == "semantic-host-before-transient-reattach"
                && expectation.ownerViewRelation == .same
        })
        XCTAssertTrue(scenario.expectedSemanticTimeline.contains { expectation in
            expectation.kind == .viewStarted
                && expectation.scene == "scene-A"
                && expectation.screen == "home"
                && expectation.occurrence == 2
                && expectation.rumViewOrigin == .semantic
        })
    }

    func testSemanticNavigationHostFinalRemovalIsSceneIsolatedAndFallsBackToAutomatic()
        throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.final-removal-isolation"
            )
        )

        XCTAssertEqual(scenario.initialWindows, ["scene-A", "scene-B"])
        XCTAssertEqual(scenario.requiredCapabilities, [.multipleScenes])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            ProbeScenarioCatalog.usesSemanticNavigationHostLifetimeTestingSPI(scenario)
        )
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostFinalDetachSPI(scenario))
        XCTAssertTrue(scenario.steps.contains { step in
            step.kind == .removeSemanticNavigationHost
                && step.scene == "scene-A"
                && step.value == "home#1"
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .viewStopped
                && expectation.scene == "scene-A"
                && expectation.screen == "home"
                && expectation.expectedCount == 1
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .viewStopped
                && expectation.scene == "scene-B"
                && expectation.screen == "home"
                && expectation.expectedCount == 1
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .viewStarted
                && expectation.scene == "scene-B"
                && expectation.screen == "detail-1"
                && expectation.expectedCount == 1
                && expectation.rumViewOrigin == .semantic
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .action
                && expectation.name == "semantic-host-after-final-removal"
                && expectation.sourceScene == "scene-A"
                && expectation.sourceScreen == "detail-1"
                && expectation.rumViewOrigin == .automatic
                && expectation.ownerViewStartedAfterStep
                    == .removeSemanticNavigationHost
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .action
                && expectation.name == "semantic-host-peer-after-final-removal"
                && expectation.scene == "scene-B"
                && expectation.occurrence == 1
                && expectation.ownerViewRelation == .same
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .action
                && expectation.name
                    == "semantic-host-peer-transition-after-final-removal"
                && expectation.scene == "scene-B"
                && expectation.screen == "detail-1"
                && expectation.ownerViewReferenceAction
                    == "semantic-host-peer-after-final-removal"
                && expectation.ownerViewRelation == .different
        })
    }

    func testSemanticNavigationHostOpaqueContainerKeepsAutomaticFallback() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-host.automatic-fallback"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesAutomaticSemanticNavigationHostSPI(scenario))
        XCTAssertEqual(
            scenario.expectedSemanticTimeline,
            [ProbeExpectation(.viewStarted, rumViewOrigin: .automatic)]
        )
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .viewStarted
                && expectation.rumViewOrigin == .automatic
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .noViewStarted
                && expectation.rumViewOrigin == .semantic
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .action
                && expectation.name == "task-delayed"
                && expectation.sourceScreen == "detail-1"
                && expectation.rumViewOrigin == .automatic
        })
        XCTAssertTrue(scenario.completionConditions.contains { expectation in
            expectation.kind == .resource
                && expectation.name == "task-delayed"
                && expectation.sourceScreen == "detail-1"
                && expectation.rumViewOrigin == .automatic
        })
    }

    func testSemanticNavigationAPICoversPresentationReplacement() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.presentation-replacement"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertEqual(
            scenario.steps
                .filter { $0.kind == .setSwiftUIPresentation }
                .compactMap(\.value),
            ["sheet", "full-screen-cover", "sheet", "home"]
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted && $0.rumViewOrigin == .automatic
            }
        )
        for (screen, occurrence) in [
            ("home", 1),
            ("sheet", 1),
            ("full-screen-cover", 1),
            ("sheet", 2),
            ("home", 2)
        ] {
            XCTAssertTrue(
                scenario.expectedSemanticTimeline.contains {
                    $0.kind == .viewStarted
                        && $0.scene == "scene-A"
                        && $0.screen == screen
                        && $0.occurrence == occurrence
                        && $0.rumViewOrigin == .semantic
                },
                "Missing semantic presentation occurrence \(screen)#\(occurrence)"
            )
        }
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .viewStarted
                    && $0.screen == "home"
                    && $0.expectedCount == 2
            }
        )
        for (screen, occurrence) in [
            ("sheet", 1),
            ("full-screen-cover", 1),
            ("sheet", 2)
        ] {
            for phase in ["on-appear", "task-immediate"] {
                for kind in [ProbeExpectationKind.action, .resource] {
                    XCTAssertTrue(
                        scenario.completionConditions.contains {
                            $0.kind == kind
                                && $0.screen == screen
                                && $0.occurrence == occurrence
                                && $0.name == phase
                                && $0.rumViewOrigin == .semantic
                        }
                    )
                }
            }
        }
    }

    func testSemanticNavigationAPIExercisesRepeatedNativeValueLinks() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.repeated-value-links"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationValueLinks(scenario))
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted && $0.rumViewOrigin == .automatic
            }
        )
        for (screen, occurrence) in [
            ("home", 1),
            ("detail-1", 1),
            ("detail-1", 2),
            ("detail-1", 3),
            ("home", 2)
        ] {
            XCTAssertTrue(
                scenario.expectedSemanticTimeline.contains {
                    $0.kind == .viewStarted
                        && $0.screen == screen
                        && $0.occurrence == occurrence
                        && $0.rumViewOrigin == .semantic
                }
            )
        }
        for (screen, occurrence, name) in [
            ("detail-1", 1, "binding-update-1"),
            ("detail-1", 2, "binding-update-1"),
            ("detail-1", 3, "navigation-appearance-2"),
            ("home", 2, "navigation-appearance-2")
        ] {
            for kind in [ProbeExpectationKind.action, .resource] {
                XCTAssertTrue(
                    scenario.completionConditions.contains {
                        $0.kind == kind
                            && $0.screen == screen
                            && $0.occurrence == occurrence
                            && $0.name == name
                            && $0.rumViewOrigin == .semantic
                    }
                )
            }
        }
    }

    func testSemanticNavigationAPIExercisesInitialRepeatedPath() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.initial-repeated-path"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
        XCTAssertEqual(scenario.runtimeOptions.initialSwiftUIPath, ["detail-1", "detail-1"])
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertFalse(ProbeScenarioCatalog.usesSemanticNavigationValueLinks(scenario))
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted && $0.rumViewOrigin == .automatic
            }
        )
        for (screen, occurrence) in [
            ("detail-1", 1),
            ("detail-1", 2),
            ("home", 1)
        ] {
            XCTAssertTrue(
                scenario.expectedSemanticTimeline.contains {
                    $0.kind == .viewStarted
                        && $0.screen == screen
                        && $0.occurrence == occurrence
                        && $0.rumViewOrigin == .semantic
                }
            )
        }
        for phase in ["navigation-appearance-1", "on-appear", "task-immediate"] {
            for kind in [ProbeExpectationKind.action, .resource] {
                XCTAssertTrue(
                    scenario.expectedSemanticTimeline.contains {
                        $0.kind == kind
                            && $0.screen == "detail-1"
                            && $0.occurrence == 1
                            && $0.name == phase
                            && $0.sourceScreen == "home"
                            && $0.rumViewOrigin == .semantic
                    }
                )
            }
        }
    }

    func testSemanticNavigationAPICoversExternalRejectedAndCanonicalRouterWrites() throws {
        let external = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.external-replacements"
            )
        )
        let rejected = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.rejected-link-write"
            )
        )
        let canonicalized = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.canonicalized-link-write"
            )
        )

        for scenario in [external, rejected, canonicalized] {
            XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
            XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
            XCTAssertTrue(
                scenario.completionConditions.contains {
                    $0.kind == .noViewStarted && $0.rumViewOrigin == .automatic
                }
            )
        }

        XCTAssertEqual(
            external.steps.filter { $0.kind == .setSwiftUIPath }.compactMap(\.value),
            ["detail-1", "detail-2", "alternate"]
        )
        for screen in ["home", "detail-1", "detail-2", "alternate"] {
            XCTAssertTrue(
                external.expectedSemanticTimeline.contains {
                    $0.kind == .viewStarted
                        && $0.screen == screen
                        && $0.occurrence == 1
                        && $0.rumViewOrigin == .semantic
                }
            )
        }

        XCTAssertEqual(rejected.runtimeOptions.swiftUIRouterWritePolicy, .reject)
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationValueLinks(rejected))
        XCTAssertFalse(
            rejected.steps.contains {
                $0.kind == .setSwiftUIPath || $0.kind == .replaceSwiftUIDestination
            }
        )
        XCTAssertTrue(
            rejected.steps.contains {
                $0.signal == "assertion:\(ProbeSemanticRouterContract.rejectedAssertion)"
            }
        )
        XCTAssertTrue(
            rejected.steps.contains {
                $0.signal == "assertion:\(ProbeSemanticRouterContract.settledAssertion)"
            }
        )
        XCTAssertTrue(
            rejected.completionConditions.contains {
                $0.kind == .noEvent
                    && $0.scene == "scene-A"
                    && $0.screen == "detail-1"
                    && $0.sourceScene == nil
                    && $0.sourceScreen == nil
            }
        )
        XCTAssertTrue(
            rejected.completionConditions.contains {
                $0.kind == .viewStopped
                    && $0.screen == "home"
                    && $0.expectedCount == 0
            }
        )

        XCTAssertEqual(
            canonicalized.runtimeOptions.swiftUIRouterWritePolicy,
            .canonicalizeToAlternate
        )
        XCTAssertTrue(
            ProbeScenarioCatalog.usesSemanticNavigationValueLinks(canonicalized)
        )
        XCTAssertFalse(
            canonicalized.steps.contains {
                $0.kind == .setSwiftUIPath || $0.kind == .replaceSwiftUIDestination
            }
        )
        XCTAssertTrue(
            canonicalized.steps.contains {
                $0.signal
                    == "assertion:\(ProbeSemanticRouterContract.canonicalizedAssertion)"
            }
        )
        XCTAssertTrue(
            canonicalized.steps.contains {
                $0.signal == "assertion:\(ProbeSemanticRouterContract.settledAssertion)"
            }
        )
        XCTAssertTrue(
            canonicalized.completionConditions.contains {
                $0.kind == .noViewStarted && $0.screen == "detail-1"
            }
        )
        XCTAssertTrue(
            canonicalized.completionConditions.contains {
                $0.kind == .noEvent
                    && $0.scene == "scene-A"
                    && $0.screen == "detail-1"
                    && $0.sourceScene == nil
                    && $0.sourceScreen == nil
            }
        )
        XCTAssertFalse(
            canonicalized.steps.contains {
                $0.signal == "marker:task-delayed"
            }
        )
        XCTAssertTrue(
            canonicalized.expectedSemanticTimeline.contains {
                $0.kind == .viewStarted
                    && $0.screen == "alternate"
                    && $0.occurrence == 1
                    && $0.rumViewOrigin == .semantic
            }
        )
    }

    func testAutomaticKeyedManualViewRequiresFreshAutomaticOwnerAfterStop() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.automatic-keyed-manual-view"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .startKeyedManualView && $0.value == "compose"
            }
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .stopKeyedManualView && $0.value == "compose"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "keyed-manual-stopped-immediate"
                    && $0.ownerViewStartedAfterStep == .stopKeyedManualView
                    && $0.ownerViewRelation == .different
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .viewStopped
                    && $0.rumViewOrigin == .automatic
                    && $0.ownerViewReferenceAction == "automatic-home-before-keyed-manual"
                    && $0.ownerViewRelation == .same
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == .automatic
                    && $0.interval == "keyed-manual-authority-scene-A"
            }
        )
        XCTAssertEqual(
            scenario.expectedSemanticTimeline.filter {
                $0.name == "keyed-manual-active"
                    && $0.scene == "scene-A"
                    && $0.screen == "compose"
                    && $0.occurrence == 1
                    && $0.rumViewOrigin == .semantic
            }.map(\.kind),
            [.action, .resource]
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .viewStopped
                    && $0.scene == "scene-A"
                    && $0.screen == "compose"
                    && $0.occurrence == 1
                    && $0.rumViewOrigin == .semantic
            }
        )
        for marker in [
            "keyed-manual-stopped-immediate",
            "keyed-manual-stopped-settled"
        ] {
            XCTAssertEqual(
                scenario.expectedSemanticTimeline.filter { $0.name == marker }.map(\.kind),
                [.action, .resource]
            )
        }
    }

    func testNestedKeyedManualViewRequiresFreshComposeAndHomeOccurrences() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.nested-keyed-manual-view"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .startKeyedManualView && $0.value == "compose"
            }.count,
            2
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .startKeyedManualView && $0.value == "preview"
            }
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .stopKeyedManualView && $0.value == "preview"
            }
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .waitForSignal && $0.signal == "rum-view:compose#2"
            }
        )
        XCTAssertEqual(
            scenario.expectedSemanticTimeline.filter {
                $0.kind == .viewStarted
                    && $0.scene == "scene-A"
                    && $0.screen == "compose"
            }.compactMap(\.occurrence),
            [1, 2]
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == nil
                    && $0.interval
                        == "duplicate-keyed-manual-start-compose-scene-A"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "duplicate-keyed-manual-start-compose-scene-A"
                    && $0.scene == "scene-A"
                    && $0.screen == "compose"
                    && $0.occurrence == 2
                    && $0.ownerViewReferenceAction
                        == "nested-keyed-manual-compose-resumed"
                    && $0.ownerViewRelation == .same
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "keyed-manual-stopped-immediate"
                    && $0.ownerViewStartedAfterStep == .stopKeyedManualView
                    && $0.ownerViewStartedAfterStepValue == "compose"
                    && $0.ownerViewReferenceAction
                        == "automatic-home-before-nested-keyed-manual"
                    && $0.ownerViewRelation == .different
            }
        )
    }

    func testSameKeyManualTwoScenesUsesExactContextAndReverseOrderStops() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.same-key-manual-two-scenes"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertEqual(scenario.initialWindows, ["scene-A", "scene-B"])
        XCTAssertEqual(
            Set(scenario.requiredCapabilities),
            [.multipleScenes, .simultaneousVisibleWindows]
        )
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .startKeyedManualView && $0.value == "compose"
            }.compactMap(\.scene),
            ["scene-A", "scene-B"]
        )
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .stopKeyedManualView && $0.value == "compose"
            }.compactMap(\.scene),
            ["scene-B", "scene-A"]
        )
        XCTAssertEqual(
            Set(
                scenario.steps.filter {
                    $0.kind == .emitSceneContextMarker
                }.compactMap(\.scene)
            ),
            ["scene-A", "scene-B"]
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == .automatic
                    && $0.interval == "keyed-manual-authority-scene-B"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "same-key-compose-b-active"
                    && $0.scene == "scene-B"
                    && $0.screen == "compose"
                    && $0.occurrence == 1
                    && $0.ownerViewReferenceAction
                        == "same-key-compose-a-active"
                    && $0.ownerViewRelation == .different
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "same-key-compose-a-after-b-stop"
                    && $0.scene == "scene-A"
                    && $0.screen == "compose"
                    && $0.ownerViewReferenceAction
                        == "same-key-compose-a-active"
                    && $0.ownerViewRelation == .same
            }
        )
    }

    func testSiblingContainerAuthorityStagesLatestAutomaticDestination() throws {
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.sibling-container-authority"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertEqual(
            scenario.runtimeOptions.swiftUIStress,
            .siblingContainerAuthority
        )
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .setSwiftUIPath && $0.value == "detail-1"
            }
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .waitForSignal
                    && $0.signal == "assertion:sibling-controller-topology"
            }
        )
        XCTAssertTrue(
            scenario.steps.contains {
                $0.kind == .emitMarker
                    && $0.value == "sibling-underlying-detail-active"
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == .automatic
                    && $0.interval == "manual-sibling-authority"
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewName == "AutoTracked_HostingController_Fallback"
                    && $0.interval == "sibling-container-observation"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "sibling-underlying-detail-active"
                    && $0.sourceScreen == "detail-1"
                    && $0.screen == "sibling-authority"
                    && $0.rumViewOrigin == .semantic
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.name == "sibling-authority-stopped-immediate"
                    && $0.ownerViewStartedAfterStep == .stopKeyedManualView
                    && $0.ownerViewStartedAfterStepValue == "sibling-authority"
                    && $0.ownerViewReferenceAction == "sibling-home-before-authority"
                    && $0.ownerViewRelation == .different
            }
        )
    }

    func testSemanticSiblingContainerIsolationReusesTopologyWithActualSPI() throws {
        let control = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.coexistence.sibling-container-authority"
            )
        )
        let scenario = try XCTUnwrap(
            ProbeScenarioCatalog.scenario(
                identifier: "swiftui.semantic-api.sibling-container-isolation"
            )
        )

        XCTAssertEqual(scenario.trackingMode, .automatic)
        XCTAssertEqual(scenario.steps.count, control.steps.count - 1)
        XCTAssertEqual(
            scenario.steps.filter {
                $0.kind == .waitForSignal && $0.signal == "marker:task-delayed"
            }.count,
            1
        )
        XCTAssertEqual(scenario.runtimeOptions, control.runtimeOptions)
        XCTAssertEqual(
            scenario.runtimeOptions.swiftUIStress,
            .siblingContainerAuthority
        )
        XCTAssertFalse(ProbeScenarioCatalog.usesSemanticNavigationSPI(control))
        XCTAssertTrue(ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario))
        XCTAssertTrue(ProbeScenarioCatalog.usesObservableDriver(scenario))
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.rumViewOrigin == .automatic
                    && $0.interval == nil
            }
        )
        XCTAssertTrue(
            scenario.completionConditions.contains {
                $0.kind == .noViewStarted
                    && $0.screen == "detail-1"
                    && $0.rumViewOrigin == .semantic
                    && $0.interval == "manual-sibling-authority"
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .viewStarted
                    && $0.screen == "home"
                    && $0.occurrence == 1
                    && $0.rumViewOrigin == .semantic
            }
        )
        XCTAssertTrue(
            scenario.expectedSemanticTimeline.contains {
                $0.kind == .viewStarted
                    && $0.screen == "detail-1"
                    && $0.occurrence == 1
                    && $0.rumViewOrigin == .semantic
            }
        )
    }

    func testUIKitSplitScenariosTreatPrimaryAsStructuralContext() throws {
        for identifier in [
            "uikit.split.replacement",
            "uikit.split.subclass",
            "uikit.split.pop-automatic",
            "uikit.split.pop-cancel",
            "uikit.split.pop-finish",
            "uikit.split.native-pop-control",
            "uikit.split.native-pop-cancel",
            "uikit.split.native-pop-finish",
            "uikit.split.concurrent-scenes"
        ] {
            let scenario = try XCTUnwrap(
                ProbeScenarioCatalog.scenario(identifier: identifier)
            )

            XCTAssertTrue(
                scenario.expectedSemanticTimeline.contains(
                    ProbeExpectation(
                        .noViewStarted,
                        scene: "scene-A",
                        screen: "primary"
                    )
                ),
                "\(identifier) must not model the structural Primary pane as a RUM view"
            )
            XCTAssertFalse(
                scenario.expectedSemanticTimeline.contains {
                    $0.kind == .viewStarted && $0.screen == "primary"
                },
                "\(identifier) must model only the current destination"
            )
        }
    }

    func testEveryCatalogScenarioResolvesWithItsDefaultRunMode() {
        for scenario in ProbeScenarioCatalog.all {
            let resolution = ProbeScenarioRunner.resolve(
                arguments: ["probe", "--probe-scenario", scenario.identifier],
                environment: [:]
            )

            XCTAssertTrue(
                resolution.isValid,
                "\(scenario.identifier): \(resolution.manifest.validationErrors)"
            )
            XCTAssertEqual(resolution.manifest.runMode, scenario.defaultRunMode)
        }
    }

    func testDefaultResolutionUsesInteractiveScenarioAndGeneratedRunID() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe"],
            environment: [:],
            generatedRunID: { "generated-run-id" }
        )

        XCTAssertTrue(resolution.isValid)
        XCTAssertEqual(resolution.scenario?.identifier, ProbeScenarioCatalog.defaultIdentifier)
        XCTAssertEqual(resolution.manifest.runID, "generated-run-id")
        XCTAssertEqual(resolution.manifest.runMode, .clean)
        XCTAssertEqual(resolution.manifest.resolutionSource, .defaultScenario)
        XCTAssertEqual(resolution.manifest.schemaVersion, 3)
    }

    func testNamedScenarioResolvesCommandLineMetadata() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: [
                "probe",
                "--probe-scenario", "swiftui.stack.return",
                "--probe-run-id", "named-run",
                "--probe-run-mode", "clean"
            ],
            environment: [:]
        )

        XCTAssertTrue(resolution.isValid)
        XCTAssertEqual(resolution.scenario?.identifier, "swiftui.stack.return")
        XCTAssertEqual(resolution.manifest.runID, "named-run")
        XCTAssertEqual(resolution.manifest.runMode, .clean)
        XCTAssertEqual(resolution.manifest.resolutionSource, .commandLine)
    }

    func testKnownLegacyProfileMapsToNamedScenario() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe"],
            environment: [
                "DD_MULTI_SCENE_RUN_ID": "legacy-run",
                "DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING": "navigation-occurrence",
                "DD_MULTI_SCENE_SWIFTUI_LAYOUT": "split-selection",
                "DD_MULTI_SCENE_SPLIT_RETURN_TO_DETAIL": "1"
            ]
        )

        XCTAssertTrue(resolution.isValid)
        XCTAssertEqual(resolution.scenario?.identifier, "swiftui.split.retained-return")
        XCTAssertEqual(resolution.manifest.resolutionSource, .legacyEnvironment)
    }

    func testUnknownScenarioIsRejected() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe", "--probe-scenario", "does.not.exist"],
            environment: [:]
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertNil(resolution.scenario)
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("unknown probe scenario")
            }
        )
    }

    func testUnknownProbeEnvironmentKeyIsRejected() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe"],
            environment: ["DD_MULTI_SCENE_UNKNOWN": "1"]
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("unknown multi-scene probe environment key")
            }
        )
    }

    func testNamedScenarioCannotMixWithLegacyConfiguration() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe", "--probe-scenario", "swiftui.stack.return"],
            environment: ["DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL": "1"]
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("cannot be mixed with legacy configuration")
            }
        )
    }

    func testContradictoryLegacyReplacementIsRejected() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe"],
            environment: [
                "DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL": "1",
                "DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL": "1",
                "DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL_INSTANCE": "1"
            ]
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("cannot both be enabled")
            }
        )
    }

    func testInvalidBooleanDoesNotSilentlyUseItsDefault() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe"],
            environment: ["DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL": "yes"]
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("expected 0 or 1")
            }
        )
    }

    func testDuplicateAndMissingArgumentsAreRejected() {
        let duplicate = ProbeScenarioRunner.resolve(
            arguments: [
                "probe",
                "--probe-scenario", "swiftui.stack.return",
                "--probe-scenario", "swiftui.stack.abort"
            ],
            environment: [:]
        )
        let missing = ProbeScenarioRunner.resolve(
            arguments: ["probe", "--probe-run-id"],
            environment: [:]
        )

        XCTAssertFalse(duplicate.isValid)
        XCTAssertFalse(missing.isValid)
        XCTAssertTrue(
            duplicate.manifest.validationErrors.contains {
                $0.contains("provided more than once")
            }
        )
        XCTAssertTrue(
            missing.manifest.validationErrors.contains {
                $0.contains("missing value")
            }
        )
    }

    func testRunIDConflictAndWhitespaceAreRejected() {
        let conflict = ProbeScenarioRunner.resolve(
            arguments: ["probe", "--probe-run-id", "argument-run"],
            environment: ["DD_MULTI_SCENE_RUN_ID": "environment-run"]
        )
        let whitespace = ProbeScenarioRunner.resolve(
            arguments: ["probe", "--probe-run-id", "invalid run"],
            environment: [:]
        )

        XCTAssertFalse(conflict.isValid)
        XCTAssertFalse(whitespace.isValid)
        XCTAssertTrue(
            conflict.manifest.validationErrors.contains {
                $0.contains("conflicts")
            }
        )
        XCTAssertTrue(
            whitespace.manifest.validationErrors.contains {
                $0.contains("contain no whitespace")
            }
        )
    }

    func testEmptyEnvironmentRunIDIsRejectedInsteadOfRegenerated() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: ["probe"],
            environment: ["DD_MULTI_SCENE_RUN_ID": "   "],
            generatedRunID: { "must-not-hide-invalid-input" }
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("DD_MULTI_SCENE_RUN_ID cannot be empty")
            }
        )
    }

    func testArgumentFollowedByAnotherFlagReportsMissingValue() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: [
                "probe",
                "--probe-scenario",
                "--probe-run-id", "still-parsed"
            ],
            environment: [:]
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertEqual(resolution.manifest.runID, "still-parsed")
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("missing value after --probe-scenario")
            }
        )
    }

    func testRestorationScenarioRejectsCleanOverride() {
        let resolution = ProbeScenarioRunner.resolve(
            arguments: [
                "probe",
                "--probe-scenario", "windows.restoration",
                "--probe-run-mode", "clean"
            ],
            environment: [:]
        )

        XCTAssertFalse(resolution.isValid)
        XCTAssertTrue(
            resolution.manifest.validationErrors.contains {
                $0.contains("requires restoration run mode")
            }
        )
    }
}
