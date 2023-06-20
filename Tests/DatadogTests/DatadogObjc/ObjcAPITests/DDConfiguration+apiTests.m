/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;
@import DatadogCrashReporting;

// MARK: - DDUIKitRUMViewsPredicate

@interface CustomDDUIKitRUMViewsPredicate: NSObject
@end

@interface CustomDDUIKitRUMViewsPredicate () <DDUIKitRUMViewsPredicate>
@end

@implementation CustomDDUIKitRUMViewsPredicate
- (DDRUMView * _Nullable)rumViewFor:(UIViewController * _Nonnull)viewController { return nil; }
@end

// MARK: - DDUIKitRUMViewsPredicate

@interface CustomDDUIKitRUMUserActionsPredicate: NSObject
@end

@interface CustomDDUIKitRUMUserActionsPredicate () <DDUIKitRUMUserActionsPredicate>
@end

@implementation CustomDDUIKitRUMUserActionsPredicate
- (DDRUMAction * _Nullable)rumActionWithTargetView:(UIView * _Nonnull)targetView { return nil; }
- (DDRUMAction * _Nullable)rumActionWithPress:(enum UIPressType)type targetView:(UIView * _Nonnull)targetView { return nil; }

@end

// MARK: - DDDataEncryption

@interface CustomDDDataEncryption: NSObject <DDDataEncryption>
@end

@implementation CustomDDDataEncryption

- (NSData * _Nullable)decryptWithData:(NSData * _Nonnull)data error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    return data;
}

- (NSData * _Nullable)encryptWithData:(NSData * _Nonnull)data error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    return data;
}

@end

// MARK: - Tests

@interface DDConfiguration_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - only check if the interface is available to Objc.
 */
@implementation DDConfiguration_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

- (void)testDDEndpointAPI {
    [DDEndpoint eu];
    [DDEndpoint eu1];
    [DDEndpoint gov];
    [DDEndpoint us];
    [DDEndpoint us1];
    [DDEndpoint us1];
    [DDEndpoint us1_fed];
    [DDEndpoint us3];
    [DDEndpoint us5];
}

- (void)testDDBatchSizeAPI {
    DDBatchSizeSmall; DDBatchSizeMedium; DDBatchSizeLarge;
}

- (void)testDDUploadFrequencyAPI {
    DDUploadFrequencyRare; DDUploadFrequencyAverage; DDUploadFrequencyFrequent;
}

- (void)testDDConfigurationAPI {
    [DDConfiguration builderWithClientToken:@"" environment:@""];
    [DDConfiguration builderWithRumApplicationID:@"" clientToken:@"" environment:@""];
}

- (void)testDDConfigurationBuilderAPI {
    DDConfigurationBuilder *builder = [DDConfiguration builderWithClientToken:@"" environment:@""];
    [builder enableTracing:YES];
    [builder enableRUM:YES];
    [builder setWithEndpoint:[DDEndpoint us]];
    [builder setWithCustomRUMEndpoint:[NSURL new]];
    [builder trackURLSessionWithFirstPartyHosts:[NSSet setWithArray:@[]]];
    [builder setWithTracingSamplingRate:75];
    [builder setWithServiceName:@""];
    [builder setWithRumSessionsSamplingRate:50];
    [builder setOnRUMSessionStart:^(NSString * _Nonnull sessionId, BOOL isDiscarded) {}];
    [builder trackUIKitRUMViews];
    [builder trackUIKitRUMViewsUsing:[CustomDDUIKitRUMViewsPredicate new]];
    [builder trackUIKitRUMActions];
    [builder trackUIKitRUMActionsUsing:[CustomDDUIKitRUMUserActionsPredicate new]];
    [builder setRUMViewEventMapper:^DDRUMViewEvent * _Nonnull(DDRUMViewEvent * _Nonnull viewEvent) {
        viewEvent.view.url = @"";
        return viewEvent;
    }];
    [builder trackRUMLongTasks];
    [builder trackRUMLongTasksWithThreshold:10.0];
    [builder setRUMResourceEventMapper:^DDRUMResourceEvent * _Nullable(DDRUMResourceEvent * _Nonnull resourceEvent) {
        resourceEvent.resource.url = @"";
        return resourceEvent;
    }];
    [builder setRUMActionEventMapper:^DDRUMActionEvent * _Nullable(DDRUMActionEvent * _Nonnull actionEvent) {
        return nil;
    }];
    [builder setRUMErrorEventMapper:^DDRUMErrorEvent * _Nullable(DDRUMErrorEvent * _Nonnull errorEvent) {
        return nil;
    }];
    [builder setRUMLongTaskEventMapper:^DDRUMLongTaskEvent * _Nullable(DDRUMLongTaskEvent * _Nonnull longTaskEvent) {
        return nil;
    }];
    [builder setWithMobileVitalsFrequency:DDVitalsFrequencyFrequent];
    [builder setWithBatchSize:DDBatchSizeMedium];
    [builder setWithUploadFrequency:DDUploadFrequencyAverage];
    [builder setWithAdditionalConfiguration:@{}];
    [builder setWithEncryption:[CustomDDDataEncryption new]];

    [builder build];
}

- (void)testDatadogCrashReporterAPI {
    [DDCrashReporter enable];
}

#pragma clang diagnostic pop

@end
