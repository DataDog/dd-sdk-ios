/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The simulator and reference directory used by one layer snapshot environment.
internal struct LayerSnapshotEnvironment: Decodable {
    let name: String
    let simulator: SnapshotSimulator

    var snapshotsFolderPath: String { "_snapshots_/\(name)/png" }

    /// Creates a validated environment for the running simulator.
    init(osVersion: String, modelIdentifier: String?) throws {
        let url = Bundle(for: LayerSnapshotTestCase.self)
            .url(forResource: "SnapshotEnvironments", withExtension: "json")

        guard let url else {
            throw ConfigurationError("Missing SnapshotEnvironments.json in the layer snapshot test bundle.")
        }

        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        let environment: Self

        if let name = ProcessInfo.processInfo.environment["SNAPSHOT_ENV"], !name.isEmpty {
            guard let selected = configuration.environments.first(where: { $0.name == name }) else {
                throw ConfigurationError("Unsupported layer snapshot environment: '\(name)'.")
            }
            try selected.validate(osVersion: osVersion, modelIdentifier: modelIdentifier)
            environment = selected
        } else {
            guard let modelIdentifier else {
                throw ConfigurationError("Layer snapshots require an iOS simulator.")
            }

            let matches = configuration.environments.filter {
                $0.simulator.osVersion == osVersion && $0.simulator.modelIdentifier == modelIdentifier
            }

            guard let match = matches.first else {
                throw ConfigurationError(
                    "No layer snapshot environment matches iOS \(osVersion) on \(modelIdentifier). "
                    + "See SnapshotEnvironments.json for supported simulators."
                )
            }

            guard matches.count == 1 else {
                throw ConfigurationError(
                    "Multiple layer snapshot environments match iOS \(osVersion) on \(modelIdentifier). "
                    + "Set SNAPSHOT_ENV to choose one."
                )
            }
            environment = match
        }

        self = environment
    }

    /// Stops a mismatched simulator from comparing or overwriting this environment's references.
    private func validate(osVersion: String, modelIdentifier: String?) throws {
        guard let modelIdentifier, modelIdentifier == simulator.modelIdentifier else {
            throw ConfigurationError(
                "Snapshot environment '\(name)' requires \(simulator.name) (\(simulator.modelIdentifier ?? "unknown")); "
                + "running on \(modelIdentifier ?? "a non-simulator device")."
            )
        }

        guard osVersion == simulator.osVersion else {
            throw ConfigurationError(
                "Snapshot environment '\(name)' requires iOS \(simulator.osVersion); running on iOS \(osVersion)."
            )
        }
    }

    private struct Configuration: Decodable {
        let environments: [LayerSnapshotEnvironment]
    }

    private struct ConfigurationError: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
