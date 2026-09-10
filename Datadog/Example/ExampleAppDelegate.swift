/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
import DatadogCore
import DatadogFlags
import DatadogLogs
import DatadogTrace
import DatadogRUM
import DatadogCrashReporting
import OpenTelemetryApi

let serviceName = "ios-sdk-example-app"

var logger: LoggerProtocol!
var tracer: OTTracer { Tracer.shared() }
var rumMonitor: RUMMonitorProtocol { RUMMonitor.shared() }
var otelTracer: OpenTelemetryApi.Tracer {
    OpenTelemetry
        .instance
        .tracerProvider
        .get(instrumentationName: "", instrumentationVersion: nil)
}

final class DummySessionDataDelegate: NSObject, URLSessionDataDelegate {}

@main
class ExampleAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if Environment.isRunningUnitTests() {
            return false
        }

        // Initialize Datadog SDK
        let siteName = Bundle.main.infoDictionary?["DatadogSite"] as? String ?? "us1"
        let site = DatadogSite(rawValue: siteName) ?? .us1
        Datadog.initialize(
            with: Datadog.Configuration(
                clientToken: Environment.readClientToken(),
                env: "tests",
                site: site,
                service: serviceName,
                batchSize: .small,
                uploadFrequency: .frequent
            ),
            trackingConsent: .granted
        )

        // Set user information
        Datadog.setUserInfo(id: "abcd-1234", name: "foo", email: "foo@example.com", extraInfo: ["key-extraUserInfo": "value-extraUserInfo"])

        // Set account information
        Datadog.setAccountInfo(id: "account-1234", name: "account-US")

        // Enable Logs
        Logs.enable(
            with: Logs.Configuration(
                customEndpoint: Environment.readCustomLogsURL()
            )
        )

        // Enable Crash Reporting
        CrashReporting.enable(
            with: CrashReporting.Configuration(
                appHangBacktraceEnabled: Environment.isAppHangBacktraceEnabled()
            )
        )

        // Set highest verbosity level to see debugging logs from the SDK
        Datadog.verbosityLevel = .debug

        // Enable Trace
        Trace.enable(
            with: Trace.Configuration(
                tags: ["testing-tag": "my-value"], 
                networkInfoEnabled: true,
                customEndpoint: Environment.readCustomTraceURL()
            )
        )

        // Enable RUM
        RUM.enable(
            with: RUM.Configuration(
                applicationID: Environment.readRUMApplicationID(),
                urlSessionTracking: .init(
                    firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: ["api.shopist.io": [.datadog]],sampleRate: 100),
                    resourceAttributesProvider: { req, resp, data, err in
                        print("⭐️ [Attributes Provider] data: \(String(describing: data))")
                        return [:]
                    }
                ),
                trackBackgroundEvents: true,
                appHangThreshold: 0.5,
                trackWatchdogTerminations: true,
                customEndpoint: Environment.readCustomRUMURL(),
                telemetrySampleRate: 100
            )
        )
        RUMMonitor.shared().debug = true

        URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: DummySessionDataDelegate.self))

        // Enable Feature Flags
        Flags.enable()
        let flagsClientProtocol = FlagsClient.create()
        flagsClientProtocol.setEvaluationContext(
            FlagsEvaluationContext(targetingKey: "diagnostic-user", attributes: [:])
        )
        if let flagsClient = flagsClientProtocol as? FlagsClient {
            runFlagsDiagnostics(client: flagsClient)
        }

        // Register Trace Provider
        OpenTelemetry.registerTracerProvider(
            tracerProvider: OTelTracerProvider()
        )
        Logs.addAttribute(forKey: "testing-attribute", value: "my-value")

        // Create Logger
        logger = Logger.create(
            with: Logger.Configuration(
                name: "logger-name",
                networkInfoEnabled: true,
                consoleLogFormat: .shortWith(prefix: "[iOS App] ")
            )
        )

        logger.addAttribute(forKey: "device-model", value: UIDevice.current.model)

        #if DEBUG
        logger.addTag(withKey: "build_configuration", value: "debug")
        #else
        logger.addTag(withKey: "build_configuration", value: "release")
        #endif

        // Launch initial screen depending on the launch configuration
        #if os(iOS) || os(visionOS)
        let storyboard = UIStoryboard(name: "Main iOS", bundle: nil)
        launch(storyboard: storyboard)
        #endif

        #if os(iOS)
        // Instantiate location monitor if the Example app is run in interactive mode. This will
        // enable background location tracking if it was started in previous session.
        // Note: Background location monitoring is iOS-only (not available on tvOS or visionOS).
        if Environment.isRunningInteractive() {
            backgroundLocationMonitor = BackgroundLocationMonitor(rum: rumMonitor)
        }
        #endif

        return true
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        if Environment.isRunningInteractive() {
            installConsoleOutputInterceptor()
        }
        return true
    }

    func launch(storyboard: UIStoryboard) {
        if window == nil {
            #if os(visionOS)
            window = UIWindow()
            #else
            window = UIWindow(frame: UIScreen.main.bounds)
            #endif
            window?.makeKeyAndVisible()
        }
        window?.rootViewController = storyboard.instantiateInitialViewController()!
    }
}

