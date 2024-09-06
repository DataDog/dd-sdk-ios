/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct ConfigurationFile: Decodable {
    let clientToken: String
    let env: String
    let site: DatadogSite
    let configURL: URL?
    let backgroundUpload: Bool?
    let uploadFrequency: Datadog.Configuration.UploadFrequency?
    let batchProcessingLevel: Datadog.Configuration.BatchProcessingLevel?
    let properties: [String: Any]

    init?(from bundle: Bundle = .main) throws {
        guard let file = bundle.url(forResource: "datadog-config", withExtension: "json") else {
            return nil
        }

        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        self = try decoder.decode(ConfigurationFile.self, from: data)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        clientToken = try container.decode(String.self, forKey: .init("client_token"))
        env = try container.decode(String.self, forKey: .init("env"))
        site = try container.decode(DatadogSite.self, forKey: .init("site"))
        configURL = try container.decodeIfPresent(URL.self, forKey: .init("remote_config"))
        backgroundUpload = try container.decodeIfPresent(Bool.self, forKey: .init("background_upload"))
        uploadFrequency = try container.decodeIfPresent(Datadog.Configuration.UploadFrequency.self, forKey: .init("upload_frequency"))
        batchProcessingLevel = try container.decodeIfPresent(Datadog.Configuration.BatchProcessingLevel.self, forKey: .init("batch_processing_level"))
        properties = try container.allKeys.reduce(into: [:]) { properties, key in
            properties[key.stringValue] = try container.decode(AnyDecodable.self, forKey: key).value
        }
    }
}

internal final class RemoteConfiguration: Configuration {
    @ReadWriteLock
    var properties: [String: Any]

    /// A weak core reference.
    ///
    /// The core **must** be accessed within the queue.
    private weak var core: DatadogCoreProtocol?

    init(
        directory: URL,
        endpoint: URL?,
        properties: [String: Any]
    ) throws {
        self.properties = properties

        let file = directory.appendingPathComponent("datadog-config.json", isDirectory: false)
        let decoder = JSONDecoder()

        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                let local = try decoder.decode(AnyDecodable.self, from: data)
                if let local = local.value as? [String: Any] {
                    self.properties = config_merge(properties, local)
                }
            }
        } catch { print(error) }

        guard let endpoint else {
            return
        }

        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: endpoint) { [weak self] data, _, _ in
            guard  let self, let data else {
                return
            }

            try? data.write(to: file, options: .atomic)

            let remote = try? decoder.decode(AnyDecodable.self, from: data)
            guard let remote = remote?.value as? [String: Any] else {
                return
            }
            self._properties.mutate { local in
                local = config_merge(local, remote)
            }

            self.core?.send(message: .configuration(self))
        }.resume()
    }

    /// Connects the core to the bus.
    ///
    /// The message-bus keeps a weak reference to the core.
    ///
    /// - Parameter core: The core ference.
    func connect(core: DatadogCoreProtocol) {
        self.core = core
    }

    /// Return a Configuration object of type T.
    ///
    /// - Parameters:
    ///   - type: The configuration type.
    ///   - key: The configuration key.
    /// - Returns: The configuration object if available.
    func property<T>(_ type: T.Type, forKey key: String) -> T? where T: Decodable {
        let decoder = AnyDecoder()
        return try? decoder.decode(type, from: properties[key])
    }
}

private func config_merge(_ local: [String: Any], _ remote: [String: Any] ) -> [String: Any] {
    var result = local
    for rk in remote.keys {
        if !local.keys.contains(rk) {
            result[rk] = remote[rk]
            continue
        }

        let rv = remote[rk]
        let lv = local[rk]

        switch (lv, rv) {
        case let (ld, rd) as ([String: Any], [String: Any]):
            result[rk] = config_merge(ld, rd)
        default:
            result[rk] = rv
        }
    }

    return result
}
