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
                "swiftui.stack.abort",
                "swiftui.stack.same-type-replacement",
                "swiftui.coexistence.semantic-a-automatic-b",
                "swiftui.coexistence.automatic-manual-sheet",
                "swiftui.coexistence.automatic-keyed-manual-view",
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
                    && $0.interval == "keyed-manual-authority"
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