// MARK: - Flags SDK Diagnostics

private extension ExampleAppDelegate {
    // swiftlint:disable function_body_length
    func runFlagsDiagnostics(client: FlagsClient) {
        DispatchQueue.global(qos: .utility).async {
            let tag = "FlagsDiagnostics"
            let clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String ?? ""
            let siteName = Bundle.main.infoDictionary?["DatadogSite"] as? String ?? "us1"
            let site = DatadogSite(rawValue: siteName) ?? .us1

            guard let cdnHost = Self.flagsCdnHost(for: site),
                  let cdnURL = URL(string: "https://\(cdnHost)/precompute-assignments") else {
                NSLog("[%@] Flags CDN not supported for site %@", tag, siteName)
                return
            }
            let intakeURL = site.endpoint.appendingPathComponent("api/v2/exposures")

            NSLog("[%@] ========== FLAGS SDK NETWORK DIAGNOSTICS START ==========", tag)
            NSLog("[%@] Configured site: %@", tag, siteName.uppercased())
            NSLog("[%@] Flags CDN URL: %@", tag, cdnURL.absoluteString)
            NSLog("[%@] Exposures intake URL: %@", tag, intakeURL.absoluteString)

            // DNS resolution
            Self.dnsCheck(tag: tag, label: "Flags CDN", host: cdnHost)
            if let intakeHost = intakeURL.host {
                Self.dnsCheck(tag: tag, label: "Intake", host: intakeHost)
            }

            // HEAD checks — confirm TCP/TLS reachability without auth
            Self.headCheck(tag: tag, label: "Flags CDN", url: cdnURL)
            Self.headCheck(tag: tag, label: "Exposures intake", url: intakeURL)

            // POST probe — SDK-shaped request, reveals auth errors vs network errors
            Self.postProbe(tag: tag, url: cdnURL, clientToken: clientToken)

            NSLog("[%@] ========== FLAGS SDK NETWORK DIAGNOSTICS END ==========", tag)

            // Flag snapshot — wait for client Ready state
            Self.observeSnapshotOnce(tag: tag, client: client)
        }
    }
    // swiftlint:enable function_body_length

    static func flagsCdnHost(for site: DatadogSite) -> String? {
        let subdomain = "preview"
        switch site {
        case .us1:     return "\(subdomain).ff-cdn.datadoghq.com"
        case .us3:     return "\(subdomain).ff-cdn.us3.datadoghq.com"
        case .us5:     return "\(subdomain).ff-cdn.us5.datadoghq.com"
        case .eu1:     return "\(subdomain).ff-cdn.datadoghq.eu"
        case .ap1:     return "\(subdomain).ff-cdn.ap1.datadoghq.com"
        case .ap2:     return "\(subdomain).ff-cdn.ap2.datadoghq.com"
        case .uk1:     return "\(subdomain).ff-cdn.uk1.datadoghq.com"
        case .us1_fed, .us2_fed: return nil
        }
    }

