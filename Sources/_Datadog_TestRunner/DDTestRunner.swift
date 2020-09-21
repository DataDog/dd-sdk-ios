/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

internal class DDTestRunner: NSObject, XCTestObservation {
    static var instance: DDTestRunner?

    private let env = DDEnvironmentValues()
    private let testNameRegex = try? NSRegularExpression(pattern: "([\\w]+) ([\\w]+)", options: .caseInsensitive)
    private let supportsSkipping = NSClassFromString("XCTSkippedTestContext") != nil
    private var currentBundleName = ""
    var activeTestSpan: DDSpan?

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
        startTracer()
    }

    func startTracer() {
        guard let clientToken = env.ddClientToken else {
            return
        }

        Datadog.initialize(
            appContext: .init(),
            configuration: Datadog.Configuration
                .builderUsing(clientToken: clientToken, environment: env.ddEnvironment ?? "test")
                .set(serviceName: env.ddService ?? ProcessInfo.processInfo.processName)
                .build()
        )

        Global.sharedTracer = Tracer.initialize(
            configuration: Tracer.Configuration(
                sendNetworkInfo: true
            )
        )
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        currentBundleName = testBundle.bundleURL.deletingPathExtension().lastPathComponent
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        guard let tracer = Global.sharedTracer as? DDTracer else {
            return
        }

        /// We need to wait for all the traces to be written to the backend before exiting

        tracer.queue.sync {} // waits until data is passed to writer
        if let writer = TracingFeature.instance?.storage.writer as? FileWriter {
            writer.queue.sync {} // waits until data is written
        }
        /// <--- here the file will be existing

        do {
            let directory = try Directory(withSubdirectoryPath: TracingFeature.dataDirectoryPath)
            while try directory.files().count > 0 {
                Thread.sleep(forTimeInterval: 0.5)
            }
        } catch {
            return
        }
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard let tracer = Global.sharedTracer as? DDTracer else {
            return
        }
        guard let namematch = testNameRegex?.firstMatch(in: testCase.name, range: NSRange(location: 0, length: testCase.name.count)),
            let suiteRange = Range(namematch.range(at: 1), in: testCase.name),
            let nameRange = Range(namematch.range(at: 2), in: testCase.name) else {
                return
        }
        let testSuite = String(testCase.name[suiteRange])
        let testName = String(testCase.name[nameRange])

        let tags: [String: Encodable] = [
            OTTags.spanKind: "test",
            DDTags.resource: testCase.name,
            DDTestingTags.testSuite: testSuite,
            DDTestingTags.testName: testName,
            DDTestingTags.testFramework: "XCTest",
            DDTestingTags.testTraits: currentBundleName
        ]

        let testSpan = tracer.startSpan(spanContext: tracer.createSpanContext(), operationName: "XCTest.test", spanType: DDTestingTags.typeTest, tags: tags)
        testSpan.setActive()
        env.addTagsToSpan(span: testSpan)
        activeTestSpan = testSpan
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let activeTest = activeTestSpan else {
            return
        }
        var status: String
        if supportsSkipping && testCase.testRun?.hasBeenSkipped == true {
            status = DDTestingTags.statusSkip
        } else if testCase.testRun?.hasSucceeded ?? false {
            status = DDTestingTags.statusPass
        } else {
            status = DDTestingTags.statusFail
            activeTestSpan?.setTag(key: OTTags.error, value: true)
        }

        activeTest.setTag(key: DDTestingTags.testStatus, value: status)
        activeTest.finish()
        activeTestSpan = nil
    }

    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        activeTestSpan?.log(
            fields: [
                OTLogFields.event: "test",
                DDTestingTags.logSource: "\(filePath ?? ""):\(lineNumber)",
                OTLogFields.message: description
            ]
        )
    }
}
