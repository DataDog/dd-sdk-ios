/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;
@import DatadogTrace;

@interface DDNSURLSessionDelegate_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - only check if the interface is available to Objc.
 */
@implementation DDNSURLSessionDelegate_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

- (void)setUp {
    [super setUp];

    DDConfiguration *configuration = [[DDConfiguration alloc] initWithClientToken:@"abc" env:@"def"];
    [DDDatadog initializeWithConfiguration:configuration trackingConsent:[DDTrackingConsent notGranted]];

    DDTraceConfiguration *config = [[DDTraceConfiguration alloc] init];
    DDTraceFirstPartyHostsTracing *tracing = [[DDTraceFirstPartyHostsTracing alloc] initWithHosts:[NSSet new] sampleRate:20];
    DDTraceURLSessionTracking *urlSessionTracking = [[DDTraceURLSessionTracking alloc] initWithFirstPartyHostsTracing:tracing];
    [config setURLSessionTracking:urlSessionTracking];
    [DDTrace enableWith:config];
}

- (void)tearDown {
    [super tearDown];

    [DDURLSessionInstrumentation disableWithDelegateClass:[DDNSURLSessionDelegate class]];
    [DDDatadog clearAllData];
    [DDDatadog flushAndDeinitialize];
}

- (void)testDDNSURLSessionDelegateAPI {
    [[DDNSURLSessionDelegate alloc] init];
    [[DDNSURLSessionDelegate alloc] initWithAdditionalFirstPartyHosts:[NSSet setWithArray:@[]]];
    [[DDNSURLSessionDelegate alloc] initWithAdditionalFirstPartyHostsWithHeaderTypes:@{
        @"host": [[NSSet alloc] initWithObjects:[DDTracingHeaderType datadog], nil]
    }];
}

#pragma clang diagnostic pop

@end
