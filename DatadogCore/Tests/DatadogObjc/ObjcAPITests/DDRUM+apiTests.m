/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;

// MARK: - DDUIKitRUMViewsPredicate

@interface CustomDDUIKitRUMViewsPredicate: NSObject
@end

@interface CustomDDUIKitRUMViewsPredicate () <DDUIKitRUMViewsPredicate>
@end

@implementation CustomDDUIKitRUMViewsPredicate
- (DDRUMView * _Nullable)rumViewFor:(UIViewController * _Nonnull)viewController { return nil; }
@end

// MARK: - DDUIKitRUMActionsPredicate

@interface CustomDDUIKitRUMActionsPredicate: NSObject
@end

@interface CustomDDUIKitRUMActionsPredicate () <DDUIKitRUMActionsPredicate>
@end

@implementation CustomDDUIKitRUMActionsPredicate
- (DDRUMAction * _Nullable)rumActionWithTargetView:(UIView * _Nonnull)targetView { return nil; }
- (DDRUMAction * _Nullable)rumActionWithPress:(enum UIPressType)type targetView:(UIView * _Nonnull)targetView { return nil; }

@end

// MARK: - DDRUM tests

@interface DDRUM_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - minimal assertions, mainly check if the interface is available to Objc.
 */
@implementation DDRUM_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

- (void)testDDRUMAPI {
    DDRUMConfiguration *config = [[DDRUMConfiguration alloc] initWithApplicationID:@"app-id"];
    [DDRUM enableWith:config];
}

- (void)testDDRUMConfigurationAPI {
    DDRUMConfiguration *config = [[DDRUMConfiguration alloc] initWithApplicationID:@"app-id"];
    XCTAssertEqual(config.applicationID, @"app-id");

    XCTAssertEqual(config.sessionSampleRate, 100);
    config.sessionSampleRate = 10;
    XCTAssertEqual(config.sessionSampleRate, 10);

    XCTAssertEqual(config.telemetrySampleRate, 20);
    config.telemetrySampleRate = 30;
    XCTAssertEqual(config.telemetrySampleRate, 30);

    XCTAssertNil(config.uiKitViewsPredicate);
    CustomDDUIKitRUMViewsPredicate *viewsPredicate = [CustomDDUIKitRUMViewsPredicate new];
    config.uiKitViewsPredicate = viewsPredicate;
    XCTAssertIdentical(config.uiKitViewsPredicate, viewsPredicate);

    XCTAssertNil(config.uiKitActionsPredicate);
    CustomDDUIKitRUMActionsPredicate *actionsPredicate = [CustomDDUIKitRUMActionsPredicate new];
    config.uiKitActionsPredicate = actionsPredicate;
    XCTAssertIdentical(config.uiKitActionsPredicate, actionsPredicate);

    DDRUMURLSessionTracking *urlSessionTracking = [DDRUMURLSessionTracking new];
    DDRUMFirstPartyHostsTracing *tracing;
    tracing = [[DDRUMFirstPartyHostsTracing alloc] initWithHosts:[NSSet new] sampleRate:20];
    tracing = [[DDRUMFirstPartyHostsTracing alloc] initWithHosts:[NSSet new]];
    tracing = [[DDRUMFirstPartyHostsTracing alloc] initWithHostsWithHeaderTypes:@{}];
    tracing = [[DDRUMFirstPartyHostsTracing alloc] initWithHostsWithHeaderTypes:@{} sampleRate:20];
    [urlSessionTracking setFirstPartyHostsTracing:tracing];
    [urlSessionTracking setResourceAttributesProvider:^NSDictionary<NSString *,id> * _Nullable(NSURLRequest * _Nonnull request,
                                                                                                NSURLResponse * _Nullable response,
                                                                                                NSData * _Nullable data,
                                                                                                NSError * _Nullable error) {
        return @{};
    }];

    XCTAssertTrue(config.trackFrustrations);
    config.trackFrustrations = NO;
    XCTAssertFalse(config.trackFrustrations);

    XCTAssertFalse(config.trackBackgroundEvents);
    config.trackBackgroundEvents = YES;
    XCTAssertTrue(config.trackBackgroundEvents);

    XCTAssertEqual(config.longTaskThreshold, 0.1);
    config.longTaskThreshold = 1;
    XCTAssertEqual(config.longTaskThreshold, 1);

    XCTAssertEqual(config.vitalsUpdateFrequency, DDRUMVitalsFrequencyAverage);
    config.vitalsUpdateFrequency = DDRUMVitalsFrequencyFrequent;
    XCTAssertEqual(config.vitalsUpdateFrequency, DDRUMVitalsFrequencyFrequent);
    config.vitalsUpdateFrequency = DDRUMVitalsFrequencyNever;
    XCTAssertEqual(config.vitalsUpdateFrequency, DDRUMVitalsFrequencyNever);

    [config setViewEventMapper:^DDRUMViewEvent * _Nonnull(DDRUMViewEvent * _Nonnull viewEvent) {
        viewEvent.view.url = @"";
        return viewEvent;
    }];
    [config setResourceEventMapper:^DDRUMResourceEvent * _Nullable(DDRUMResourceEvent * _Nonnull resourceEvent) {
        resourceEvent.resource.url = @"";
        return resourceEvent;
    }];
    [config setActionEventMapper:^DDRUMActionEvent * _Nullable(DDRUMActionEvent * _Nonnull actionEvent) {
        return nil;
    }];
    [config setErrorEventMapper:^DDRUMErrorEvent * _Nullable(DDRUMErrorEvent * _Nonnull errorEvent) {
        return nil;
    }];
    [config setLongTaskEventMapper:^DDRUMLongTaskEvent * _Nullable(DDRUMLongTaskEvent * _Nonnull longTaskEvent) {
        return nil;
    }];

    XCTAssertNil(config.onSessionStart);
    config.onSessionStart = ^(NSString * _Nonnull uuid, BOOL discarded) {};
    XCTAssertNotNil(config.onSessionStart);

    XCTAssertNil(config.customEndpoint);
    config.customEndpoint = [NSURL new];
    XCTAssertNotNil(config.customEndpoint);
}

#pragma clang diagnostic pop

@end
