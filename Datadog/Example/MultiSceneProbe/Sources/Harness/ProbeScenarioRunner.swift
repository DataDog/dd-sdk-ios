/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

enum ProbeScenarioRunner {
    private struct ManifestRecord: Codable {
        let type = "manifest"
        let manifest: ProbeScenarioManifest
    }

    private struct ParsedArguments {
        var scenarioIdentifier: String?
        var runID: String?
        var runMode: ProbeRunMode?
        var errors: [String] = []
    }

    private static let runIDEnvironmentKey = "DD_MULTI_SCENE_RUN_ID"
    private static let legacyConfigurationKeys: Set<String> = [
        "DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING",
        "DD_MULTI_SCENE_SWIFTUI_STRESS",
        "DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL",
        "DD_MULTI_SCENE_AUTORUN_OPEN_SECOND_WINDOW",
        "DD_MULTI_SCENE_AUTORUN_CLOSE_SCENE_B",
        "DD_MULTI_SCENE_AUTORUN_ABORT_DETAIL",
        "DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL",
        "DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL_INSTANCE",
        "DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY",
        "DD_MULTI_SCENE_SYNTHETIC_READER_DISCONNECT",
        "DD_MULTI_SCENE_SWIFTUI_LAYOUT",
        "DD_MULTI_SCENE_UIKIT_SPLIT_AUTOMATIC_POP",
        "DD_MULTI_SCENE_UIKIT_SPLIT_INTERACTIVE_POP",
        "DD_MULTI_SCENE_SPLIT_INITIAL_SELECTION",
        "DD_MULTI_SCENE_SPLIT_AUTOMATIC_SEQUENCE",
        "DD_MULTI_SCENE_SPLIT_RETURN_TO_DETAIL",
        "DD_MULTI_SCENE_UI_EVENT_HANDOFF"
    ]
    private static let knownEnvironmentKeys = legacyConfigurationKeys.union([runIDEnvironmentKey])

    static func resolve(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        generatedRunID: () -> String = { UUID().uuidString.lowercased() }
    ) -> ProbeScenarioResolution {
        let parsedArguments = parse(arguments: arguments)
        var errors = parsedArguments.errors
        errors.append(contentsOf: unknownEnvironmentErrors(environment))

        let environmentRunID = normalized(environment[runIDEnvironmentKey])
        if environment[runIDEnvironmentKey] != nil && environmentRunID == nil {
            errors.append("\(runIDEnvironmentKey) cannot be empty")
        }
        if
            let argumentRunID = parsedArguments.runID,
            let environmentRunID,
            argumentRunID != environmentRunID {
            errors.append(
                "--probe-run-id conflicts with \(runIDEnvironmentKey); provide only one value"
            )
        }
        let runID = parsedArguments.runID ?? environmentRunID ?? generatedRunID()
        if runID.isEmpty || runID.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            errors.append("probe run ID must be non-empty and contain no whitespace")
        }
        if runID.utf8.count > 128 {
            errors.append("probe run ID must be at most 128 UTF-8 bytes")
        }

        let source: ProbeScenarioResolutionSource
        let scenario: ProbeScenario?
        if let identifier = parsedArguments.scenarioIdentifier {
            source = .commandLine
            let mixedKeys = legacyConfigurationKeys.filter {
                environment[$0] != nil
            }.sorted()
            if !mixedKeys.isEmpty {
                errors.append(
                    "named scenarios cannot be mixed with legacy configuration keys: "
                        + mixedKeys.joined(separator: ",")
                )
            }
            scenario = ProbeScenarioCatalog.scenario(identifier: identifier)
            if scenario == nil {
                errors.append(
                    "unknown probe scenario '\(identifier)'; available scenarios: "
                        + ProbeScenarioCatalog.all.map(\.identifier).sorted().joined(separator: ",")
                )
            }
        } else if hasLegacyConfiguration(environment) {
            source = .legacyEnvironment
            let legacy = resolveLegacyScenario(environment: environment)
            scenario = legacy.scenario
            errors.append(contentsOf: legacy.errors)
        } else {
            source = .defaultScenario
            scenario = ProbeScenarioCatalog.scenario(
                identifier: ProbeScenarioCatalog.defaultIdentifier
            )
        }

        let runMode = parsedArguments.runMode ?? scenario?.defaultRunMode ?? .clean
        if let scenario {
            errors.append(contentsOf: validate(scenario, runMode: runMode))
        }

