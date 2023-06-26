/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;
@import DatadogCrashReporting;

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
}

- (void)testDDConfigurationBuilderAPI {
    DDConfigurationBuilder *builder = [DDConfiguration builderWithClientToken:@"" environment:@""];
    [builder setWithEndpoint:[DDEndpoint us]];
    [builder setWithServiceName:@""];
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
