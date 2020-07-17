/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog
@testable import DatadogObjc

class DDTracerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(TracingFeature.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(TracingFeature.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testSendingCustomizedSpans() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { TracingFeature.instance = nil }

        let objcTracer = DDTracer.initialize(configuration: DDTracerConfiguration()).dd!

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

        let spanMatchers = try server.waitAndReturnSpanMatchers(count: 5)

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
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let loggingFeature = LoggingFeature.mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .veryQuick)
        )
        TracingFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp),
            loggingFeature: loggingFeature
        )
        defer { TracingFeature.instance = nil }

        let objcTracer = DDTracer(configuration: DDTracerConfiguration())

        let objcSpan = objcTracer.startSpan("operation")
        objcSpan.log(["foo": NSString(string: "bar")], timestamp: Date.mockDecember15th2019At10AMUTC())
        objcSpan.log(["bizz": NSNumber(10.5)])
        objcSpan.log(["buzz": NSURL(string: "https://example.com/image.png")!], timestamp: nil)

        let logMatchers = try server.waitAndReturnLogMatchers(count: 3)

        logMatchers[0].assertValue(forKey: "foo", equals: "bar")
        logMatchers[1].assertValue(forKey: "bizz", equals: 10.5)
        logMatchers[2].assertValue(forKey: "buzz", equals: "https://example.com/image.png")
    }

    func testInjectingSpanContextToValidCarrierAndFormat() throws {
        let objcTracer = DDTracer(swiftTracer: Tracer.mockAny())
        let objcSpanContext = DDSpanContextObjc(
            swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2)
        )

        let objcWriter = DDHTTPHeadersWriter()
        try objcTracer.inject(objcSpanContext, format: OTFormatHTTPHeaders, carrier: objcWriter)

        let expectedHTTPHeaders = [
            "x-datadog-trace-id": "1",
            "x-datadog-parent-id": "2",
        ]
        let swiftWritter = objcWriter.swiftHTTPHeadersWriter
        XCTAssertEqual(swiftWritter.tracePropagationHTTPHeaders, expectedHTTPHeaders)
    }

    func testInjectingSpanContextToInvalidCarrierOrFormat() throws {
        let objcTracer = DDTracer(swiftTracer: Tracer.mockAny())
        let objcSpanContext = DDSpanContextObjc(swiftSpanContext: DDSpanContext.mockWith(traceID: 1, spanID: 2))

        let objcValidWriter = DDHTTPHeadersWriter()
        let objcInvalidFormat = "foo"
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcInvalidFormat, carrier: objcValidWriter)
        )

        let objcInvalidWriter = NSObject()
        let objcValidFormat = OTFormatHTTPHeaders
        XCTAssertThrowsError(
            try objcTracer.inject(objcSpanContext, format: objcValidFormat, carrier: objcInvalidWriter)
        )
    }

    func testWhenSettingGlobalTracer_itSetsSwiftTracerAswell() {
        XCTAssertTrue(OTGlobal.sharedTracer === noopTracer)

        let swiftTracer = Tracer.mockAny()
        let objcTracer = DDTracer(swiftTracer: swiftTracer)

        let previousObjcTracer = OTGlobal.sharedTracer
        let previousSwiftTracer = Global.sharedTracer
        OTGlobal.initSharedTracer(objcTracer)
        defer {
            OTGlobal.sharedTracer = previousObjcTracer
            Global.sharedTracer = previousSwiftTracer
        }

        XCTAssertTrue(OTGlobal.sharedTracer === objcTracer)
        XCTAssertTrue(Global.sharedTracer as? Tracer === swiftTracer)
    }

    // MARK: - Usage errors

    func testsWhenUsingUnexpectedOTTracer() throws {
        let previousObjcTracer = OTGlobal.sharedTracer

        OTGlobal.initSharedTracer(noopTracer)

        XCTAssertTrue(OTGlobal.sharedTracer === previousObjcTracer)
        XCTAssertFalse(Global.sharedTracer is Tracer)
    }

    func testsWhenUsingUnexpectedOTSpanContext() throws {
        let objcTracer = DDTracer(swiftTracer: Tracer.mockAny())

        XCTAssertNil(objcTracer.startSpan(.mockAny(), childOf: noopSpanContext).dd!.swiftSpan.dd.ddContext.parentSpanID)
        XCTAssertNil(objcTracer.startSpan(.mockAny(), childOf: noopSpanContext, tags: NSDictionary()).dd!.swiftSpan.dd.ddContext.parentSpanID)
        XCTAssertNil(objcTracer.startSpan(.mockAny(), childOf: noopSpanContext, tags: NSDictionary(), startTime: .mockAny()).dd!.swiftSpan.dd.ddContext.parentSpanID)

        let objcWriter = DDHTTPHeadersWriter()
        try objcTracer.inject(noopSpanContext, format: OTFormatHTTPHeaders, carrier: objcWriter)
        XCTAssertEqual(objcWriter.swiftHTTPHeadersWriter.tracePropagationHTTPHeaders.count, 0)
    }

    func testsWhenUsingUnexpectedTagsDictionary() throws {
        let objcTracer = DDTracer(swiftTracer: Tracer.mockAny())

        let tags = NSDictionary(dictionary: [1: "string"])
        let objcSpan = objcTracer.startSpan(.mockAny(), tags: tags)

        XCTAssertEqual(objcSpan.dd?.swiftSpan.dd.tags.count, 0)
    }

    func testUsingNoopTracerIsSafe() {
        // noop Tracer
        XCTAssertTrue(noopTracer.startSpan(.mockAny()) === noopSpan)
        XCTAssertTrue(noopTracer.startSpan(.mockAny(), tags: nil) === noopSpan)
        XCTAssertTrue(noopTracer.startSpan(.mockAny(), childOf: nil) === noopSpan)
        XCTAssertTrue(noopTracer.startSpan(.mockAny(), childOf: nil, tags: nil) === noopSpan)
        XCTAssertTrue(noopTracer.startSpan(.mockAny(), childOf: nil, tags: nil, startTime: nil) === noopSpan)
        XCTAssertNoThrow(try noopTracer.inject(noopSpanContext, format: .mockAny(), carrier: NSObject()))
        XCTAssertNoThrow(try noopTracer.extractWithFormat(.mockAny(), carrier: NSObject()))

        // noop Span
        XCTAssertTrue(noopSpan.context === noopSpanContext)
        XCTAssertTrue(noopSpan.tracer === noopTracer)
        noopSpan.setOperationName(.mockAny())
        noopSpan.setTag(.mockAny(), value: "")
        noopSpan.setTag(.mockAny(), numberValue: 0)
        noopSpan.setTag(.mockAny(), boolValue: false)
        noopSpan.log([:])
        noopSpan.log([:], timestamp: nil)
        _ = noopSpan.setBaggageItem(.mockAny(), value: .mockAny())
        _ = noopSpan.getBaggageItem(.mockAny())
        noopSpan.finish()
        noopSpan.finishWithTime(nil)

        // noop SpanContext
        noopSpanContext.forEachBaggageItem { _, _ in false }
    }
}
