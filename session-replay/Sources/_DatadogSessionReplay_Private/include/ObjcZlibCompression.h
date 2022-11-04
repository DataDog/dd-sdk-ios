/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#ifndef Header_h
#define Header_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface __dd_srprivate_ZlibCompression : NSObject

/// Compresses the data into ZLIB Compressed Data Format as described in IETF RFC 1950.
///
/// It uses `Z_SYNC_FLUSH` and `Z_FINISH` flags for flushing compressed data to the output. This
/// allows the receiver to concatenate succeeding chunks of compressed data and perform inflate only once
/// instead of decompressing each chunk individually.
///
/// - Parameters:
///   - data: source data to compress
///   - level: compression level (0 to 9)
///   - error: compression error if any
+ (NSData * _Nullable) compress:(NSData *)data level: (int)level error:(__autoreleasing NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif
