/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogTrace;

@interface DDTrace_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - minimal assertions, mainly check if the interface is available to Objc.
 */
@implementation DDTrace_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"
#pragma clang diagnostic ignored "-Wunused-variable"

- (void)testDDTraceAPI {
    DDTraceConfiguration *config = [[DDTraceConfiguration alloc] init];
    [DDTrace enableWith:config];
}

- (void)testDDTraceConfigurationAPI {
    DDTraceConfiguration *config = [[DDTraceConfiguration alloc] init];

    XCTAssertEqual(config.sampleRate, 100);
    config.sampleRate = 10;
    XCTAssertEqual(config.sampleRate, 10);

    XCTAssertNil(config.service);
    config.service = @"custom-service";
    XCTAssertNotNil(config.service);

    XCTAssertNil(config.tags);
    config.tags = @{};
    XCTAssertNotNil(config.tags);

    DDTraceFirstPartyHostsTracing *tracing;
    tracing = [[DDTraceFirstPartyHostsTracing alloc] initWithHosts:[NSSet new] sampleRate:20];
    tracing = [[DDTraceFirstPartyHostsTracing alloc] initWithHosts:[NSSet new]];
    tracing = [[DDTraceFirstPartyHostsTracing alloc] initWithHostsWithHeaderTypes:@{}];
    tracing = [[DDTraceFirstPartyHostsTracing alloc] initWithHostsWithHeaderTypes:@{} sampleRate:20];
    DDTraceURLSessionTracking *urlSessionTracking = [[DDTraceURLSessionTracking alloc] initWithFirstPartyHostsTracing:tracing];

    config.bundleWithRumEnabled = NO;
    XCTAssertFalse(config.bundleWithRumEnabled);

    config.networkInfoEnabled = YES;
    XCTAssertTrue(config.networkInfoEnabled);

    XCTAssertNil(config.customEndpoint);
    config.customEndpoint = [NSURL new];
    XCTAssertNotNil(config.customEndpoint);
}

- (void)testDDTracerAPI {
    [[DDTracer shared] startSpan:@""];
    [[DDTracer shared] startSpan:@"" tags:@{}];
    [[DDTracer shared] startSpan:@"" childOf:NULL];
    id<OTSpan> span = [[DDTracer shared] startSpan:@"" childOf:NULL tags:NULL startTime:NULL];
    [span finish];
    [span finishWithTime:NULL];
}

#pragma clang diagnostic pop

@end