    static func dnsCheck(tag: String, label: String, host: String) {
        let start = CFAbsoluteTimeGetCurrent()
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        if status != 0 {
            let errStr = String(cString: gai_strerror(status))
            NSLog("[%@] DNS [%@] %@ -> FAILED (%dms): %@", tag, label, host, elapsed, errStr)
            return
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var current = result
        while let info = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen,
                           &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: buffer))
            }
            current = info.pointee.ai_next
        }
        NSLog("[%@] DNS [%@] %@ -> %@ (%dms)", tag, label, host, addresses.joined(separator: ", "), elapsed)
    }

    static func headCheck(tag: String, label: String, url: URL) {
        let semaphore = DispatchSemaphore(value: 0)
        let start = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { _, response, error in
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let error = error {
                NSLog("[%@] HEAD [%@] FAILED (%dms): %@", tag, label, elapsed, error.localizedDescription)
            } else if let http = response as? HTTPURLResponse {
                NSLog("[%@] HEAD [%@] %@ -> HTTP %d (%dms)", tag, label, url.host ?? "", http.statusCode, elapsed)
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
    }

    static func postProbe(tag: String, url: URL, clientToken: String) {
        let body: [String: Any] = [
            "data": [
                "type": "precompute-assignments-request",
                "attributes": [
                    "env": ["dd_env": "diagnostic"],
                    "source": ["sdk_name": "dd-sdk-ios", "sdk_version": "diagnostic"],
                    "subject": [
                        "targeting_key": "diagnostic-probe",
                        "targeting_attributes": [:] as [String: Any]
                    ]
                ]
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            NSLog("[%@] POST [Flags CDN] FAILED: could not encode body", tag)
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientToken, forHTTPHeaderField: "dd-client-token")
        request.httpBody = bodyData

        let semaphore = DispatchSemaphore(value: 0)
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { data, response, error in
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let error = error {
                NSLog("[%@] POST [Flags CDN] FAILED (%dms): %@", tag, elapsed, error.localizedDescription)
            } else if let http = response as? HTTPURLResponse {
                let snippet = data.flatMap { String(data: $0.prefix(500), encoding: .utf8) } ?? ""
                NSLog("[%@] POST [Flags CDN] %@ -> HTTP %d (%dms)", tag, url.host ?? "", http.statusCode, elapsed)
                if !snippet.isEmpty {
                    NSLog("[%@] POST [Flags CDN] body: %@", tag, snippet)
                }
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
    }

    static func observeSnapshotOnce(tag: String, client: FlagsClient) {
        let listener = DiagnosticsStateListener(tag: tag, client: client)
        client.state.addListener(listener)
    }
}

/// One-shot state listener that dumps the flag snapshot on Ready or logs the error state.
private final class DiagnosticsStateListener: FlagsStateListener {
    private let tag: String
    private weak var client: FlagsClient?

    init(tag: String, client: FlagsClient) {
        self.tag = tag
        self.client = client
    }

    func flagsStateDidChange(_ newState: FlagsClientState) {
        let tag = self.tag
        NSLog("[%@] FlagsClient state: %@", tag, "\(newState)")
        switch newState {
        case .ready:
            dumpSnapshot()
            client?.state.removeListener(self)
        case .error:
            NSLog("[%@] Flag snapshot: client entered Error state", tag)
            client?.state.removeListener(self)
        case .stale:
            dumpSnapshot()
            client?.state.removeListener(self)
        case .notReady, .reconciling:
            break
        }
    }

    private func dumpSnapshot() {
        guard let client = client as? FlagsClientInternal else {
            NSLog("[%@] Flag snapshot: FlagsClientInternal not available", tag)
            return
        }
        let assignments = client.getFlagAssignments()
        if let flags = assignments, !flags.isEmpty {
            NSLog("[%@] Flag snapshot: %d flag(s) loaded", tag, flags.count)
            for (key, assignment) in flags {
                let variationType: String
                switch assignment.variation {
                case .boolean: variationType = "boolean"
                case .string: variationType = "string"
                case .integer: variationType = "integer"
                case .double: variationType = "double"
                case .object: variationType = "object"
                case .unknown(let rawType): variationType = "unknown(\(rawType))"
                }
                NSLog("[%@]   flag: %@ | type=%@ variant=%@ reason=%@",
                      tag, key,
                      variationType,
                      assignment.variationKey,
                      assignment.reason)
            }
        } else {
            NSLog("[%@] Flag snapshot: client Ready but no flags loaded", tag)
        }
    }
}
