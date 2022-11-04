/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <zlib.h>
#import <Foundation/Foundation.h>
#import "ObjcZlibCompression.h"

@implementation __dd_srprivate_ZlibCompression

+ (NSData * _Nullable) compress:(NSData *)data level: (int)level error:(__autoreleasing NSError **)error {
    if ([data length] == 0) {
        return data;
    }
    
    NSMutableData *compressedData = [NSMutableData new];

    // Configure initial state of zlib:
    // - Setting `Z_NULL` for memory allocation routines means that zlib will use its default implementations.
    // - This mutable state is shared between our code and zlib. In later do / while iterations zlib will leverage
    // it to empower `deflate()` calls and walk through original `data` with `next_in` and `avail_in`.
    // - A good explanation of how to use `z_stream`: https://zlib.net/zlib_how.html
    // - A practical explanation of different ZLIB APIs: https://github.com/madler/zlib/blob/cacf7f1d4e3d44d871b605da3b647f07d718623f/zlib.h
    z_stream strm;
    strm.zalloc    = Z_NULL;
    strm.zfree     = Z_NULL;
    strm.opaque    = Z_NULL;
    strm.total_out = 0; // total number of bytes output so far
    strm.next_in   = (Bytef*)[data bytes]; // pointer to next input byte
    strm.avail_in  = (uInt)[data length]; // number of bytes available at next_in

    int result; // zlib return codes
    result = deflateInit(&strm, level);

    if (result != Z_OK) {
        deflateEnd(&strm); // free the allocated zlib state
        *error = [self errorFor:result failureReason:@"Received error code from `deflateInit()`"];
        return nil;
    }
    
    // CHUNK is the buffer size for feeding data to and pulling data from the zlib routines.
    // Larger buffers are more efficient.
    uInt CHUNK = 16384; // 16kB
    unsigned char outputBuffer[CHUNK];
    
    int flush; // current flushing state for deflate()
    unsigned have; // amount of data returned from deflate()
    
    do {
        strm.next_out = outputBuffer;
        strm.avail_out = CHUNK;
                
        flush = strm.avail_in == 0 ? Z_FINISH: Z_SYNC_FLUSH; // if no more data to compress flush with `Z_FINISH`
        result = deflate(&strm, flush);
        
        have = CHUNK - strm.avail_out;
        [compressedData appendBytes:outputBuffer length:have];
    } while ( result == Z_OK );

    if (result != Z_STREAM_END) {
        deflateEnd(&strm); // free the allocated zlib state
        *error = [self errorFor:result failureReason:@"Received error code from `deflate()`"];
        return nil;
    }

    deflateEnd(&strm); // free the allocated zlib state
  
    return compressedData;
}

+ (NSError * _Nonnull)errorFor:(int)status failureReason:(NSString*)failureReason {
    NSDictionary *userInfo = @{
        NSLocalizedFailureReasonErrorKey: failureReason,
        NSLocalizedDescriptionKey: [self errorLabelFor:status],
    };
    return [NSError errorWithDomain:@"com.datadoghq.zlib-compression" code:status userInfo:userInfo];
}

+ (NSString * _Nonnull)errorLabelFor:(int)status {
    switch (status) {
    case Z_ERRNO:           return @"Z_ERRNO";
    case Z_STREAM_ERROR:    return @"Z_STREAM_ERROR";
    case Z_DATA_ERROR:      return @"Z_DATA_ERROR";
    case Z_MEM_ERROR:       return @"Z_MEM_ERROR";
    case Z_BUF_ERROR:       return @"Z_BUF_ERROR";
    case Z_VERSION_ERROR:   return @"Z_VERSION_ERROR";
    default:                return [NSString stringWithFormat:@"Unknown error code: %d", status];
    }
}

@end
