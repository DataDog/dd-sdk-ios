/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;

@interface DDGlobal_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - only check if the interface is available to Objc.
 */
@implementation DDGlobal_apiTests

- (void)testSharedTracerAPI {
    id tracer = DDGlobal.sharedTracer;
    DDGlobal.sharedTracer = tracer;
}

- (void)testRUMAPI {
    id rum = DDGlobal.rum;
    DDGlobal.rum = rum;
}

@end
