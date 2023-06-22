/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogTrace
@testable import Datadog
@testable import DatadogObjc

class DDTracerTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        CoreRegistry.register(default: core)
    }

    override func tearDown() {
        CoreRegistry.unregisterDefault()
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testSendingCustomizedSpans() throws {
        DDTracer.initialize(configuration: .init())

        let objcTracer = DDTracer.shared.dd!

        let objcSpan1 = objcTracer.startSpan("operation")
        let objcSpan2 = objcTracer.startSpan(
            "operation",
            tags: NSDictionary(dictionary: ["tag1": NSString(string: "value1"), "tag2": NSInteger(integerLiteral: 123)])
        )
        let objcSpan3 = objcTracer.startSpan(
            "operation",
            childOf: objcSpan1.context
        )
        let objcSpan4 = objcTracer.startSpan(
            "operation",
            childOf: objcSpan1.context,
            tags: NSDictionary(dictionary: ["tag1": NSString(string: "value1"), "tag2": NSInteger(integerLiteral: 123)])
        )
        let objcSpan5 = objcTracer.startSpan(
            "operation",
            childOf: objcSpan1.context,
            tags: NSDictionary(
                dictionary: [
                    "tag1": NSString(string: "value1"),
                    "tag2": NSInteger(integerLiteral: 123),
                    "nsurlTag": NSURL(string: "https://example.com/image.png")!
                ]
            ),
            startTime: .mockDecember15th2019At10AMUTC()
        )

        objcSpan5.setOperationName("updated operation name")
        objcSpan5.setTag("nsstringTag", value: NSString(string: "string value"))
        objcSpan5.setTag("nsnumberTag", numberValue: NSNumber(value: 10.5))
        objcSpan5.setTag("nsboolTag", boolValue: true)

        _ = objcSpan5.setBaggageItem("item", value: "value")
        XCTAssertEqual(objcSpan5.getBaggageItem("item"), "value")

        var baggageItems: [(key: String, value: String)] = []
        objcSpan5.context.forEachBaggageItem { itemKey, itemValue in
            baggageItems.append((key: itemKey, value: itemValue))
            return false
        }
        XCTAssertEqual(baggageItems.count, 1)
        XCTAssertEqual(baggageItems[0].key, "item")
        XCTAssertEqual(baggageItems[0].value, "value")

        objcSpan1.finish()
        objcSpan2.finish()
        objcSpan3.finish()
        objcSpan4.finishWithTime(nil)
        objcSpan5.finishWithTime(.mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5))

        [objcSpan1, objcSpan2, objcSpan3, objcSpan4, objcSpan5].forEach { span in
            XCTAssertTrue(span.tracer === objcTracer)
        }

        let spanMatchers = try core.waitAndReturnSpanMatchers()

        // assert operation name
        try spanMatchers[0...3].forEach { spanMatcher in
            XCTAssertEqual(try spanMatcher.operationName(), "operation")
        }
        XCTAssertEqual(try spanMatchers[4].operationName(), "updated operation name")

        // assert parent-child relationship
        try spanMatchers[2...4].forEach { spanMatcher in
            XCTAssertEqual(try spanMatcher.traceID(), try spanMatchers[0].traceID())
            XCTAssertEqual(try spanMatcher.parentSpanID(), try spanMatchers[0].spanID())
        }

        // assert tags
        try [spanMatchers[1], spanMatchers[3], spanMatchers[4]].forEach { spanMatcher in
            XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag1"), "value1")
            XCTAssertEqual(try spanMatcher.meta.custom(keyPath: "meta.tag2"), "123")
        }
        XCTAssertEqual(try spanMatchers[4].meta.custom(keyPath: "meta.nsurlTag"), "https://example.com/image.png")
        XCTAssertEqual(try spanMatchers[4].meta.custom(keyPath: "meta.nsstringTag"), "string value")
        XCTAssertEqual(try spanMatchers[4].meta.custom(keyPath: "meta.nsnumberTag"), "10.5")
        XCTAssertEqual(try spanMatchers[4].meta.custom(keyPath: "meta.nsboolTag"), "true")

        // assert baggage item
        XCTAssertEqual(try spanMatchers[4].meta.custom(keyPath: "meta.item"), "value")

        // assert timing
        XCTAssertEqual(try spanMatchers[4].startTime(), 1_576_404_000_000_000_000)
        XCTAssertEqual(try spanMatchers[4].duration(), 500_000_000)
    }

    func testSendingSpanLogs() throws {
        let logging: LogsFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        try core.register(feature: logging)

        DDTracer.initialize(configuration: .init())
        let objcTracer = DDTracer.shared

        let objcSpan = objcTracer.startSpan("operation")
        objcSpan.log(["foo": NSString(string: "bar")], timestamp: Date.mockDecember15th2019At10AMUTC())
        objcSpan.log(["bizz": NSNumber(10.5)])
        objcSpan.log(["buzz": NSURL(string: "https://example.com/image.png")!], timestamp: nil)

        let logMatchers = try core.waitAndReturnLogMatchers()

        logMatchers[0].assertValue(forKey: "foo", equals: "bar")
        logMatchers[1].assertValue(forKey: "bizz", equals: 10.5)
        logMatchers[2].assertValue(forKey: "buzz", equals: "https://example.com/image.png")
        objcSpan.finish()
    }

    func testSendingSpanLogsWithErrorFromArguments() throws {
        let logging: LogsFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        try core.register(feature: logging)

        DDTracer.initialize(configuration: .init())
        let objcTracer = DDTracer.shared

        let objcSpan = objcTracer.startSpan("operation")
        objcSpan.log(["foo": NSString(string: "bar")], timestamp: Date.mockDecember15th2019At10AMUTC())
        objcSpan.setError(kind: "Swift error", message: "Ops!", stack: nil)

        let logMatchers = try core.waitAndReturnLogMatchers()

        logMatchers[0].assertValue(forKey: "foo", equals: "bar")

        let errorLogMatcher = logMatchers[1]
        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Swift error")
        errorLogMatcher.assertMessage(equals: "Ops!")
        objcSpan.finish()
    }

    func testSendingSpanLogsWithErrorFromNSError() throws {
        let logging: LogsFeature = .mockWith(
            messageReceiver: LogMessageReceiver.mockAny()
        )
        try core.register(feature: logging)

        DDTracer.initialize(configuration: .init())
        let objcTracer = DDTracer.shared

        let objcSpan = objcTracer.startSpan("operation")
        objcSpan.log(["foo": NSString(string: "bar")], timestamp: Date.mockDecember15th2019At10AMUTC())
        let error = NSError(
            domain: "Tracer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Ops!"]
        )
        objcSpan.setError(error)

        let logMatchers = try core.waitAndReturnLogMatchers()

        logMatchers[0].assertValue(forKey: "foo", equals: "bar")

        let errorLogMatcher = logMatchers[1]
        errorLogMatcher.assertStatus(equals: "error")
        errorLogMatcher.assertValue(forKey: "event", equals: "error")
        errorLogMatcher.assertValue(forKey: "error.kind", equals: "Tracer - 1")
        errorLogMatcher.assertMessage(equals: "Ops!")
        objcSpan.finish()
    }

    func testInjectingSpanContextToValidCarrierAndFormat() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(
            swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2)
        )

        let objcWriter = DDHTTPHeadersWriter(samplingRate: 100)
        try objcTracer.inject(objcSpanContext, format: OT.formatTextMap, carrier: objcWriter)

        let expectedHTTPHeaders = [
            "x-datadog-trace-id": "1",
            "x-datadog-parent-id": "2",
            "x-datadog-sampling-priority": "1",
        ]
        XCTAssertEqual(objcWriter.traceHeaderFields, expectedHTTPHeaders)
    }

    func testInjectingRejectedSpanContextToValidCarrierAndFormat() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(
            swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2)
        )

        let objcWriter = DDHTTPHeadersWriter(samplingRate: 0)
        try objcTracer.inject(objcSpanContext, format: OT.formatTextMap, carrier: objcWriter)

        let expectedHTTPHeaders = [
            "x-datadog-sampling-priority": "0",
        ]
        XCTAssertEqual(objcWriter.traceHeaderFields, expectedHTTPHeaders)
    }

    func testInjectingSpanContextToInvalidCarrierOrFormat() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2))

        let objcValidWriter = DDHTTPHeadersWriter(samplingRate: 100)
        let objcInvalidFormat = "foo"
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcInvalidFormat, carrier: objcValidWriter)
        )

        let objcInvalidWriter = NSObject()
        let objcValidFormat = OT.formatTextMap
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcValidFormat, carrier: objcInvalidWriter)
        )
    }

    func testInjectingSpanContextToValidCarrierAndFormatForOTel() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(
            swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2)
        )

        let objcWriter = DDOTelHTTPHeadersWriter(samplingRate: 100)
        try objcTracer.inject(objcSpanContext, format: OT.formatTextMap, carrier: objcWriter)

        let expectedHTTPHeaders = [
            "b3": "00000000000000000000000000000001-0000000000000002-1-0000000000000000"
        ]
        XCTAssertEqual(objcWriter.traceHeaderFields, expectedHTTPHeaders)
    }

    func testInjectingRejectedSpanContextToValidCarrierAndFormatForOTel() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(
            swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2)
        )

        let objcWriter = DDOTelHTTPHeadersWriter(samplingRate: 0)
        try objcTracer.inject(objcSpanContext, format: OT.formatTextMap, carrier: objcWriter)

        let expectedHTTPHeaders = [
            "b3": "0",
        ]
        XCTAssertEqual(objcWriter.traceHeaderFields, expectedHTTPHeaders)
    }

    func testInjectingSpanContextToInvalidCarrierOrFormatForOTel() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2))

        let objcValidWriter = DDOTelHTTPHeadersWriter(samplingRate: 100)
        let objcInvalidFormat = "foo"
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcInvalidFormat, carrier: objcValidWriter)
        )

        let objcInvalidWriter = NSObject()
        let objcValidFormat = OT.formatTextMap
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcValidFormat, carrier: objcInvalidWriter)
        )
    }

    func testInjectingSpanContextToValidCarrierAndFormatForW3C() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(
            swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2)
        )

        let objcWriter = DDW3CHTTPHeadersWriter(samplingRate: 100)
        try objcTracer.inject(objcSpanContext, format: OT.formatTextMap, carrier: objcWriter)

        let expectedHTTPHeaders = [
            "traceparent": "00-00000000000000000000000000000001-0000000000000002-01"
        ]
        XCTAssertEqual(objcWriter.traceHeaderFields, expectedHTTPHeaders)
    }

    func testInjectingRejectedSpanContextToValidCarrierAndFormatForW3C() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(
            swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2)
        )

        let objcWriter = DDW3CHTTPHeadersWriter(samplingRate: 0)
        try objcTracer.inject(objcSpanContext, format: OT.formatTextMap, carrier: objcWriter)

        let expectedHTTPHeaders = [
            "traceparent": "00-00000000000000000000000000000001-0000000000000002-00"
        ]
        XCTAssertEqual(objcWriter.traceHeaderFields, expectedHTTPHeaders)
    }

    func testInjectingSpanContextToInvalidCarrierOrFormatForW3C() throws {
        let objcTracer = DDTracer(swiftTracer: DatadogTracer.mockAny(in: core))
        let objcSpanContext = DDSpanContextObjc(swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2))

        let objcValidWriter = DDW3CHTTPHeadersWriter(samplingRate: 100)
        let objcInvalidFormat = "foo"
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcInvalidFormat, carrier: objcValidWriter)
        )

        let objcInvalidWriter = NSObject()
        let objcValidFormat = OT.formatTextMap
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcValidFormat, carrier: objcInvalidWriter)
        )
    }

    // MARK: - Usage errors

    func testsWhenTagsDictionaryContainsInvalidKeys_thenThosesTagsAreDropped() throws {
        // Given
        DDTracer.initialize(configuration: .init())
        let objcTracer = DDTracer.shared.dd!

        // When
        let tags = NSDictionary(
            dictionary: [
                123: "tag with invalid key",
                "valid-tag": "tag with valid key"
            ]
        )
        let objcSpan = objcTracer.startSpan(.mockAny(), tags: tags)
        objcSpan.finish()

        // Then
        let spanMatchers = try core.waitAndReturnSpanMatchers()
        XCTAssertEqual(spanMatchers.count, 1)
        XCTAssertNil(try? spanMatchers[0].meta.custom(keyPath: "meta.123"), "123 is not a valid tag-key, so it should be dropped")
        XCTAssertNotNil(try? spanMatchers[0].meta.custom(keyPath: "meta.valid-tag"))
    }
}
