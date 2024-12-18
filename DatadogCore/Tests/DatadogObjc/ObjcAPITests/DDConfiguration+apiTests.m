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

- (void)testDDSiteAPI {
    [DDSite eu1];
    [DDSite us1];
    [DDSite us1];
    [DDSite us1_fed];
    [DDSite us3];
    [DDSite us5];
}

- (void)testDDBatchSizeAPI {
    DDBatchSizeSmall; DDBatchSizeMedium; DDBatchSizeLarge;
}

- (void)testDDUploadFrequencyAPI {
    DDUploadFrequencyRare; DDUploadFrequencyAverage; DDUploadFrequencyFrequent;
}

- (void)testDDConfigurationBuilderAPI {
    DDConfiguration *configuration = [[DDConfiguration alloc] initWithClientToken:@"abc" env:@"def"];

    configuration.site = [DDSite us1];
    configuration.service = @"";
    configuration.bundle = [NSBundle mainBundle];
    configuration.batchSize = DDBatchSizeMedium;
    configuration.uploadFrequency = DDUploadFrequencyAverage;
    configuration.additionalConfiguration = @{@"additional": @"config"};
    [configuration setEncryption:[CustomDDDataEncryption new]];
    configuration.backgroundTasksEnabled = true;
}

- (void)testDatadogCrashReporterAPI {
    [DDCrashReporter enable];
}

#pragma clang diagnostic pop

@end