        return ProbeScenarioResolution(
            manifest: ProbeScenarioManifest(
                runID: runID,
                runMode: runMode,
                resolutionSource: source,
                scenario: scenario,
                validationErrors: errors
            )
        )
    }

    static func emitManifest(_ manifest: ProbeScenarioManifest) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard
            let data = try? encoder.encode(ManifestRecord(manifest: manifest)),
            let json = String(data: data, encoding: .utf8)
        else {
            print(
                "🔬 [RUM Native Multi-Scene JSONL] "
                    + #"{"type":"manifest-encoding-failed"}"#
            )
            return
        }
        print("🔬 [RUM Native Multi-Scene JSONL] \(json)")
    }

    private static func parse(arguments: [String]) -> ParsedArguments {
        var parsed = ParsedArguments()
        var index = arguments.isEmpty ? 0 : 1

        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--probe-") else {
                index += 1
                continue
            }
            guard
                index + 1 < arguments.count,
                !arguments[index + 1].hasPrefix("--probe-")
            else {
                parsed.errors.append("missing value after \(argument)")
                index += 1
                continue
            }
            let value = arguments[index + 1]
            switch argument {
            case "--probe-scenario":
                assignOnce(
                    value,
                    label: argument,
                    destination: &parsed.scenarioIdentifier,
                    errors: &parsed.errors
                )
            case "--probe-run-id":
                assignOnce(
                    value,
                    label: argument,
                    destination: &parsed.runID,
                    errors: &parsed.errors
                )
            case "--probe-run-mode":
                if parsed.runMode != nil {
                    parsed.errors.append("\(argument) was provided more than once")
                } else if let runMode = ProbeRunMode(rawValue: value) {
                    parsed.runMode = runMode
                } else {
                    parsed.errors.append(
                        "invalid \(argument) '\(value)'; expected clean or restoration"
                    )
                }
            default:
                parsed.errors.append("unknown probe argument \(argument)")
            }
            index += 2
        }
        return parsed
    }

    private static func assignOnce(
        _ value: String,
        label: String,
        destination: inout String?,
        errors: inout [String]
    ) {
        if destination != nil {
            errors.append("\(label) was provided more than once")
        } else if value.isEmpty {
            errors.append("\(label) cannot be empty")
        } else {
            destination = value
        }
    }

    private static func hasLegacyConfiguration(_ environment: [String: String]) -> Bool {
        legacyConfigurationKeys.contains { environment[$0] != nil }
    }

    private static func unknownEnvironmentErrors(
        _ environment: [String: String]
    ) -> [String] {
        environment.keys
            .filter {
                $0.hasPrefix("DD_MULTI_SCENE_")
                    && !knownEnvironmentKeys.contains($0)
            }
            .sorted()
            .map { "unknown multi-scene probe environment key \($0)" }
    }

    private static func resolveLegacyScenario(
        environment: [String: String]
    ) -> (scenario: ProbeScenario?, errors: [String]) {
        var errors: [String] = []
        let trackingMode = parseEnum(
            environment["DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING"],
            key: "DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING",
            defaultValue: ProbeTrackingMode.automatic,
            errors: &errors
        )
        let layout = parseEnum(
            environment["DD_MULTI_SCENE_SWIFTUI_LAYOUT"],
            key: "DD_MULTI_SCENE_SWIFTUI_LAYOUT",
            defaultValue: ProbeLayout.stack,
            errors: &errors
        )
        let stress = parseEnum(
            environment["DD_MULTI_SCENE_SWIFTUI_STRESS"],
            key: "DD_MULTI_SCENE_SWIFTUI_STRESS",
            defaultValue: ProbeSwiftUIStress.none,
            errors: &errors
        )
        let interactiveOutcome: ProbeTransitionOutcome? = parseOptionalEnum(
            environment["DD_MULTI_SCENE_UIKIT_SPLIT_INTERACTIVE_POP"],
            key: "DD_MULTI_SCENE_UIKIT_SPLIT_INTERACTIVE_POP",
            nilValue: "none",
            errors: &errors
        )
        let syntheticTarget = parseOptionalString(
            environment["DD_MULTI_SCENE_SYNTHETIC_READER_DISCONNECT"],
            key: "DD_MULTI_SCENE_SYNTHETIC_READER_DISCONNECT",
            nilValue: "none",
            allowedValues: ["scene-A", "scene-B"],
            errors: &errors
        )
        let startsWithoutSelection = parseChoice(
            environment["DD_MULTI_SCENE_SPLIT_INITIAL_SELECTION"],
            key: "DD_MULTI_SCENE_SPLIT_INITIAL_SELECTION",
            falseValue: "detail-1",
            trueValue: "none",
            defaultValue: false,
            errors: &errors
        )

        var options = ProbeRuntimeOptions()
        options.automaticallyNavigates = parseBoolean(
            environment["DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL"],
            key: "DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL",
            defaultValue: false,
            errors: &errors
        )
        options.automaticallyOpensSecondWindow = parseBoolean(
            environment["DD_MULTI_SCENE_AUTORUN_OPEN_SECOND_WINDOW"],
            key: "DD_MULTI_SCENE_AUTORUN_OPEN_SECOND_WINDOW",
            defaultValue: false,
            errors: &errors
        )
        options.automaticallyClosesSceneB = parseBoolean(
            environment["DD_MULTI_SCENE_AUTORUN_CLOSE_SCENE_B"],
            key: "DD_MULTI_SCENE_AUTORUN_CLOSE_SCENE_B",
            defaultValue: false,
            errors: &errors
        )
        options.automaticallyAbortsDetail = parseBoolean(
            environment["DD_MULTI_SCENE_AUTORUN_ABORT_DETAIL"],
            key: "DD_MULTI_SCENE_AUTORUN_ABORT_DETAIL",
            defaultValue: false,
            errors: &errors
        )
        options.automaticallyReplacesDetail = parseBoolean(
            environment["DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL"],
            key: "DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL",
            defaultValue: false,
            errors: &errors
        )
        options.automaticallyReplacesDetailInstance = parseBoolean(
            environment["DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL_INSTANCE"],
            key: "DD_MULTI_SCENE_AUTORUN_REPLACE_DETAIL_INSTANCE",
            defaultValue: false,
            errors: &errors
        )
        options.forcesNavigationRouteIdentity = parseBoolean(
            environment["DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY"],
            key: "DD_MULTI_SCENE_FORCE_ROUTE_IDENTITY",
            defaultValue: false,
            errors: &errors
        )
        options.syntheticReaderDisconnectTarget = syntheticTarget
        options.automaticallyPopsUIKitSplitNavigation = parseBoolean(
            environment["DD_MULTI_SCENE_UIKIT_SPLIT_AUTOMATIC_POP"],
            key: "DD_MULTI_SCENE_UIKIT_SPLIT_AUTOMATIC_POP",
            defaultValue: true,
            errors: &errors
        )
        options.uiKitSplitInteractivePopOutcome = interactiveOutcome
        options.startsSplitWithoutSelection = startsWithoutSelection
        options.automaticallyAdvancesSplitSelection = parseBoolean(
            environment["DD_MULTI_SCENE_SPLIT_AUTOMATIC_SEQUENCE"],
            key: "DD_MULTI_SCENE_SPLIT_AUTOMATIC_SEQUENCE",
            defaultValue: true,
            errors: &errors
        )
        options.automaticallyReturnsSplitToDetail = parseBoolean(
            environment["DD_MULTI_SCENE_SPLIT_RETURN_TO_DETAIL"],
            key: "DD_MULTI_SCENE_SPLIT_RETURN_TO_DETAIL",
            defaultValue: false,
            errors: &errors
        )
        options.exercisesUIEventContextHandoff = parseBoolean(
            environment["DD_MULTI_SCENE_UI_EVENT_HANDOFF"],
            key: "DD_MULTI_SCENE_UI_EVENT_HANDOFF",
            defaultValue: false,
            errors: &errors
        )
        options.swiftUIStress = stress

        validateLegacyCombination(
            options: options,
            layout: layout,
            trackingMode: trackingMode,
            environment: environment,
            errors: &errors
        )

        guard errors.isEmpty else {
            return (nil, errors)
        }
        guard let scenario = ProbeScenarioCatalog.scenario(
            matching: options,
            layout: layout,
            trackingMode: trackingMode
        ) else {
            return (
                nil,
                [
                    "legacy environment combination has no named scenario; "
                        + "add it to ProbeScenarioCatalog before running"
                ]
            )
        }
        return (scenario, [])
    }

    private static func validateLegacyCombination(
        options: ProbeRuntimeOptions,
        layout: ProbeLayout,
        trackingMode: ProbeTrackingMode,
        environment: [String: String],
        errors: inout [String]
    ) {
        if options.automaticallyReplacesDetail && options.automaticallyReplacesDetailInstance {
            errors.append("alternate and same-type Detail replacement cannot both be enabled")
        }
        if
            (options.automaticallyReplacesDetail || options.automaticallyReplacesDetailInstance)
                && !options.automaticallyNavigates {
            errors.append("Detail replacement requires automatic Detail navigation")
        }
        if options.automaticallyAbortsDetail && options.automaticallyNavigates {
            errors.append("same-turn Detail abort cannot be combined with automatic Detail navigation")
        }
        if layout != .stack {
            if
                options.automaticallyNavigates
                    || options.automaticallyAbortsDetail
                    || options.automaticallyReplacesDetail
                    || options.automaticallyReplacesDetailInstance {
                errors.append("stack navigation controls cannot be enabled for a split layout")
            }
            if options.swiftUIStress != .none {
                errors.append("SwiftUI stress containers are supported only by the stack layout")
            }
        }
        if layout != .splitSelection {
            if options.startsSplitWithoutSelection {
                errors.append("empty split selection requires the split-selection layout")
            }
            if !options.automaticallyAdvancesSplitSelection {
                errors.append("disabling the split sequence requires the split-selection layout")
            }
            if options.automaticallyReturnsSplitToDetail {
                errors.append("split return requires the split-selection layout")
            }
        } else if options.startsSplitWithoutSelection && options.automaticallyAdvancesSplitSelection {
            errors.append("empty initial split selection requires the automatic sequence to be disabled")
        }
        if layout != .uikitSplitNavigation {
            if !options.automaticallyPopsUIKitSplitNavigation {
                errors.append("UIKit automatic-pop control requires the UIKit split-navigation layout")
            }
            if options.uiKitSplitInteractivePopOutcome != nil {
                errors.append("UIKit interactive-pop control requires the UIKit split-navigation layout")
            }
        } else if
            options.uiKitSplitInteractivePopOutcome != nil
                && options.automaticallyPopsUIKitSplitNavigation {
            errors.append("deterministic UIKit interactive pop requires automatic pop to be disabled")
        }
        if
            options.exercisesUIEventContextHandoff,
            layout != .uikitSplit,
            layout != .uikitSplitSubclass {
            errors.append("UI-event handoff control requires a UIKit split layout")
        }
        if options.exercisesSwiftUIButtonStructuredTask {
            if layout != .stack {
                errors.append("SwiftUI Button structured Task requires the stack layout")
            }
            if trackingMode != .navigationOccurrence {
                errors.append(
                    "SwiftUI Button structured Task requires navigation-occurrence tracking"
                )
            }
        }
        if options.forcesNavigationRouteIdentity {
            if trackingMode == .automatic || trackingMode == .manual {
                errors.append("forced route identity requires navigation-path tracking")
            }
            if trackingMode == .navigationOccurrence {
                errors.append("forced route identity conflicts with navigation-occurrence tracking")
            }
        }
        if
            options.syntheticReaderDisconnectTarget != nil,
            layout != .stack {
            errors.append("synthetic reader disconnect is supported only by the stack layout")
        }

        let neutralSplitKeys = [
            "DD_MULTI_SCENE_SPLIT_INITIAL_SELECTION": "detail-1",
            "DD_MULTI_SCENE_SPLIT_AUTOMATIC_SEQUENCE": "1",
            "DD_MULTI_SCENE_SPLIT_RETURN_TO_DETAIL": "0"
        ]
        if layout != .splitSelection {
            for (key, neutralValue) in neutralSplitKeys {
                if let value = environment[key], value != neutralValue {
                    errors.append("\(key)=\(value) is not neutral for layout \(layout.rawValue)")
                }
            }
        }
    }

    private static func validate(
        _ scenario: ProbeScenario,
        runMode: ProbeRunMode
    ) -> [String] {
        var errors: [String] = []
        if scenario.identifier.isEmpty {
            errors.append("scenario identifier cannot be empty")
        }
        if scenario.initialWindows.isEmpty {
            errors.append("scenario must define at least one initial window")
        }
        if Set(scenario.initialWindows).count != scenario.initialWindows.count {
            errors.append("scenario initial window labels must be unique")
        }
        if Set(scenario.requiredCapabilities).count != scenario.requiredCapabilities.count {
            errors.append("scenario required capabilities must be unique")
        }
        if
            scenario.requiredCapabilities.contains(.restoration),
            runMode != .restoration {
            errors.append("scenario \(scenario.identifier) requires restoration run mode")
        }
        if
            scenario.runtimeOptions.automaticallyReplacesDetail,
            scenario.runtimeOptions.automaticallyReplacesDetailInstance {
            errors.append("scenario cannot enable both Detail replacement modes")
        }
        if
            scenario.trackingMode == .navigationOccurrence,
            scenario.runtimeOptions.forcesNavigationRouteIdentity {
            errors.append("navigation-occurrence scenarios cannot force customer route identity")
        }
        if !scenario.runtimeOptions.initialSwiftUIPath.isEmpty {
            if scenario.layout != .stack {
                errors.append("initial SwiftUI path requires the stack layout")
            }
            if !ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario) {
                errors.append("initial SwiftUI path requires the semantic navigation API")
            }
            let supportedInitialRoutes = Set(["detail-1", "detail-2", "alternate"])
            let unsupportedInitialRoutes = Set(scenario.runtimeOptions.initialSwiftUIPath)
                .subtracting(supportedInitialRoutes)
                .sorted()
            if !unsupportedInitialRoutes.isEmpty {
                errors.append(
                    "unsupported initial SwiftUI routes: "
                        + unsupportedInitialRoutes.joined(separator: ",")
                )
            }
        }
        if scenario.runtimeOptions.swiftUIRouterWritePolicy != .accept {
            if !ProbeScenarioCatalog.usesSemanticNavigationSPI(scenario) {
                errors.append("router write policy requires the semantic navigation API")
            }
            if !ProbeScenarioCatalog.usesSemanticNavigationValueLinks(scenario) {
                errors.append("router write policy requires a native semantic value link")
            }
            if scenario.steps.contains(where: {
                $0.kind == .setSwiftUIPath || $0.kind == .replaceSwiftUIDestination
            }) {
                errors.append(
                    "router write policy cannot be combined with driver path mutation"
                )
            }
        }
        for step in scenario.steps {
            if
                let percentage = step.percentage,
                !(0...1).contains(percentage) {
                errors.append(
                    "scenario \(scenario.identifier) has transition percentage outside 0...1"
                )
            }
            switch step.kind {
            case .openWindow:
                guard
                    let sourceScene = normalized(step.scene),
                    let targetScene = normalized(step.value)
                else {
                    errors.append(
                        "scenario \(scenario.identifier) open-window requires source and target scenes"
                    )
                    continue
                }
                if sourceScene == targetScene {
                    errors.append(
                        "scenario \(scenario.identifier) open-window source and target must differ"
                    )
                }
                for scene in [sourceScene, targetScene]
                where !scenario.initialWindows.contains(scene) {
                    errors.append(
                        "scenario \(scenario.identifier) open-window uses undeclared scene \(scene)"
                    )
                }
            case .activateWindow,
                 .closeWindow,
                 .releaseSwiftUIButtonStructuredTask,
                 .bounceSemanticNavigationHostReader:
                guard let scene = normalized(step.scene) else {
                    errors.append(
                        "scenario \(scenario.identifier) \(step.kind.rawValue) requires a scene"
                    )
                    continue
                }
                if !scenario.initialWindows.contains(scene) {
                    errors.append(
                        "scenario \(scenario.identifier) \(step.kind.rawValue) uses undeclared scene \(scene)"
                    )
                }
            case .removeSemanticNavigationHost:
                guard
                    let scene = normalized(step.scene),
                    let occurrence = normalized(step.value),
                    occurrence.split(separator: "#", maxSplits: 1).count == 2,
                    Int(occurrence.split(separator: "#", maxSplits: 1)[1]) != nil
                else {
                    errors.append(
                        "scenario \(scenario.identifier) remove-semantic-navigation-host "
                            + "requires a scene and screen#occurrence value"
                    )
                    continue
                }
                if !scenario.initialWindows.contains(scene) {
                    errors.append(
                        "scenario \(scenario.identifier) remove-semantic-navigation-host "
                            + "uses undeclared scene \(scene)"
                    )
                }
            case .startOperation, .succeedOperation, .failOperation:
                guard
                    let scene = normalized(step.scene),
                    normalized(step.value) != nil
                else {
                    errors.append(
                        "scenario \(scenario.identifier) \(step.kind.rawValue) "
                            + "requires a scene and operation instance"
                    )
                    continue
                }
                if !scenario.initialWindows.contains(scene) {
                    errors.append(
                        "scenario \(scenario.identifier) \(step.kind.rawValue) "
                            + "uses undeclared scene \(scene)"
                    )
                }
            case .waitForSignal where step.signal?.hasPrefix("scene-state:") == true:
                guard let scene = normalized(step.scene) else {
                    errors.append(
                        "scenario \(scenario.identifier) scene-state wait requires a scene"
                    )
                    continue
                }
                if !scenario.initialWindows.contains(scene) {
                    errors.append(
                        "scenario \(scenario.identifier) scene-state wait uses undeclared scene \(scene)"
                    )
                }
                let rawState = step.signal.map {
                    String($0.dropFirst("scene-state:".count))
                }
                if rawState.flatMap(ProbeSceneActivationState.init(rawValue:)) == nil {
                    let allowed = ProbeSceneActivationState.allCases
                        .map(\.rawValue)
                        .sorted()
                        .joined(separator: ",")
                    errors.append(
                        "scenario \(scenario.identifier) has invalid scene state; expected one of \(allowed)"
                    )
                }
            default:
                break
            }
        }
        for expectation in scenario.completionConditions + scenario.expectedSemanticTimeline {
            if let occurrence = expectation.occurrence, occurrence < 1 {
                errors.append("scenario view occurrence must be greater than zero")
            }
            if
                (expectation.ownerViewReferenceAction == nil)
                    != (expectation.ownerViewRelation == nil) {
                errors.append(
                    "scenario owner-view relation requires both a reference action and relation"
                )
            }
            if
                expectation.ownerViewStartedAfterStep == nil,
                expectation.ownerViewStartedAfterStepValue != nil {
                errors.append(
                    "scenario owner-view step value requires a step kind"
                )
            }
        }
        return errors
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func parseBoolean(
        _ value: String?,
        key: String,
        defaultValue: Bool,
        errors: inout [String]
    ) -> Bool {
        guard let value else {
            return defaultValue
        }
        switch value {
        case "0":
            return false
        case "1":
            return true
        default:
            errors.append("invalid \(key)=\(value); expected 0 or 1")
            return defaultValue
        }
    }

    private static func parseChoice(
        _ value: String?,
        key: String,
        falseValue: String,
        trueValue: String,
        defaultValue: Bool,
        errors: inout [String]
    ) -> Bool {
        guard let value else {
            return defaultValue
        }
        switch value {
        case falseValue:
            return false
        case trueValue:
            return true
        default:
            errors.append(
                "invalid \(key)=\(value); expected \(falseValue) or \(trueValue)"
            )
            return defaultValue
        }
    }

    private static func parseOptionalString(
        _ value: String?,
        key: String,
        nilValue: String,
        allowedValues: Set<String>,
        errors: inout [String]
    ) -> String? {
        guard let value, value != nilValue else {
            return nil
        }
        guard allowedValues.contains(value) else {
            errors.append(
                "invalid \(key)=\(value); expected "
                    + "\(([nilValue] + Array(allowedValues)).sorted().joined(separator: ","))"
            )
            return nil
        }
        return value
    }

    private static func parseEnum<T: RawRepresentable & CaseIterable>(
        _ value: String?,
        key: String,
        defaultValue: T,
        errors: inout [String]
    ) -> T where T.RawValue == String {
        guard let value else {
            return defaultValue
        }
        guard let parsed = T(rawValue: value) else {
            let allowed = T.allCases.map(\.rawValue).sorted().joined(separator: ",")
            errors.append("invalid \(key)=\(value); expected one of \(allowed)")
            return defaultValue
        }
        return parsed
    }

    private static func parseOptionalEnum<T: RawRepresentable & CaseIterable>(
        _ value: String?,
        key: String,
        nilValue: String,
        errors: inout [String]
    ) -> T? where T.RawValue == String {
        guard let value, value != nilValue else {
            return nil
        }
        guard let parsed = T(rawValue: value) else {
            let allowed = ([nilValue] + T.allCases.map(\.rawValue))
                .sorted()
                .joined(separator: ",")
            errors.append("invalid \(key)=\(value); expected one of \(allowed)")
            return nil
        }
        return parsed
    }
}
