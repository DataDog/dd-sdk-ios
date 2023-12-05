/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
#include <sys/wait.h>
@import DatadogObjc;
@import DatadogTrace;

#import <Foundation/Foundation.h>

@interface MockDelegate : NSObject <NSURLSessionDataDelegate>
@end

@implementation MockDelegate
@end

@interface DDURLSessionInstrumentationTests_apiTests : XCTestCase
@end

@implementation DDURLSessionInstrumentationTests_apiTests

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

    [DDDatadog clearAllData];
    [DDDatadog flushAndDeinitialize];
}

- (void)testWorkflow {
    XCTestExpectation *expectation = [self expectationWithDescription:@"task completed"];
    DDURLSessionInstrumentationConfiguration *config = [[DDURLSessionInstrumentationConfiguration alloc] initWithDelegateClass:[MockDelegate class]];
    [DDURLSessionInstrumentation enableWithConfiguration:config];

    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                          delegate:[MockDelegate new] delegateQueue:nil];
    NSURLSessionTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"https://status.datadoghq.com"]
                                    completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [expectation fulfill];
    }];
    [task resume];

    [self waitForExpectationsWithTimeout:10 handler:nil];

    [DDURLSessionInstrumentation disableWithDelegateClass:[MockDelegate class]];
}

#pragma clang diagnostic pop

@end
