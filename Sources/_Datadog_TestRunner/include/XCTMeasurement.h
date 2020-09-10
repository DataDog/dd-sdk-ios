/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#import <Foundation/Foundation.h>

/// This interface has been generated using class-dump, since this header is not public
@interface XCTMeasurement : NSObject
{
    NSString *_identifier;
    NSString *_units;
    NSString *_name;
    NSDictionary *_baseline;
    NSDictionary *_defaultBaseline;
    NSArray *_measurements;
}

@property(copy) NSArray<NSNumber*> *measurements;
@property(copy) NSDictionary *defaultBaseline;
@property(copy) NSDictionary *baseline;
@property(copy) NSString *name;
@property(copy) NSString *units;
@property(copy) NSString *identifier;
- (id)init;
@end
