/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal
import DatadogBenchmarks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        guard let scenario = SyntheticScenario() else {
            return false
        }

        let run = SyntheticRun()
        let applicationInfo = try! AppInfo() // crash if info are missing or malformed

        // Collect metrics during all run
        let meter = Meter(
            provider: Benchmarks.metricsProvider(
                with: Benchmarks.Configuration(
                    info: applicationInfo,
                    scenario: scenario,
                    run: run
                )
            )
        )

        switch run {
        case .baseline, .instrumented:
            meter.observeCPU()
            meter.observeMemory()
            meter.observeFPS()

        case .profiling:
            // Collect traces during profiling run
            let profiler = Profiler(
                provider: Benchmarks.tracerProvider(
                    with: Benchmarks.Configuration(
                        info: applicationInfo,
                        scenario: scenario,
                        run: run
                    )
                )
            )

            DatadogInternal.bench = (profiler, meter)
        case .none:
            break
        }

        if run != .baseline {
            // instrument the application with Datadog SDK
            // when not in baseline run
            scenario.instrument(with: applicationInfo)
        }

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = scenario.initialViewController
        window?.makeKeyAndVisible()

        return true
    }
}

extension Benchmarks.Configuration {
    init(
        info: AppInfo,
        scenario: SyntheticScenario,
        run: SyntheticRun,
        bundle: Bundle = .main,
        sysctl: SysctlProviding = Sysctl(),
        device: UIDevice = .current
    ) {
        self.init(
            clientToken: info.clientToken,
            apiKey: info.apiKey,
            context: Benchmarks.Configuration.Context(
                applicationIdentifier: bundle.bundleIdentifier!,
                applicationName: bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as! String,
                applicationVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as! String,
                sdkVersion: "",
                deviceModel: try! sysctl.model(),
                osName: device.systemName,
                osVersion: device.systemVersion,
                run: run.rawValue,
                scenario: scenario.name.rawValue,
                branch: ""
            )
        )
    }
}
