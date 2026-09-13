/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
import DatadogCore
import DatadogLogs
import DatadogTrace
import DatadogRUM
import DatadogCrashReporting
import DatadogFlags
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

        let signedAssignmentsMode = ProcessInfo.processInfo.environment["DD_SIGNED_ASSIGNMENTS_POC"]
        let datadogEnvironment = signedAssignmentsMode == nil
            ? "tests"
            : ProcessInfo.processInfo.environment["FFE_STAGING_ENV"] ?? "staging"

        // Initialize Datadog SDK
        Datadog.initialize(
            with: Datadog.Configuration(
                clientToken: Environment.readClientToken(),
                env: datadogEnvironment,
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

        // These modes exercise the signed-assignment POC. They only change the
        // example app. The SDK verifies each response before it decodes JSON.
        var assignmentProtection: Flags.AssignmentProtection?
        var assignmentAuthorization: Flags.AssignmentAuthorization?
        switch signedAssignmentsMode {
        case "signed":
            assignmentProtection = .signed
        case "signed-and-authorized":
            if let token = ProcessInfo.processInfo.environment["FFE_STAGING_ASSIGNMENT_JWT"],
               let expirationValue = ProcessInfo.processInfo.environment["FFE_STAGING_ASSIGNMENT_JWT_EXPIRES_AT"],
               let expiration = TimeInterval(expirationValue),
               Date(timeIntervalSince1970: expiration) > Date() {
                assignmentProtection = .signedAndAuthorized
                assignmentAuthorization = Flags.AssignmentAuthorization(
                    bearerToken: token,
                    expiresAt: Date(timeIntervalSince1970: expiration)
                )
            } else {
                print("SIGNED_ASSIGNMENT_E2E: invalid or missing authorization configuration")
            }
        case .some(let mode):
            print("SIGNED_ASSIGNMENT_E2E: unsupported protection mode=\(mode)")
        case .none:
            break
        }

        if let assignmentProtection {
            let endpoint = ProcessInfo.processInfo.environment["FFE_STAGING_ASSIGNMENTS_ENDPOINT"]
                .flatMap(URL.init(string:))
                ?? URL(string: "https://preview.ff-cdn.datad0g.com/precompute-assignments")
            Flags.enable(
                with: Flags.Configuration(
                    customFlagsEndpoint: endpoint,
                    assignmentProtection: assignmentProtection,
                    assignmentAuthorization: assignmentAuthorization,
                    trackExposures: false,
                    trackEvaluations: false
                )
            )
            let flagsClient = FlagsClient.create()
            flagsClient.setEvaluationContext(
                FlagsEvaluationContext(
                    targetingKey: "user123",
                    attributes: ["country": .string("US")]
                )
            ) { result in
                switch result {
                case .success:
                    print("SIGNED_ASSIGNMENT_E2E: verification=accepted; mode=\(signedAssignmentsMode ?? "unknown")")
                case .failure(let error):
                    print("SIGNED_ASSIGNMENT_E2E: verification=rejected; mode=\(signedAssignmentsMode ?? "unknown"); error=\(error)")
                }
                let value = flagsClient.getStringValue(
                    key: "country-message",
                    defaultValue: "unverified"
                )
                print("SIGNED_ASSIGNMENT_E2E: country-message=\(value)")
            }
        }

        URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: DummySessionDataDelegate.self))

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
