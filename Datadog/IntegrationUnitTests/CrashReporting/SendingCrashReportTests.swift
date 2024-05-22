/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCrashReporting
import DatadogInternal
@testable import DatadogLogs
@testable import DatadogRUM

/// A crash reporter mock with two capabilities:
/// - notifying a pending crash report found at SDK init,
/// - recording crash context data injected from SDK core and features like RUM.
private class CrashReporterMock: CrashReportingPlugin {
    @ReadWriteLock
    internal var pendingCrashReport: DDCrashReport?
    @ReadWriteLock
    internal var injectedContext: Data? = nil

    init(pendingCrashReport: DDCrashReport? = nil) {
        self.pendingCrashReport = pendingCrashReport
    }

    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) { _ = completion(pendingCrashReport) }
    func inject(context: Data) { injectedContext = context }
}

/// Covers broad scenarios of sending Crash Reports.
class SendingCrashReportTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testWhenSDKStartsWithPendingCrashReport_itSendsItAsLogAndRUMEvent() throws {
        // Given
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted, // CR from the app session that has enabled data collection
            lastIsAppInForeground: true, // CR occurred while the app was in the foreground
            lastRUMAttributes: GlobalRUMAttributes(attributes: mockRandomAttributes()),
            lastLogAttributes: .init(mockRandomAttributes())
        )
        let crashReport: DDCrashReport = .mockRandomWith(context: crashContext)

        // When
        Logs.enable(with: .init(), in: core)
        RUM.enable(with: .init(applicationID: "rum-app-id"), in: core)
        CrashReporting.enable(with: CrashReporterMock(pendingCrashReport: crashReport), in: core)

        // Then (an emergency log is sent)
        let log = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: LogsFeature.name, ofType: LogEvent.self).first)
        XCTAssertEqual(log.status, .emergency)
        XCTAssertEqual(log.message, crashReport.message)
        XCTAssertEqual(log.error?.message, crashReport.message)
        XCTAssertEqual(log.error?.kind, crashReport.type)
        XCTAssertEqual(log.error?.stack, crashReport.stack)
        XCTAssertFalse(log.attributes.userAttributes.isEmpty)
        DDAssertJSONEqual(log.attributes.userAttributes, crashContext.lastLogAttributes!)
        XCTAssertNotNil(log.attributes.internalAttributes?[DDError.threads])
        XCTAssertNotNil(log.attributes.internalAttributes?[DDError.binaryImages])
        XCTAssertNotNil(log.attributes.internalAttributes?[DDError.meta])
        XCTAssertNotNil(log.attributes.internalAttributes?[DDError.wasTruncated])

        // Then (RUMError is sent)
        let rumEvent = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(rumEvent.error.message, crashReport.message)
        XCTAssertEqual(rumEvent.error.type, crashReport.type)
        XCTAssertEqual(rumEvent.error.stack, crashReport.stack)
        XCTAssertNotNil(rumEvent.error.threads)
        XCTAssertNotNil(rumEvent.error.binaryImages)
        XCTAssertNotNil(rumEvent.error.meta)
        XCTAssertNotNil(rumEvent.error.wasTruncated)
        DDAssertJSONEqual(rumEvent.context!.contextInfo, crashContext.lastRUMAttributes!)
    }

    func testWhenSendingCrashReportAsLog_itIsLinkedToTheRUMSessionThatHasCrashed() throws {
        let crashReporter = CrashReporterMock()

        // Given (RUM session)
        Logs.enable(with: .init(), in: core)
        RUM.enable(with: .init(applicationID: "rum-app-id"), in: core)
        CrashReporting.enable(with: crashReporter, in: core)
        RUMMonitor.shared(in: core).startView(key: "view-1", name: "FirstView")

        let rumEvent = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMViewEvent.self).last)

        // Flush async tasks in Crash Reporting feature (this is yet not a part of `core.flushAndTearDown()` today)
        // TODO: RUM-2766 Stop core instance with completion
        (core.get(feature: CrashReportingFeature.self)!.crashContextProvider as! CrashContextCoreProvider).flush()
        core.flushAndTearDown()

        // When (starting an SDK with pending crash report)
        core = DatadogCoreProxy()

        let crashReport: DDCrashReport = .mockRandomWith( // mock a CR with context injected from previous instance of the SDK
            contextData: crashReporter.injectedContext!
        )

        Logs.enable(with: .init(), in: core)
        RUM.enable(with: .init(applicationID: "rum-app-id"), in: core)
        CrashReporting.enable(with: CrashReporterMock(pendingCrashReport: crashReport), in: core)

        // Then (an emergency log is sent)
        let log = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: LogsFeature.name, ofType: LogEvent.self).first)
        XCTAssertEqual(log.status, .emergency)
        XCTAssertEqual(log.message, crashReport.message)
        XCTAssertEqual(log.attributes.internalAttributes?["application_id"] as? String, rumEvent.application.id)
        XCTAssertEqual(log.attributes.internalAttributes?["session_id"] as? String, rumEvent.session.id)
        XCTAssertEqual(log.attributes.internalAttributes?["view.id"] as? String, rumEvent.view.id)
    }
}
