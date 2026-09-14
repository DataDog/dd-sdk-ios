/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

final class ProbeScenarioRunnerTests: XCTestCase {
    func testCatalogHasUniqueIdentifiersAndRequiredScenarios() {
        let identifiers = ProbeScenarioCatalog.all.map(\.identifier)

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(
            Set([
                "swiftui.stack.return",
                "operations.navigation.lifecycle",
                "operations.cross-scene.lifecycle",
                "swiftui.stack.abort",
                "swiftui.stack.same-type-replacement",
                "swiftui.coexistence.semantic-a-automatic-b",
                "swiftui.coexistence.automatic-manual-sheet",
                "swiftui.coexistence.automatic-scene-targeted-sheet",
                "swiftui.coexistence.automatic-scene-targeted-full-screen-cover",
                "swiftui.coexistence.automatic-keyed-manual-view",
                "swiftui.coexistence.nested-keyed-manual-view",
                "swiftui.coexistence.same-key-manual-two-scenes",
                "swiftui.coexistence.sibling-container-authority",
                "swiftui.split.same-type-selection",
                "uikit.split.pop-cancel",
                "uikit.split.pop-finish",
                "windows.parallel-navigation",
                "windows.close-with-resource",
                "actions.exact-source-handoff",
                "regression.single-scene"
            ]).isSubset(of: Set(identifiers))
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

        XCTAssertEqual(scenario.trackingMode, .navigationOccurrence)
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
        XCTAssertEqual(resolution.manifest.schemaVersion, 2)
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
