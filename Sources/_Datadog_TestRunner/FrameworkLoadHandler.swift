/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public class FrameworkLoadHandler: NSObject {
    @objc
    public static func handleLoad() {
        installTestObserver()
    }

    static func installTestObserver() {
        /// Only initialize test observer if user configured so and is running tests
        guard ProcessInfo.processInfo.environment["DD_TEST_RUNNER"] != nil else {
            return
        }

        let isInTestMode = ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isInTestMode {
            DDTestRunner.instance = DDTestRunner()
        }
    }
}
