/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

@MainActor
class DDSpanTests: XCTestCase {
    // MARK: - Sending SpanEvent

    func testWhenSpanIsFinished_itWritesSpanEventToCore() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - Customizing SpanEvents

    func testWhenSettingCustomOperationName_itOverwritesOriginalName() throws {
        let writeSpansExpectation = expectation(description: "write 2 span events")
        writeSpansExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let defaultOperationName: String = .mockRandom()
        let tracer: DatadogTracer = .mockWith(core: core)
        let defaultSpan = tracer.startSpan(operationName: defaultOperationName)
        let customizedSpan = tracer.startSpan(operationName: defaultOperationName)

        // When
        let customizedOperationName: String = .mockRandom()
        customizedSpan.setOperationName(customizedOperationName)

        // Then
        defaultSpan.finish()
        customizedSpan.finish()

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].spans.first?.operationName, defaultOperationName)
        XCTAssertEqual(events[1].spans.first?.operationName, customizedOperationName)
    }

    func testWhenSettingCustomTags_theyAreMergedWithDefaultTags() throws {
        let writeSpansExpectation = expectation(description: "write 2 span events")
        writeSpansExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let defaultTags: [String: String] = .mockRandom()
        let tracer: DatadogTracer = .mockWith(core: core)
        let defaultSpan = tracer.startSpan(operationName: .mockAny(), tags: defaultTags)
        let customizedSpan = tracer.startSpan(operationName: .mockAny(), tags: defaultTags)

        // When
        let customTags: [String: String] = .mockRandom()
        customTags.forEach { tagKey, tagValue in
            customizedSpan.setTag(key: tagKey, value: tagValue)
        }

        // Then
        defaultSpan.finish()
        customizedSpan.finish()

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].spans.first?.tags, defaultTags)
        XCTAssertEqual(events[1].spans.first?.tags, defaultTags.merging(customTags) { _, custom in custom })
    }

    func testSettingBaggageItems() {
        // Given
        let span: DDSpan = .mockWith(
            core: PassthroughCoreMock(),
            context: .mockWith(baggageItems: BaggageItems())
        )
        XCTAssertEqual(span.ddContext.baggageItems.all, [:])

        // When
        span.setBaggageItem(key: "foo", value: "bar")
        span.setBaggageItem(key: "bizz", value: "buzz")

        // Then
        XCTAssertEqual(span.baggageItem(withKey: "foo"), "bar")
        XCTAssertEqual(span.baggageItem(withKey: "bizz"), "buzz")
        XCTAssertEqual(span.ddContext.baggageItems.all, ["foo": "bar", "bizz": "buzz"])
    }

    // MARK: - Thread Safety

    func testSpanCanBeSafelyAccessedFromDifferentThreads() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When
        callConcurrently(
            closures: [
                // swiftlint:disable opening_brace
                { span.setTag(key: .mockRandom(), value: "value") },
                { span.setBaggageItem(key: .mockRandom(), value: "value") },
                { _ = span.baggageItem(withKey: .mockRandom()) },
                { _ = span.context.forEachBaggageItem { _, _ in return false } },
                // swiftlint:enable opening_brace
            ],
            iterations: 100
        )

        span.finish()

        // Then
        waitForExpectations(timeout: 2, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].spans.first?.tags.count, 200, "It should contain 200 tags (100 explicit tags + 100 baggage items as tags)")
    }

    // MARK: - Tag Flattening

    func testFlattenedTagPairs_withFlatDictionary_prefixesEachKey() {
        let pairs = flattenedTagPairs(key: "context", value: ["foo": "foo-value", "bar": "bar-value"])

        let asStrings = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1 as? String) })
        XCTAssertEqual(asStrings, ["context.foo": "foo-value", "context.bar": "bar-value"])
    }

    func testFlattenedTagPairs_withNestedDictionary_recursesToLeaves() {
        let pairs = flattenedTagPairs(key: "outer", value: ["inner": ["x": "y"]])

        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].0, "outer.inner.x")
        XCTAssertEqual(pairs[0].1 as? String, "y", "nested dictionaries must be recursively flattened all the way to their leaves")
    }

    func testFlattenedTagPairs_withNonDictionaryValue_returnsSinglePairUnchanged() {
        let pairs = flattenedTagPairs(key: "leaf", value: 42)

        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].0, "leaf")
        XCTAssertEqual(pairs[0].1 as? Int, 42)
    }

    func testFlattenedTagPairs_withEmptyDictionary_returnsNoPairs() {
        let pairs = flattenedTagPairs(key: "context", value: [String: String]())

        XCTAssertTrue(pairs.isEmpty, "an empty dictionary tag value has no leaves, so it must produce no tags at all — not the container key itself")
    }

    func testWhenSettingFlatHomogeneousDictionaryTag_itFlattensToLeafTags() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When
        span.setTag(key: "context", value: ["foo": "foo-value", "bar": "bar-value"])
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["context.foo"], "foo-value")
        XCTAssertEqual(tags["context.bar"], "bar-value")
        XCTAssertNil(tags["context"], "the container key itself must not be stored as a blob tag")
    }

    func testWhenSettingMixedTypeDictionaryTag_itFlattensToLeafTagsWithCorrectTypes() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When
        span.setTag(key: "ctx", value: ["a": "1", "b": 2])
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["ctx.a"], "1")
        XCTAssertEqual(tags["ctx.b"], "2")
        XCTAssertNil(tags["ctx"], "the container key itself must not be stored as a blob tag")
    }

    func testWhenSettingNestedHomogeneousDictionaryTag_itFlattensRecursively() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When
        span.setTag(key: "outer", value: ["inner": ["x": "y"]])
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["outer.inner.x"], "y")
        XCTAssertNil(tags["outer"])
        XCTAssertNil(tags["outer.inner"])
    }

    func testWhenStartingSpanWithDictionaryInInitialTags_itFlattensToLeafTags() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)

        // When
        let span = tracer.startSpan(operationName: .mockAny(), tags: ["context": ["foo": "foo-value", "bar": "bar-value"]])
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["context.foo"], "foo-value")
        XCTAssertEqual(tags["context.bar"], "bar-value")
        XCTAssertNil(tags["context"], "a dictionary passed via startSpan(tags:) must flatten identically to one passed via setTag(key:value:) afterward")
    }

    func testWhenUserTagCollidesWithGlobalTagAfterFlattening_userTagAlwaysWins() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given: a global tag with a literal dotted key, and a user tag whose dictionary flattens to that
        // exact same key. The collision only becomes visible *after* flattening — verifying this resolves
        // deterministically to the user's value (not by incidental dictionary iteration order) is the point
        // of this test.
        let tracer: DatadogTracer = .mockWith(core: core, tags: ["context.foo": "global-value"])

        // When
        let span = tracer.startSpan(operationName: .mockAny(), tags: ["context": ["foo": "user-value"]])
        span.finish()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["context.foo"], "user-value", "user tags must win over global tags even when the collision only appears after flattening")
    }

    func testWhenUserOverridesGlobalDictionaryTagWithAScalar_itReplacesTheWholeGlobalNamespace() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given: a global dictionary tag, already flattened into leaves at `DatadogTracer.init` — so by the
        // time `startSpan` merges tags, there is no single "context" key left in `global` for a per-span
        // scalar override to collide with directly (only "context.foo"/"context.baz" leaves exist).
        let tracer: DatadogTracer = .mockWith(core: core, tags: ["context": ["foo": "global-foo", "baz": "global-baz"]])

        // When: the caller overrides the whole "context" tag with a scalar value for this one span — the same
        // thing they could do before dictionary flattening existed, when "context" was still a single literal
        // key on both sides.
        let span = tracer.startSpan(operationName: .mockAny(), tags: ["context": "span-value"])
        span.finish()

        // Then: the override must win outright — none of the global dictionary's leaves should survive
        // alongside it. (Before this fix, `mergeTags` had no key left to collide on, so both
        // "context.foo"/"context.baz" and the new "context" tag ended up on the span at once.)
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["context"], "span-value")
        XCTAssertNil(tags["context.foo"], "a per-span override must replace the whole global dictionary namespace, not sit alongside its stale leaves")
        XCTAssertNil(tags["context.baz"], "a per-span override must replace the whole global dictionary namespace, not sit alongside its stale leaves")
    }

    func testWhenSettingTheSameDictionaryTagKeyTwice_itReplacesTheWholeNamespaceInsteadOfMergingLeaves() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When: the same top-level key is set twice with different dictionary tags — per `setTag`'s usual
        // "replace" semantics, the second call should replace the first entirely, not merge with it.
        span.setTag(key: "ctx", value: ["a": "old", "b": "old"])
        span.setTag(key: "ctx", value: ["a": "new"])
        span.finish()

        // Then: only the leaves from the second call must survive — "ctx.b" must not linger from the first.
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["ctx.a"], "new")
        XCTAssertNil(tags["ctx.b"], "re-setting the same dictionary tag key must replace its whole namespace, not leave stale leaves from the previous value")
    }

    func testWhenOverridingADictionaryTagKeyWithAScalar_itReplacesTheWholeNamespace() throws {
        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When: a dictionary tag is set under "ctx", then the same top-level key is overridden with a scalar —
        // the same self-override case exercised by `OTelSpan.end()`, which applies global tags (possibly
        // dictionaries) and local attributes as a sequence of `setTag` calls on the same span.
        span.setTag(key: "ctx", value: ["a": "old", "b": "old"])
        span.setTag(key: "ctx", value: "scalar-value")
        span.finish()

        // Then: none of the earlier dictionary's leaves should survive alongside the scalar override.
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["ctx"], "scalar-value")
        XCTAssertNil(tags["ctx.a"], "a scalar self-override must replace the whole dictionary namespace, not sit alongside its stale leaves")
        XCTAssertNil(tags["ctx.b"], "a scalar self-override must replace the whole dictionary namespace, not sit alongside its stale leaves")
    }

    func testWhenFlattenedDictionaryKeyCollidesWithManualKeepOrDrop_itStoresTheTagInsteadOfOverridingSampling() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span") as! DDSpan
        let context = span.context as! DDSpanContext
        let priorityBeforeCall = context.samplingDecision.samplingPriority

        // When: a dictionary tag happens to flatten to the exact literal key "manual.keep" — this must NOT be
        // confused with a real call to `keepTrace()`/`setTag(key: SpanTags.manualKeep, value: true)`. The
        // sampling override hook (`DDSpanContext.span(willSetTagWithKey:)`) must only ever see the key/value
        // exactly as the caller wrote them, not synthetic keys produced by flattening.
        span.setTag(key: "manual", value: ["keep": true])
        span.finish()

        // Then: the tag is stored as a normal leaf tag, and sampling is untouched — this is the caller's own
        // "manual" namespace, unrelated to the reserved `SpanTags.manualKeep`/`manualDrop` tags.
        XCTAssertEqual(context.samplingDecision.samplingPriority, priorityBeforeCall, "a nested dictionary tag must never trigger the manual sampling override")
        XCTAssertEqual(context.samplingDecision.decisionMaker, .agentRate)

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["manual.keep"], "true", "the flattened tag must actually be stored, not silently dropped along with the sampling override")
    }

    func testWhenFlattenedMixedTypeDictionaryKeyCollidesWithManualKeepOrDrop_itStoresTheTagInsteadOfOverridingSampling() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span") as! DDSpan
        let context = span.context as! DDSpanContext
        let priorityBeforeCall = context.samplingDecision.samplingPriority

        // When: same collision as the homogeneous-dictionary test above, but via the mixed-value-type
        // `setTag(key:value: [String: OTTagValue])` overload — this must not reintroduce the bug that overload
        // used to have (routing through the public `setTag(key:value:)` once per entry, which let synthetic
        // flattened keys reach the sampling-override hook).
        span.setTag(key: "manual", value: ["keep": true, "other": 5])
        span.finish()

        // Then
        XCTAssertEqual(context.samplingDecision.samplingPriority, priorityBeforeCall, "a nested mixed-type dictionary tag must never trigger the manual sampling override")
        XCTAssertEqual(context.samplingDecision.decisionMaker, .agentRate)

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["manual.keep"], "true", "the flattened tags must actually be stored, not silently dropped along with the sampling override")
        XCTAssertEqual(tags["manual.other"], "5")
    }

    func testWhenSettingMixedTypeDictionaryTagOnFinishedSpan_itWarnsExactlyOnce() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span")
        span.finish()

        // When: `warnIfFinished` short-circuits `setTag(key:value: [String: OTTagValue])` before flattening ever
        // runs, so the dictionary's size/contents are irrelevant here — this verifies the finished-span warning
        // itself fires exactly once per call, regardless of which overload was used to reach it.
        span.setTag(key: "ctx", value: ["a": "1", "b": 2, "c": true])

        // Then
        XCTAssertEqual(
            dd.logger.warnLogs.count,
            1,
            "setTag on a finished span must warn exactly once per call, regardless of overload or dictionary size"
        )
    }

    func testWhenFlattenedDictionaryKeysCollideWithinOneCall_itWarnsAndKeepsOneOfTheColliding() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: .mockAny())

        // When: a literal dotted key ("a.b") and a nested dictionary entry ("a": ["b": ...]) both flatten
        // to the same leaf key ("ctx.a.b") within a single `setTag` call. Sorted by key, "a" is processed
        // before "a.b" ("a" is a proper prefix of "a.b", so it sorts first), so "a.b"'s value is written last
        // and wins deterministically — not an arbitrary "either value" outcome.
        span.setTag(key: "ctx", value: ["a.b": "literal", "a": ["b": "nested"]])
        span.finish()

        // Then: exactly one warning is raised, with content identifying a same-call key collision — not
        // silently dropped, and not some unrelated warning that happens to also fire once for this input.
        XCTAssertEqual(dd.logger.warnLogs.count, 1, "a same-call key collision must be surfaced as a warning")
        let message = try XCTUnwrap(dd.logger.warnLog?.message)
        XCTAssertTrue(message.contains("collide"), "the warning must describe a key collision, not some other issue: \(message)")

        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let tags = events[0].spans.first?.tags ?? [:]
        XCTAssertEqual(tags["ctx.a.b"], "literal", "the deterministic winner must be \"literal\", per the sort order explained above")
    }

    func testWhenDictionaryFlattensToResourceTag_itWarnsAndAppliesSameAsManualFlattening() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the operation")

        // When: flattening produces the exact same key a caller could already set manually.
        span.setTag(key: "resource", value: ["name": "custom resource"])
        span.finish()

        // Then: it warns about the special key, but still behaves like
        // `span.setTag(key: SpanTags.resource, value: "custom resource")`.
        XCTAssertEqual(dd.logger.warnLogs.count, 1)
        let message = try XCTUnwrap(dd.logger.warnLog?.message)
        XCTAssertTrue(message.contains(SpanTags.resource), "the warning must name the special key: \(message)")
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let span0 = try XCTUnwrap(events[0].spans.first)
        XCTAssertNil(span0.tags[SpanTags.resource], "SpanTagsReducer extracts resource.name from generic tags")
        XCTAssertEqual(span0.resource, "custom resource")
    }

    func testWhenGlobalDictionaryFlattensToOperationTag_itWarnsAndAppliesSameAsManualFlattening() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let writeSpansExpectation = expectation(description: "write span event")
        let core = PassthroughCoreMock()
        core.onEventWriteContext = { _ in writeSpansExpectation.fulfill() }

        // Given: the same special tag shape, reached through tracer global tags instead of per-span `setTag`.
        let tracer: DatadogTracer = .mockWith(core: core, tags: ["operation": ["name": "custom operation"]])
        let span = tracer.startSpan(operationName: "the operation")
        span.finish()

        // Then: it warns about the special key, but still behaves like a manually flattened
        // global `SpanTags.operation` tag.
        XCTAssertEqual(dd.logger.warnLogs.count, 1)
        let message = try XCTUnwrap(dd.logger.warnLog?.message)
        XCTAssertTrue(message.contains(SpanTags.operation), "the warning must name the special key: \(message)")
        waitForExpectations(timeout: 0.5, handler: nil)
        let events: [SpanEventsEnvelope] = core.events()
        let span0 = try XCTUnwrap(events[0].spans.first)
        XCTAssertNil(span0.tags[SpanTags.operation], "SpanTagsReducer extracts operation.name from generic tags")
        XCTAssertEqual(span0.operationName, "custom operation")
    }

    func testWhenSettingManualKeepTagDirectly_itStillOverridesSamplingAsBefore() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span") as! DDSpan
        let context = span.context as! DDSpanContext

        // When: the literal, direct call this hook exists for — unaffected by moving the hook check before
        // flattening, since a non-dictionary value flattens to itself unchanged.
        span.setTag(key: SpanTags.manualKeep, value: true)

        // Then
        XCTAssertEqual(context.samplingDecision.samplingPriority, .manualKeep)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .manual)

        span.finish()
    }

    func testWhenSettingDictionaryTagOnFinishedSpan_itWarnsExactlyOnce() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span")
        span.finish()

        // When: `warnIfFinished` short-circuits `setTag(key:value: [String: OTTagValue])` before flattening ever
        // runs, so the dictionary's size/contents are irrelevant here — see the mixed-type variant above for the
        // same reasoning. This just confirms it holds for the homogeneous-dictionary overload path too.
        span.setTag(key: "context", value: ["foo": "1", "bar": "2", "baz": "3"])

        // Then
        XCTAssertEqual(
            dd.logger.warnLogs.count,
            1,
            "setTag on a finished span must warn exactly once per call, regardless of overload or dictionary size"
        )
    }

    // MARK: - Usage

    func testGivenFinishedSpan_whenCallingItsAPI_itPrintsErrors() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span")
        span.finish()

        let fixtures: [(() -> Void, String)] = [
            ({ span.setOperationName(.mockAny()) },
            "🔥 Calling `setOperationName(_:)` on a finished span (\"the span\") is not allowed."),
            ({ span.setTag(key: .mockAny(), value: 0) },
            "🔥 Calling `setTag(key:value:)` on a finished span (\"the span\") is not allowed."),
            ({ span.setBaggageItem(key: .mockAny(), value: .mockAny()) },
            "🔥 Calling `setBaggageItem(key:value:)` on a finished span (\"the span\") is not allowed."),
            ({ _ = span.baggageItem(withKey: .mockAny()) },
            "🔥 Calling `baggageItem(withKey:)` on a finished span (\"the span\") is not allowed."),
            ({ span.finish(at: .mockAny()) },
            "🔥 Calling `finish(at:)` on a finished span (\"the span\") is not allowed."),
            ({ span.log(fields: [:], timestamp: .mockAny()) },
            "🔥 Calling `log(fields:timestamp:)` on a finished span (\"the span\") is not allowed."),
        ]

        fixtures.forEach { tracerMethod, expectedConsoleWarning in
            tracerMethod()
            XCTAssertEqual(dd.logger.warnLog?.message, expectedConsoleWarning)
        }
    }

    // MARK: Sampling convenience methods

    func testKeepTraceFunctionSetsExpectedSamplingDecision() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span") as! DDSpan
        let context = span.context as! DDSpanContext

        XCTAssertTrue(context.samplingDecision.samplingPriority == .autoKeep || context.samplingDecision.samplingPriority == .autoDrop)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .agentRate)

        span.keepTrace()

        XCTAssertEqual(context.samplingDecision.samplingPriority, .manualKeep)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .manual)
    }

    func testDropTraceFunctionSetsExpectedSamplingDecision() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock(messageReceiver: FeatureMessageReceiverMock())
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "the span") as! DDSpan
        let context = span.context as! DDSpanContext

        XCTAssertTrue(context.samplingDecision.samplingPriority == .autoKeep || context.samplingDecision.samplingPriority == .autoDrop)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .agentRate)

        span.dropTrace()

        XCTAssertEqual(context.samplingDecision.samplingPriority, .manualDrop)
        XCTAssertEqual(context.samplingDecision.decisionMaker, .manual)
    }

    // MARK: - Attribute Encoding Error Handling

    /// These tests use `AnyEncodable` to wrap non-`Encodable` types, simulating real production scenarios.
    /// There are 2 possible use-cases:
    /// - **ObjC APIs** (primary production path): Customers use ObjC APIs like `startSpan(_:tags:)` which accepts `NSDictionary`.
    ///   SDK automatically wraps non-String/URL values in `AnyEncodable`, losing type safety. Telemetry shows this is the dominant error path.
    /// - **Swift APIs with manual wrapping**: Swift API requires `Encodable`, but customers can explicitly wrap non-encodable
    ///   types using `AnyEncodable(value)` to bypass compile-time checks.

    func testWhenMultipleSpanTagsFailToEncode_itSkipsAllMalformedTags() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "test operation")

        // When - test various non-encodable types (closures are most common from telemetry)
        let closure1: (NSArray) -> Void = { _ in }
        let closure2: () -> Void = { }
        span.setTag(key: "valid_tag", value: "test_value")
        span.setTag(key: "onComplete", value: AnyEncodable(closure1) as! OTTagValue)
        span.setTag(key: "callback", value: AnyEncodable(closure2) as! OTTagValue)
        span.setTag(key: "custom_object", value: AnyEncodable(NSObject()) as! OTTagValue)
        span.finish()

        // Then
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)

        let spanEvent = try XCTUnwrap(events.first?.spans.first)

        // Encode to JSON to trigger attribute encoding
        let jsonData = try JSONEncoder().encode(spanEvent)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Span sent with only valid tag
        XCTAssertEqual(jsonObject["meta.valid_tag"] as? String, "test_value")
        XCTAssertNil(jsonObject["meta.onComplete"])
        XCTAssertNil(jsonObject["meta.callback"])
        XCTAssertNil(jsonObject["meta.custom_object"])

        // And all errors logged
        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute") }.count,
            3
        )
    }

    func testWhenOnlyMalformedSpanTagsAdded_itSendsSpanWithoutCustomTags() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        let span = tracer.startSpan(operationName: "test operation")

        // When
        span.setTag(key: "invalid_tag1", value: AnyEncodable(NSObject()) as! OTTagValue)
        span.setTag(key: "invalid_tag2", value: AnyEncodable(NSObject()) as! OTTagValue)
        span.finish()

        // Then
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.count, 1)

        let spanEvent = try XCTUnwrap(events.first?.spans.first)
        XCTAssertEqual(spanEvent.operationName, "test operation")

        // Encode to JSON
        let jsonData = try JSONEncoder().encode(spanEvent)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Span still sent, just without custom tags
        XCTAssertNil(jsonObject["meta.invalid_tag1"])
        XCTAssertNil(jsonObject["meta.invalid_tag2"])

        // And errors logged
        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute") }.count,
            2
        )
    }
}
